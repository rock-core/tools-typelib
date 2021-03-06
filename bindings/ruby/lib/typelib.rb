# frozen_string_literal: true

require "utilrb/object/address"
require "utilrb/logger"
require "utilrb/kernel/options"
require "utilrb/module/attr_predicate"
require "utilrb/module/const_defined_here_p"
require "delegate"
require "pp"
require "facets/string/camelcase"
require "set"
require "base64"
require "backports/2.4.0/true_class/dup"
require "backports/2.4.0/false_class/dup"
require "backports/2.4.0/fixnum/dup"
require "backports/2.4.0/float/dup"
require "backports/2.4.0/nil_class/dup"

Infinity = Float::INFINITY unless defined?(Infinity)
Inf = Float::INFINITY unless defined?(Inf)
NaN = Float::NAN unless defined?(NaN)

# Typelib is the main module for Ruby-side Typelib functionality.
#
# Typelib allows to do two things:
#
# * represent types (it is a <i>type system</i>). These representations will be
#   referred to as _types_ in the documentation.
# * manipulate in-memory values represented by these types. These are
#   referred to as _values_ in the documentation.
#
# As types may depend on each other (for instance, a structure depend on the
# types used to define its fields), Typelib maintains a consistent set of types
# in a so-called registry. Types in a registry can only refer to other types in
# the same registry.
#
# On the Ruby side, a _type_ is represented as a subclass of one of the
# specialized subclasses of Typelib::Type (depending of what kind of type it
# is). I.e.  a _type_ itself is a class, and the methods that are available on
# Type objects are the singleton methods of the Type class (or its specialized
# subclasses).  Then, a value is simply an instance of that same class.
#
# Typelib specializes for the following kinds of types:
#
# * structures and unions (Typelib::CompoundType)
# * static length arrays (Typelib::ArrayType)
# * dynamic containers (Typelib::ContainerType)
# * mappings from strings to numerical values (Typelib::EnumType)
#
# In other words:
#
#   registry = <load the registry>
#   type  = registry.get 'A' # Get the Type subclass that represents the A
#                            # structure
#   value = type.new         # Create an uninitialized value of type A
#
#   value.class == type # => true
#   type.ancestors # => [type, Typelib::CompoundType, Typelib::Type]
#
# Each class representing a type can be further specialized using
# Typelib.specialize_model and Typelib.specialize
#
module Typelib
    extend Logger::Root("Typelib", Logger::WARN)

    TYPELIB_LIB_DIR = File.expand_path("typelib", File.dirname(__FILE__))

    class << self
        # If true (the default), typelib will load its type plugins. Otherwise,
        # it will not
        attr_predicate :load_type_plugins, true
    end
    @load_type_plugins = true

    # The namespace separator character used by Typelib
    NAMESPACE_SEPARATOR = "/"

    # Returns the basename part of +name+, i.e. the type name
    # without the namespace part.
    #
    # See also Type.basename
    def self.basename(name, separator = Typelib::NAMESPACE_SEPARATOR)
        name = do_basename(name)
        if separator && separator != Typelib::NAMESPACE_SEPARATOR
            name.gsub!(Typelib::NAMESPACE_SEPARATOR, separator)
        end
        name
    end

    # Returns the namespace part of +name+.  If +separator+ is
    # given, the namespace components are separated by it, otherwise,
    # the default of Typelib::NAMESPACE_SEPARATOR is used. If nil is
    # used as new separator, no change is made either.
    def self.namespace(
        name, separator = Typelib::NAMESPACE_SEPARATOR, remove_leading = false
    )
        ns = do_namespace(name)
        ns = ns[1..-1] if remove_leading
        if separator && separator != Typelib::NAMESPACE_SEPARATOR
            ns.gsub!(Typelib::NAMESPACE_SEPARATOR, separator)
        end
        ns
    end

    class << self
        attr_predicate :warn_about_helper_method_clashes?, true
    end
    @warn_about_helper_method_clashes = true

    def self.filter_methods_that_should_not_be_defined(
        _on, reference_class, names, allowed_overloadings, msg_name, with_raw
    )
        names.find_all do |n|
            candidates = [n, "#{n}="]
            candidates.concat(["raw_#{n}", "raw_#{n}="]) if with_raw
            candidates.all? do |method_name|
                if !reference_class.method_defined?(method_name) ||
                   allowed_overloadings.include?(method_name)
                    true
                elsif warn_about_helper_method_clashes?
                    msg_name ||= "instances of #{reference_class.name}"
                    Typelib.warn "NOT defining #{candidates.join(', ')} on #{msg_name} "\
                                 "as it would overload a necessary method"
                    false
                end
            end
        end
    end

    def self.define_method_if_possible(
        on, reference_class, name, allowed_overloadings = [], msg_name = nil, &block
    )
        if !reference_class.method_defined?(name) || allowed_overloadings.include?(name)
            on.send(:define_method, name, &block)
            true
        elsif warn_about_helper_method_clashes?
            msg_name ||= "instances of #{reference_class.name}"
            Typelib.warn "NOT defining #{name} on #{msg_name} as it would overload "\
                         "a necessary method"
            false
        end
    end

    TYPELIB_RUBY_PLUGIN_PATH_DEPRECATION_WARNING = <<~MSG
        WARN: integrating typelib plugin using the TYPELIB_RUBY_PLUGIN_PATH environment
        WARN: variable is deprecated. Just put a file called typelib_plugin.rb into a
        WARN: subfolder from the RUBYLIB (e.g. base/typelib_plugin.rb)
    MSG

    @loaded_typelib_plugins = false

    def self.load_typelib_plugins(force: false)
        return if !force && @loaded_typelib_plugins

        found_by_gem = Set.new
        Gem.find_files("*/typelib_plugin.rb").each do |plugin_path|
            found_by_gem << plugin_path
            require plugin_path
        end

        @loaded_typelib_plugins = true

        if !ENV["TYPELIB_RUBY_PLUGIN_PATH"] ||
           (@typelib_plugin_path == ENV["TYPELIB_RUBY_PLUGIN_PATH"])
            return
        end

        ENV["TYPELIB_RUBY_PLUGIN_PATH"].split(":").each do |dir|
            specific_file = File.join(dir, "typelib_plugin.rb")
            if File.exist?(specific_file)
                if require(specific_file)
                    TYPELIB_RUBY_PLUGIN_PATH_DEPRECATION_WARNING
                        .split("\n").each { |line| warn line }
                    warn "WARN: Offending file: #{specific_file}"
                end
            else
                warned = false
                Dir.glob(File.join(dir, "*.rb")).sort.each do |file|
                    unless warned
                        warned = true
                        TYPELIB_RUBY_PLUGIN_PATH_DEPRECATION_WARNING
                            .split("\n").each { |line| warn line }
                        warn "WARN: Offending file: #{file}"
                    end
                    require file
                end
            end
        end

        @typelib_plugin_path = ENV["TYPELIB_RUBY_PLUGIN_PATH"].dup
    end
    @typelib_plugin_path = nil
