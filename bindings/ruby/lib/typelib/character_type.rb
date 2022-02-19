module Typelib
    # Base class for character types
    class CharacterType < Type
        def self.subclass_initialize
            super

            # This is only a hint for the rest of Typelib. The actual
            # convertion is done internally by Typelib
            convert_to_ruby(String, recursive: false, builtin: true)
        end

        def self.from_ruby(value)
            v = new
            v.typelib_from_ruby(value)
            v
        rescue TypeError => e
            raise Typelib::UnknownConversionRequested.new(value, self),
                  "cannot convert #{value} (#{value.class}) to #{self}", e.backtrace
        end

        # Returns the description of a type using only simple ruby objects
        # (Hash, Array, Numeric and String).
        #
        #    { 'name' => TypeName,
        #      'class' => 'EnumType',
        #      'integer' => Boolean,
        #      # Only for integral types
        #      'unsigned' => Boolean,
        #      # Unlike with the other types, the 'size' field is always present
        #      'size' => SizeOfTypeInBytes
        #    }
        #
        # @option (see Type#to_h)
        # @return (see Type#to_h)
        def self.to_h(options = {})
            super.merge(size: size)
        end

        # Returns the Array#pack code that matches this type
        #
        # The endianness is the one of the local OS
        def self.pack_code
            "C"
        end

        # (see Type#to_simple_value)
        def to_simple_value(_options = {})
            to_ruby
        end
    end
end

