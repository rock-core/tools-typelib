module Typelib
    # An object that gives direct access to a set of values child of a root
    class Accessor
        # The set of paths describing the required fields
        attr_reader :paths

        def initialize(paths = [])
            @paths = paths
        end

        # Builds an accessor that gives access to all the fields whose type
        # matches the given block in +type_model+
        def self.find_in_type(type_model, getter = :raw_get, iterator = :raw_each, &block)
            matches = traverse_and_find_in_type(type_model, getter, iterator, &block) || []
            matches = matches.sort_by { |p| p.size }
            Accessor.new(matches)
        end

        def self.traverse_and_find_in_type(
            type_model, getter = :raw_get, iterator = :raw_each,
            &block
        )
            result = []

            # First, check if type_model itself is wanted
            result << Path.new([]) if yield(type_model)

            if type_model <= Typelib::CompoundType
                type_model.each_field do |field_name, field_type|
                    matches = traverse_and_find_in_type(
                        field_type, getter, iterator, &block
                    )
                    if matches
                        matches.each do |path|
                            path.unshift_call(getter, field_name)
                        end
                        result.concat(matches)
                    end
                end
            elsif type_model <= Typelib::ArrayType || type_model <= Typelib::ContainerType
                matches = traverse_and_find_in_type(
                    type_model.deference, getter, iterator, &block
                )
                if matches
                    matches.each do |path|
                        path.unshift_iterate(iterator)
                    end
                    result.concat(matches)
                end
            end
            result
        end

        def each(root)
            return enum_for(:each, root) unless block_given?

            paths.each do |p|
                p.resolve(root).each do |obj|
                    yield(obj)
                end
            end
            self
        end
        include Enumerable
    end
end