end

# Type models
require "typelib/type"
require "typelib/indirect_type"
require "typelib/opaque_type"
require "typelib/pointer_type"
require "typelib/numeric_type"
require "typelib/array_type"
require "typelib/compound_type"
require "typelib/enum_type"
require "typelib/container_type"
require "typelib/metadata"

require "typelib/registry"
require "typelib/registry_export"
require "typelib/cxx_registry"
require "typelib/specializations"
require "typelib_ruby"

Typelib::Type.instance_variable_set :@metadata, Typelib::MetaData.new
Typelib::IndirectType.instance_variable_set :@metadata, Typelib::MetaData.new
Typelib::OpaqueType.instance_variable_set :@metadata, Typelib::MetaData.new
Typelib::PointerType.instance_variable_set :@metadata, Typelib::MetaData.new
Typelib::NumericType.instance_variable_set :@metadata, Typelib::MetaData.new
Typelib::ArrayType.instance_variable_set :@metadata, Typelib::MetaData.new
Typelib::CompoundType.instance_variable_set :@metadata, Typelib::MetaData.new
Typelib::EnumType.instance_variable_set :@metadata, Typelib::MetaData.new
Typelib::ContainerType.instance_variable_set :@metadata, Typelib::MetaData.new

require "typelib/standard_convertions"

require "typelib/path"
require "typelib/accessor"

class Class # :nodoc:
    def to_ruby(value)
        value
    end
end

