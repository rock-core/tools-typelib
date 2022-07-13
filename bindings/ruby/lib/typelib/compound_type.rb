# frozen_string_literal: true

module Typelib
    # Base class for compound types (structs, unions)
    #
    # See the Typelib module documentation for an overview about how types are
    # values are represented.
    class CompoundType < Type
        # Prefix for all instance variables based on the type fields
        FIELD_NAME_PREFIX = "__typelib_"

        # Module used to extend frozen values
        module Freezer
            def set(*)
                raise TypeError, "frozen object"
            end

            def raw_set(*)
                raise TypeError, "frozen object"
            end

            def raw_set_field(*)
                raise TypeError, "frozen object"
            end
        end

        # Module used to extend invalidated values
        module Invalidate
            def set(*)
                raise TypeError, "invalidated object"
            end

            def get(*)
                raise TypeError, "invalidated object"
            end

            def raw_get(*)
                raise TypeError, "invalidated object"
            end

            def raw_get_cached(*)
                raise TypeError, "invalidated object"
            end

            def raw_set(*)
                raise TypeError, "invalidated object"
            end

            def raw_get_field(*)
                raise TypeError, "invalidated object"
            end

            def raw_set_field(*)
                raise TypeError, "invalidated object"
            end
        end

        # Call to freeze the object, i.e. to make it readonly
        def freeze
            super
            extend Freezer
            self
        end

        # Call to invalidate the object, i.e. to forbid any R/W access to it.
        # This is used in the framework when the underlying memory zone has been
        # made invalid by some operation (as e.g. container resizing)
        def invalidate
            super
            extend Invalidate
            self
        end

        def freeze_children
            super
            @fields.each_value(&:freeze)
        end

        def invalidate_children
            super
            @fields.each_value(&:invalidate)
            @fields.clear
        end

        module CustomConvertionsHandling
            def invalidate_changes_from_converted_types
                super()
                self.class.converted_fields.each do |field_name|
                    instance_variable_set("@#{FIELD_NAME_PREFIX}#{field_name}", nil)
                    @fields[field_name]&.invalidate_changes_from_converted_types
                end
            end

            def apply_changes_from_converted_types
                super()
                self.class.converted_fields.each do |field_name|
                    value = instance_variable_get("@#{FIELD_NAME_PREFIX}#{field_name}")
                    unless value.nil?
                        @fields[field_name]&.apply_changes_from_converted_types
                        set_field(field_name, value)
                    end
                end
            end

            def dup
                new_value = super()
                self.class.converted_fields.each do |field_name|
                    ivar = "@#{FIELD_NAME_PREFIX}#{field_name}"
                    instance_variable_set(ivar, instance_variable_get(ivar).dup)
                end
                new_value
            end
        end

        # Internal method used to initialize a compound from a hash
        def set_hash(hash) # :nodoc:
            hash.each do |field_name, field_value|
                set_field(field_name, field_value)
            end
        end

        # Internal method used to initialize a compound from an array. The array
        # elements are supposed to be given in the field order
        def set_array(array) # :nodoc:
            fields = self.class.fields
            array.each_with_index do |value, i|
                set_field(fields[i][0], value)
            end
        end

        # Initializes this object to the pointer +ptr+, and initializes it
        # to +init+. Valid values for +init+ are:
        # * a hash, in which case it is a { field_name => field_value } hash
        # * an array, in which case the fields are initialized in order
        # Note that a compound should be either fully initialized or not initialized
        def typelib_initialize
            super
            # A hash in which we cache Type objects for each of the structure fields
            @fields = {}
            @field_types = self.class.field_types
        end

        def raw_each_field
            return enum_for(__method__) unless block_given?

            self.class.each_field do |field_name, _|
                yield(field_name, raw_get(field_name))
            end
        end

        def each_field
            return enum_for(__method__) unless block_given?

            self.class.each_field do |field_name, _|
                yield(field_name, get(field_name))
            end
        end

        @fields = []
        @field_types = {}
        @field_metadata = {}
        class << self
            # Check if this type can be used in place of +typename+
            # In case of compound types, we check that either self, or
            # the first element field is +typename+
            def is_a?(typename)
                super || (!fields.empty? && fields[0].last.is_a?(typename))
            end

            # The set of fields that are converted to a different type when
            # accessed from Ruby, as a set of names
            attr_reader :converted_fields

            @@custom_convertion_modules = {}
            def custom_convertion_module(converted_fields)
                @@custom_convertion_modules[converted_fields] ||=
                    Module.new do
                        include CustomConvertionsHandling

                        converted_fields.each do |field_name|
                            attr_name = "@#{FIELD_NAME_PREFIX}#{field_name}"
                            define_method("#{field_name}=") do |value|
                                instance_variable_set(attr_name, value)
                            end
                            define_method(field_name) do
                                v = instance_variable_get(attr_name)
                                if !v.nil?
                                    v
                                else
                                    v = get(field_name)
                                    instance_variable_set(attr_name, v)
                                end
                            end
                        end
                    end
            end

            # Creates a module that can be used to extend a certain Type class to
            # take into account the convertions.
            #
            # I.e. if a convertion is declared as
            #
            #   convert_to_ruby '/base/Time', :to => Time
            #
            # and the type T is a structure with a field of type /base/Time, then
            # if
            #
            #   type = registry.get('T')
            #   type.extend_for_custom_convertions
            #
            # then
            #   t = type.new
            #   t.time => Time instance
            #   t.time => the same Time instance
            def extend_for_custom_convertions
                super if defined? super

                unless converted_fields.empty?
                    self.contains_converted_types = true
                    # Make it local so that it can be accessed in the module we define below
                    converted_fields = self.converted_fields
                    type_klass = self

                    converted_fields = Typelib.filter_methods_that_should_not_be_defined(
                        self, type_klass, converted_fields, Type::ALLOWED_OVERLOADINGS, nil, false
                    )

                    m = custom_convertion_module(converted_fields)
                    include(m)
                end
            end

            @@access_method_modules = {}
            def access_method_module(full_fields_names, converted_field_names)
                @@access_method_modules[[full_fields_names, converted_field_names]] ||=
                    Module.new do
                        full_fields_names.each do |name|
                            define_method(name) { get(name) }
                            define_method("#{name}=") { |value| set(name, value) }
                            define_method("raw_#{name}") { raw_get(name) }
                            define_method("raw_#{name}=") { |value| raw_set(name, value) }
                        end
                        converted_field_names.each do |name|
                            define_method("raw_#{name}") { raw_get(name) }
                            define_method("raw_#{name}=") { |value| raw_set(name, value) }
                        end
                    end
            end

            # Called by the extension to initialize the subclass
            # For each field, it creates getters and setters on
            # the object, and a getter in the singleton class
            # which returns the field type
            def subclass_initialize
                @field_types = {}
                @fields = []
                @field_metadata = {}
                get_fields.each do |name, offset, type, metadata|
                    name.force_encoding("ASCII")
                    field_types[name] = type
                    field_types[name.to_sym] = type
                    fields << [name, type]
                    field_metadata[name] = metadata
                end

                converted_fields = []
                full_fields = []
                each_field do |name, type|
                    if type.contains_converted_types?
                        converted_fields << name
                    else
                        full_fields << name
                    end
                end
                converted_fields = converted_fields.sort
                full_fields = full_fields.sort

                @converted_fields = converted_fields
                overloaded_converted_fields = filter_methods_that_should_not_be_defined(converted_fields, false)
                overloaded_full_fields = filter_methods_that_should_not_be_defined(full_fields, true)
                m = access_method_module(overloaded_full_fields, overloaded_converted_fields)
                include(m)

                super if defined? super

                unless convertions_from_ruby.key?(Hash)
                    convert_from_ruby Hash do |value, expected_type|
                        result = expected_type.new
                        result.set_hash(value)
                        result
                    end
                end

                unless convertions_from_ruby.key?(Array)
                    convert_from_ruby Array do |value, expected_type|
                        result = expected_type.new
                        result.set_array(value)
                        result
                    end
                end
            end

            # Returns true if this compound has no fields
            def empty?
                fields.empty?
            end

            # Returns the offset, in bytes, of the given field
            def offset_of(fieldname)
                fieldname = fieldname.to_str
                get_fields.each do |name, offset, _|
                    return offset if name == fieldname
                end
                raise "no such field #{fieldname} in #{self}"
            end

            # The list of fields
            attr_reader :fields
            # A name => type map of the types of each fiel
            attr_reader :field_types
            # A name => object mapping of the field metadata objects
            attr_reader :field_metadata
            # Returns the type of +name+
            def [](name)
                if (result = field_types[name])
                    result
                else
                    raise ArgumentError, "#{name} is not a field of #{self.name}"
                end
            end

            # True if the given field is defined
            def has_field?(name)
                field_types.key?(name)
            end

            # Iterates on all fields
            #
            # @yield [name,type] the fields of this compound
            # @return [void]
            def each_field
                return enum_for(__method__) unless block_given?

                fields.each { |field| yield(*field) }
            end

            # Returns the description of a type using only simple ruby objects
            # (Hash, Array, Numeric and String).
            #
            #    { 'name' => TypeName,
            #      'class' => NameOfTypeClass, # CompoundType, ...
            #       # The content of 'element' is controlled by the :recursive option
            #      'fields' => [{ 'name' => FieldName,
            #                     # the 'type' field is controlled by the
            #                     # 'recursive' option
            #                     'type' => FieldType,
            #                     # 'offset' is present only if :layout_info is
            #                     # true
            #                     'offset' => FieldOffsetInBytes
            #                   }],
            #      'size' => SizeOfTypeInBytes # Only if :layout_info is true
            #    }
            #
            # @option (see Type#to_h)
            # @return (see Type#to_h)
            def to_h(options = {})
                fields = []
                if options[:recursive]
                    each_field.map do |name, type|
                        fields << Hash[name: name, type: type.to_h(options)]
                    end
                else
                    each_field.map do |name, type|
                        fields << Hash[name: name, type: type.to_h_minimal(options)]
                    end
                end

                if options[:layout_info]
                    fields.each do |field|
                        field[:offset] = offset_of(field[:name])
                    end
                end
                super.merge(fields: fields)
            end

            def pretty_print_common(pp) # :nodoc:
                all_fields = get_fields.to_a
                if all_fields.empty?
                    pp.text "{ }"
                    return
                end

                pp.text "{"
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(all_fields) do |field|
                        yield(*field)
                    end
                end

                pp.breakable
                pp.text "}"
            end

            def pretty_print(pp, verbose = false) # :nodoc:
                super(pp)
                pp.text " "
                pretty_print_common(pp) do |name, offset, type, metadata|
                    if (doc = metadata.get("doc").first)
                        pp.breakable if pp_doc(pp, doc)
                    end
                    pp.text name
                    if verbose
                        pp.text "[#{offset}] <"
                    else
                        pp.text " <"
                    end
                    pp.nest(2) do
                        type.pretty_print(pp, false)
                    end
                    pp.text ">"
                end
            end
        end

        def pretty_print(pp) # :nodoc:
            apply_changes_from_converted_types
            self.class.pretty_print_common(pp) do |name, offset, type|
                pp.text name
                pp.text "="
                get_field(name).pretty_print(pp)
            end
        end

        # Returns true if +name+ is a valid field name. It can either be given
        # as a string or a symbol
        def has_field?(name)
            @field_types.key?(name)
        end

        def [](name)
            get(name)
        end

        # Returns the value of the field +name+
        def get_field(name)
            get(name)
        end

        def raw_get_field(name)
            raw_get(name)
        end

        def get(name)
            if @fields[name]
                Typelib.to_ruby(@fields[name], @field_types[name])
            else
                value = typelib_get_field(name.to_s, false)
                if value.kind_of?(Typelib::Type)
                    @fields[name] = value
                    Typelib.to_ruby(value, @field_types[name])
                else value
                end
            end
        end

        def raw_get(name)
            @fields[name] ||= typelib_get_field(name, true)
        end

        def raw_get_cached(name)
            @fields[name]
        end

        def raw_set_field(name, value)
            raw_set(name, value)
        end

        def raw_set(name, value)
            if value.kind_of?(Type)
                attribute = raw_get(name)
                # If +value+ is already a typelib value, just do a plain copy
                return Typelib.copy(attribute, value) if attribute.kind_of?(Typelib::Type)
            end
            typelib_set_field(name, value)
        rescue ArgumentError => e
            if e.message =~ /^no field \w+ in /
                raise e, (e.message + " in #{name}(#{self.class.name})"), e.backtrace
            else
                raise e, (e.message + " while setting #{name} in #{self.class.name}"), e.backtrace
            end
        end

        def set_field(name, value)
            set(name, value)
        end

        def []=(name, value)
            set(name, value)
        end

        # Sets the value of the field +name+. If +value+ is a hash, we expect
        # that the field is a compound type and initialize it using the keys of
        # +value+ as field names
        def set(name, value)
            unless has_field?(name)
                raise ArgumentError, "#{self.class.name} has no field called #{name}"
            end

            value = Typelib.from_ruby(value, @field_types[name])
            raw_set_field(name.to_s, value)
        rescue TypeError => e
            raise e, "#{e.message} for #{self.class.name}.#{name}", e.backtrace
        end

        # (see Type#to_simple_value)
        #
        # Compound types are returned as a hash from the field name (as a
        # string) to the converted field value.
        def to_simple_value(options = {})
            apply_changes_from_converted_types
            result = {}
            raw_each_field { |name, v| result[name.to_s] = v.to_simple_value(options) }
            result
        end
    end
end