module Typelib
    # Generic method that converts a Typelib value into the corresponding Ruby
    # value.
    def self.to_ruby(value, original_type = nil)
        if value.respond_to?(:apply_changes_from_converted_types)
            value.apply_changes_from_converted_types
        end
        (original_type || value.class).to_ruby(value)
    end

    # Proper copy of a value to another. +to+ and +from+ do not have to be from the
    # same registry, as long as the types can be casted into each other
    #
    # @return [Type] the target value
    def self.copy(to, from)
        if to.invalidated?
            raise TypeError, "cannot copy, the target has been invalidated"
        elsif from.invalidated?
            raise TypeError, "cannot copy, the source has been invalidated"
        end

        if to.respond_to?(:invalidate_changes_from_converted_types)
            to.invalidate_changes_from_converted_types
        end
        if from.respond_to?(:apply_changes_from_converted_types)
            from.apply_changes_from_converted_types
        end

        to.allocating_operation do
            do_copy(to, from)
        end
    end

    def self.compare(a, b)
        if a.respond_to?(:apply_changes_from_converted_types)
            a.apply_changes_from_converted_types
        end
        if b.respond_to?(:apply_changes_from_converted_types)
            b.apply_changes_from_converted_types
        end
        do_compare(a, b)
    end

    # Exception raised when Typelib.from_ruby is called but the value cannot be
    # converted to the requested type
    class UnknownConversionRequested < ArgumentError
        attr_reader :value, :type
        def initialize(value, type)
            @value = value
            @type = type
        end

        def pretty_print(pp)
            pp.text "conversion from #{value} of type #{value.class} to #{type} "\
                    "requested, but there are no known conversion that apply"
        end
    end

    # Exception raised when Typelib.from_ruby encounters a value that has the
    # same type name than the requested type, but the types differ
    class ConversionToMismatchedType < UnknownConversionRequested
        def pretty_print(pp)
            pp.text "type mismatch when trying to convert #{value} to #{type}"
            pp.breakable
            pp.text "the value's definition is "
            value.class.pretty_print(pp, true)
            pp.breakable
            pp.text "the target type's definition is "
            type.pretty_print(pp, true)
        end
    end

    # Initializes +expected_type+ from +arg+, where +arg+ can either be a value
    # of expected_type, a value that can be casted into a value of
    # expected_type, or a Ruby value that can be converted into a value of
    # +expected_type+.
    def self.from_ruby(arg, expected_type)
        if arg.respond_to?(:apply_changes_from_converted_types)
            arg.apply_changes_from_converted_types
        end

        return arg if arg.kind_of?(expected_type)
        if arg.class < Type && arg.class.casts_to?(expected_type)
            return arg.cast(expected_type)
        end

        if (convertion = expected_type.convertions_from_ruby[arg.class])
            converted = convertion.call(arg, expected_type)
        elsif expected_type.respond_to?(:from_ruby)
            converted = expected_type.from_ruby(arg)
        elsif expected_type < NumericType
            return arg
        elsif arg.class.name != expected_type.name
            raise UnknownConversionRequested.new(arg, expected_type),
                  "types differ and there are not convertions from one "\
                  "to the other: #{arg.class.name} <-> #{expected_type.name}"
        else
            raise ConversionToMismatchedType.new(arg, expected_type),
                  "the types have the same name but different definitions: "\
                  "#{arg.class.name} <-> #{expected_type.name}"
        end

        converted.apply_changes_from_converted_types unless converted.eql?(arg)
        converted
    end

    class << self
        # Count of the memory allocated because of the containers
        #
        # @return [Integer] the allocated memory in bytes
        attr_accessor :allocated_memory

        # Value of {allocated_memory} the last time the garbage collector got
        # started because of typelib
        attr_reader :last_allocated_memory

        # Threshold of the memory allocated by Typelib that should trigger a
        # call to the garbage collector
        #
        # @return [Integer] the threshold in bytes
        attr_accessor :allocated_memory_threshold

        # Registers some memory allocated by typelib
        def add_allocated_memory(count)
            self.allocated_memory += count
            unless (allocated_memory - last_allocated_memory) > allocated_memory_threshold
                return
            end

            GC.start
            @last_allocated_memory = allocated_memory
        end
    end
    @allocated_memory = 0
    @last_allocated_memory = 0
    @allocated_memory_threshold = 50 * 1024**2

    # A raw, untyped, memory zone
    class MemoryZone
        def to_s
            "#<MemoryZone:#{object_id} ptr=0x#{zone_address.to_s(16)}>"
        end
    end
end

require "typelib/cxx"

# Finally, set guard types on the root classes
module Typelib
    class Type # :nodoc:
        initialize_base_class
    end
    class NumericType # :nodoc:
        initialize_base_class
    end
    class EnumType # :nodoc:
        initialize_base_class
    end
    class CompoundType # :nodoc:
        initialize_base_class
    end
    class ContainerType # :nodoc:
        initialize_base_class
    end
    class ArrayType # :nodoc:
        initialize_base_class
    end
    class IndirectType # :nodoc:
        initialize_base_class
    end
    class OpaqueType # :nodoc:
        initialize_base_class
    end
    class PointerType # :nodoc:
        initialize_base_class
    end
end
