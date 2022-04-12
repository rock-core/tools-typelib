require "typelib/test"

class TC_SpecializedTypes < Minitest::Test
    SRCDIR = File.expand_path("..", File.dirname(__FILE__))

    include Typelib
    def setup
        super

        @registry = Typelib::Registry.new
        Typelib::Registry.add_standard_cxx_types(@registry)
        registry.create_container "/std/vector", "/int8_t"
        registry.create_compound "/compounds/Subfield" do |t|
            t.plain = "/int8_t"
            t.vector = "/std/vector</int8_t>"
        end
        registry.create_container "/std/vector", "/compounds/Subfield"
        @compound_t = registry.create_compound "/compounds/Test" do |t|
            t.plain = "/int8_t"
            t.compound = "/compounds/Subfield"
            t.plain_vector = "/std/vector</int8_t>"
            t.vector = "/std/vector</compounds/Subfield>"
        end

        @array_t = registry.create_array "/compounds/Test", 3

        @root_t = registry.create_compound "/Root" do |t|
            t.compound = compound_t
            t.array = array_t
        end
    end

    attr_reader :registry
    attr_reader :compound_t
    attr_reader :array_t
    attr_reader :root_t

    def test_base_classes_have_metadata
        assert_kind_of Typelib::MetaData, Typelib::IndirectType.metadata
        assert_kind_of Typelib::MetaData, Typelib::OpaqueType.metadata
        assert_kind_of Typelib::MetaData, Typelib::PointerType.metadata
        assert_kind_of Typelib::MetaData, Typelib::NumericType.metadata
        assert_kind_of Typelib::MetaData, Typelib::ArrayType.metadata
        assert_kind_of Typelib::MetaData, Typelib::CompoundType.metadata
        assert_kind_of Typelib::MetaData, Typelib::EnumType.metadata
        assert_kind_of Typelib::MetaData, Typelib::ContainerType.metadata
        assert_kind_of Typelib::MetaData, Typelib::CompoundType.metadata
    end

    # Not in setup() since we want to make sure
    # that the registry is not destroyed by the GC
    def make_registry
        registry = Registry.new
        testfile = File.join(SRCDIR, "test_cimport.1")
        assert_raises(RuntimeError) { registry.import(testfile) }
        registry.import(testfile, "c")

        registry
    end

    def test_compound_type_definition
        t = compound_t
        assert(t < Typelib::CompoundType)

        fields = [["plain", registry.get("/int8_t")],
                  ["compound", registry.get("/compounds/Subfield")],
                  ["plain_vector", registry.get("/std/vector</int8_t>")],
                  ["vector", registry.get("/std/vector</compounds/Subfield>")]]
        assert_equal fields, t.fields

        assert_same(fields[0][1], t["plain"])
        assert_same(fields[1][1], t["compound"])
        assert_same(fields[2][1], t["plain_vector"])
        assert_same(fields[3][1], t["vector"])
    end

    def test_CompoundType_get_fields # rubocop:disable Naming/MethodName
        Typelib::CompoundType.get_fields
    end

    def test_compound_inititialize_with_hash
        expected_value = { plain: 10,
                           compound: { plain: 10, vector: [1, 2, 3, 5] },
                           plain_vector: [4, 5, 8, 10],
                           vector: [
                               { plain: 1, vector: [1, 2, 3, 5] },
                               { plain: 5, vector: [2, 3, 4, 6] }
                           ] }
        compound = compound_t.new(expected_value)
        assert_kind_of compound_t, compound
        assert_typelib_value_equals expected_value, compound
    end

    def assert_typelib_value_equals(expected, value)
        case value
        when ContainerType, ArrayType
            assert(value.size >= expected.size)
            value.each_with_index do |v, i|
                assert_typelib_value_equals(expected[i], v)
            end
        when CompoundType
            expected.each do |field_name, field_value|
                assert_typelib_value_equals(field_value, value[field_name])
            end
        else
            assert_equal expected, value
        end
    end

    def test_compound_raw_get
        registry = CXXRegistry.new
        registry.create_container "/std/vector", "/double"
        type = registry.create_compound "/Test" do |c|
            c.field = "/std/vector</double>"
        end

        value = type.new
        value.field.push(0)
        raw_value = value.field.raw_get(0)
        assert_kind_of Typelib::NumericType, raw_value
        assert_equal 0, Typelib.to_ruby(raw_value)
    end

    def test_compound_field_raw_set_does_no_typelib_convertion
        subfield_t = compound_t[:compound]

        value = compound_t.new
        expected_value = { plain: 10, vector: [1, 2, 3, 5] }
        subfield = Typelib.from_ruby(expected_value, subfield_t)

        flexmock(Typelib).should_receive(:from_ruby).with(subfield, subfield_t)
                         .and_return { |*args| args.first }.never

        value.raw_set("compound", subfield)
        assert_typelib_value_equals expected_value, value.compound
    end

    def test_compound_field_set_does_typelib_convertion
        subfield_t = compound_t[:compound]

        value = compound_t.new
        expected_value = { plain: 10, vector: [1, 2, 3, 5] }
        subfield = Typelib.from_ruby(expected_value, subfield_t)

        flexmock(Typelib).should_receive(:from_ruby).with(any, subfield_t)
                         .and_return { |*args| args.first }.once

        value.set_field("compound", subfield)
        assert_typelib_value_equals expected_value, value.compound
    end

    def test_compound_convertion_from_hash
        expected_value = { plain: 10,
                           compound: { plain: 10, vector: [1, 2, 3, 5] },
                           plain_vector: [4, 5, 8, 10],
                           vector: [
                               { plain: 1, vector: [1, 2, 3, 5] },
                               { plain: 5, vector: [2, 3, 4, 6] }
                           ] }
        compound = Typelib.from_ruby(expected_value, compound_t)
        assert_kind_of compound_t, compound
        assert_typelib_value_equals expected_value, compound
    end

    def test_compound_defines_access_methods
        value = compound_t.new
        assert_respond_to value, :plain
        assert_respond_to value, :plain=
        assert_respond_to value, :plain_vector
        assert_respond_to value, :plain_vector=
        assert_respond_to value, :vector
        assert_respond_to value, :vector=
        assert_respond_to value, :compound
        assert_respond_to value, :compound=
        assert_respond_to value, :raw_plain
        assert_respond_to value, :raw_plain=
        assert_respond_to value, :raw_plain_vector
        assert_respond_to value, :raw_plain_vector=
        assert_respond_to value, :raw_vector
        assert_respond_to value, :raw_vector=
        assert_respond_to value, :raw_compound
        assert_respond_to value, :raw_compound=
    end

    def test_compound_access_methods_call_base_setters_and_getters
        value = compound_t.new

        flexmock(value).should_receive(:set)
                       .with("plain", 10).once.ordered.and_return
        flexmock(value).should_receive(:raw_set)
                       .with("plain", 10).once.ordered.and_return
        flexmock(value).should_receive(:get)
                       .with("plain").once.ordered.and_return(20)
        flexmock(value).should_receive(:raw_get)
                       .with("plain").once.ordered.and_return(20)

        value.plain = 10
        value.raw_plain = 10
        assert_equal 20, value.plain
        assert_equal 20, value.raw_plain
    end

    def test_compound_field_access_caches_typelib_wrapper
        value = compound_t.new
        assert_same value.vector, value.vector
    end

    def test_compound_field_assignment_without_convertion_does_a_typelib_copy
        element_t = compound_t[:vector]
        field = element_t.new
        value = compound_t.new

        flexmock(Typelib).should_receive(:copy).with(value.vector, element_t).once
        value.vector = field # rubocop:disable Lint/UselessSetterCall
    end

    def test_compound_method_overloading
        t = registry.create_compound "/CompoundWithOverloadingClashes" do |compound_t|
            # should not be overloaded on the class, but OK on the instance
            compound_t.name = "/int32_t"
            # should not be overloaded on the instance, but OK on the class
            compound_t.cast = "/int32_t"
            # should be overloaded in both cases
            compound_t.object_id = "/int32_t"
        end

        v = t.new
        v.zero!
        assert_equal 0, v.name
        assert_equal v, v.cast(t)
        assert_equal 0, v.object_id
    end

    def test_compound_invalidate_no_field_accessed
        value = root_t.new.compound
        value.invalidate # Nothing should happen
    end

    def test_compound_invalidate
        value = root_t.new.compound
        flexmock(value.vector).should_receive(:invalidate).once
        flexmock(value.compound).should_receive(:invalidate).once
        value.invalidate
    end

    def test_array_definition
        array_t = registry.create_array compound_t, 10
        array = array_t.new

        assert_equal 10, array_t.length
        assert_same compound_t, array_t.deference
        assert_equal 10, array.size
        assert_same compound_t, array.element_t
    end

    def test_array_plain_set_get
        array_t = registry.create_array "/float", 10
        array = array_t.new

        (0..(array.size - 1)).each do |i|
            array[i] = Float(i) / 10.0
        end
        (0..(array.size - 1)).each do |i|
            assert_in_delta(Float(i) / 10.0, array[i], 0.01)
        end
    end

    def test_array_plain_initialize_from_ruby_array
        array_t = registry.create_array "/int32_t", 10
        # Array too small
        assert_raises(ArgumentError) do
            array_t.new([0, 1, 2, 3, 4, 5])
        end
        array = array_t.new((0..9).to_a)
        array.enum_for(:raw_each).each_with_index do |val, i|
            assert_equal i, val
        end
    end

    def test_array_plain_raw_each
        array_t = registry.create_array "/int32_t", 10
        array = array_t.new
        10.times do |i|
            array[i] = i
        end
        array.enum_for(:raw_each).each_with_index do |val, i|
            assert_kind_of Typelib::Type, val
            assert_equal i, Typelib.to_ruby(val)
        end
    end

    def test_array_complex_set_get
        array_t = registry.create_array compound_t, 10
        array = array_t.new

        expected_value = { plain: 10,
                           compound: { plain: 10, vector: [1, 2, 3, 5] },
                           plain_vector: [4, 5, 8, 10],
                           vector: [
                               { plain: 1, vector: [1, 2, 3, 5] },
                               { plain: 5, vector: [2, 3, 4, 6] }
                           ] }
        compound = Typelib.from_ruby(expected_value, compound_t)

        (0..(array.size - 1)).each do |i|
            compound.plain = i
            array[i] = compound
        end
        (0..(array.size - 1)).each do |i|
            expected_value[:plain] = i
            assert_typelib_value_equals expected_value, array[i]
        end
    end

    def test_array_complex_set_get_caches_return_value
        array_t = registry.create_array compound_t, 10
        array = array_t.new
        assert_same array[3], array[3]
    end

    def test_array_complex_raw_set_uses_typelib_copy
        array_t = registry.create_array compound_t, 10
        array = array_t.new

        compound = compound_t.new
        flexmock(Typelib).should_receive(:copy).with(array[3], compound).once
        array[3] = compound # rubocop:disable Lint/UselessSetterCall
    end

    def test_array_complex_set_calls_raw_set
        array_t = registry.create_array compound_t, 10
        array = array_t.new

        compound = compound_t.new
        flexmock(array).should_receive(:raw_set).with(3, compound).once
        array[3] = compound # rubocop:disable Lint/UselessSetterCall
    end

    def test_array_complex_set_does_type_convertion
        array_t = registry.create_array compound_t, 10
        array = array_t.new

        compound = compound_t.new
        flexmock(Typelib).should_receive(:from_ruby).with(compound, compound_t).once
                         .and_return { |val, type| val }
        array[3] = compound # rubocop:disable Lint/UselessSetterCall
    end

    def test_enum
        registry = Typelib::Registry.new
        registry.create_enum "/E" do |enum|
            enum.add "E_FIRST", 0
            enum.add "E_SECOND", 1
        end
        e_container = registry.create_compound "/EContainer" do |c|
            c.add "value", "/E"
        end

        e = e_container.new
        assert(e.respond_to?(:value))
        assert(e.respond_to?(:value=))
        e.value = 0
        assert_equal(:E_FIRST, e.value)
        e.value = "E_FIRST"
        assert_equal(:E_FIRST, e.value)
        e.value = :E_SECOND
        assert_equal(:E_SECOND, e.value)
    end

    def test_enum_can_cast_to_superset
        registry = Typelib::Registry.new
        e_type = registry.create_enum "/E" do |enum|
            enum.add "E_FIRST", 0
            enum.add "E_SECOND", 1
        end
        e_modified = registry.create_enum "/E_modified" do |enum|
            enum.add "E_FIRST", 0
            enum.add "E_SECOND", 1
            enum.add "E_THIRD", 2
        end
        refute_equal e_type, e_modified
        assert e_type.casts_to?(e_modified)
    end

    def test_enum_cannot_cast_to_subset
        registry = Typelib::Registry.new
        e_type = registry.create_enum "/E" do |enum|
            enum.add "E_FIRST", 0
            enum.add "E_SECOND", 1
        end
        e_modified = registry.create_enum "/E_modified" do |enum|
            enum.add "E_FIRST", 0
            enum.add "E_SECOND", 2
        end
        refute_equal e_type, e_modified
        refute e_type.casts_to?(e_modified)
    end

    def test_enum_cannot_cast_to_modified
        registry = make_registry
        e_type = registry.get("E")
        e_modified = registry.get("E_comparison_2/E_with_modified_values")
        assert(!(e_type == e_modified))
        assert(!e_modified.casts_to?(e_type))
    end

    def test_enum_to_ruby
        registry = make_registry
        e_type = registry.get("EContainer")
        e = e_type.new
        e.value = 0
        enum = e.raw_get("value")
        assert_kind_of Typelib::EnumType, enum
        sym = Typelib.to_ruby(enum)
        assert_kind_of Symbol, sym
        assert_equal :E_FIRST, sym
    end

    def test_enum_from_ruby
        registry = make_registry
        e_type = registry.get("EContainer")["value"]
        enum = Typelib.from_ruby(:E_FIRST, e_type)
        assert_kind_of Typelib::EnumType, enum
        assert_equal :E_FIRST, Typelib.to_ruby(enum)
    end

    def test_numeric
        registry = Typelib::Registry.new
        registry.create_numeric "/int32_t", 4, :sint
        registry.create_numeric "/uint32_t", 4, :uint
        registry.create_numeric "/double", 8, :float

        long = registry.get("/int32_t")
        assert(long < NumericType)
        assert(long.integer?)
        assert(!long.unsigned?)
        assert_equal(4, long.size)

        long_v = long.from_ruby(10)
        assert_equal 10, long_v.to_ruby

        ulong = registry.get("/uint32_t")
        assert(ulong < NumericType)
        assert_equal(4, ulong.size)
        assert(ulong.integer?)
        assert(ulong.unsigned?)

        double = registry.get("/double")
        assert(double < NumericType)
        assert_equal(8, double.size)
        assert(!double.integer?)
        assert_raises(ArgumentError) { double.unsigned? }
    end

    def test_numeric_to_ruby
        registry = Typelib::Registry.new
        registry.create_numeric "/int32_t", 4, :sint
        long = registry.get("/int32_t")
        v = long.new
        v.zero!
        zero = Typelib.to_ruby(v)
        assert_kind_of Numeric, zero
        assert_equal 0, zero
    end

    def test_numeric_from_ruby
        registry = Typelib::Registry.new
        registry.create_numeric "/int32_t", 4, :sint
        long = registry.get("/int32_t")
        zero = Typelib.from_ruby(0, long)
        assert_kind_of Typelib::NumericType, zero
        assert_equal 0, Typelib.to_ruby(zero)
    end

    def test_numeric_from_ruby_raises_UnknownConversionRequested_when_converting_a_non_numeric # rubocop:disable Naming/MethodName
        registry = Typelib::Registry.new
        registry.create_numeric "/int32_t", 4, :sint
        long = registry.get("/int32_t")
        assert_raises(UnknownConversionRequested) { long.from_ruby("10") }
    end

    def test_string_handling
        registry = Typelib::CXXRegistry.new
        char_pointer = registry.build("char*").new
        assert(char_pointer.string_handler?)
        assert(char_pointer.respond_to?(:to_str))
    end

    def test_null
        registry = Typelib::Registry.new
        registry.create_null "/void"
        null = registry.get("/void")
        assert(null.null?)
    end

    def test_null_type_equality
        registry = Typelib::Registry.new
        void_t = registry.create_null("/void")
        nil_t  = registry.create_null("/nil")
        other_registry = Typelib::Registry.new
        other_void_t = other_registry.create_null("/void")

        assert_equal void_t, other_void_t
        refute_equal void_t, nil_t
        refute_equal other_void_t, nil_t
    end

    def test_containers
        std = make_registry.get("StdCollections")
        assert(std[:dbl_vector] < Typelib::ContainerType)
        assert_equal("/std/vector", std[:dbl_vector].container_kind)

        value = std.new
        assert_equal(0, value.dbl_vector.length)
        assert(value.dbl_vector.empty?)

        value.dbl_vector.push(10)
        assert_equal(1, value.dbl_vector.length)
        assert_equal([10], value.dbl_vector.to_a)

        expected = [10]
        10.times do |i|
            value.dbl_vector.push(i)
            assert_equal(i + 2, value.dbl_vector.length)
            expected << i
            assert_equal(expected, value.dbl_vector.to_a)
        end

        expected.delete_if { |v| v < 5 }
        value.dbl_vector.delete_if { |v| v < 5 }
        assert_equal(expected, value.dbl_vector.to_a)

        expected.delete_at(2)
        value.dbl_vector.erase(6)
        assert_equal(expected, value.dbl_vector.to_a)
    end

    def test_container_random_access
        std = make_registry.get("StdCollections")
        value = std.new
        value.dbl_vector.push(20)
        assert_equal 20, value.dbl_vector[0]
        value.dbl_vector[0] = 10
        assert_equal 10, value.dbl_vector[0]
    end

    def test_container_of_container
        std = make_registry.get("StdCollections")
        assert(std[:v_of_v] < Typelib::ContainerType)
        assert(std[:v_of_v].deference < Typelib::ContainerType)

        inner_t = std[:v_of_v].deference

        value = std.new
        outer = value.v_of_v
        assert_equal(0, outer.length)

        new_element = inner_t.new
        new_element.push(10)
        outer.push(new_element)
        new_element.push(20)
        outer.push(new_element)

        assert_equal(2, outer.length)
        elements = outer.to_a
        assert_kind_of(Typelib::ContainerType, elements[0])
        assert_equal([10], elements[0].to_a)
        assert_kind_of(Typelib::ContainerType, elements[1])
        assert_equal([10, 20], elements[1].to_a)
    end

    def test_container_clear
        value = make_registry.get("StdCollections").new

        value.dbl_vector.push(10)
        assert(!value.dbl_vector.empty?)
        value.dbl_vector.clear
        assert(value.dbl_vector.empty?)
    end

    def test_container_raw_each
        type = CXXRegistry.new.create_container "/std/vector", "/double"
        value = type.new
        10.times do |i|
            value.push(i)
        end
        value.enum_for(:raw_each).each_with_index do |val, i|
            assert_kind_of Typelib::Type, val
            assert_equal i, Typelib.to_ruby(val)
        end
    end

    def test_container_raw_get
        type = CXXRegistry.new.create_container "/std/vector", "/double"
        value = type.new
        value.push(0)
        raw_value = value.raw_get(0)
        assert_kind_of Typelib::NumericType, raw_value
        assert_equal 0, Typelib.to_ruby(raw_value)
    end

    def test_container_size
        type = CXXRegistry.new.create_container "/std/vector", "/double"
        value = type.new
        assert_equal 0, value.size

        value.push(0)
        assert_equal 1, value.size
    end

    def test_create_container
        reg = Typelib::Registry.new
        int32_t = reg.create_numeric "/int32_t", 4, :sint
        assert_raises(ArgumentError) { reg.create_container("/blabla") }
        cont = reg.create_container "/std/vector", int32_t

        assert(cont < Typelib::ContainerType)
        assert_equal("/std/vector", cont.container_kind)
        assert_equal(int32_t, cont.deference)
        assert_equal("/std/vector</int32_t>", cont.name)
    end

    def test_std_string
        reg   = Typelib::CXXRegistry.new
        type  = reg.get("/std/string")
        value = type.new

        assert value.empty?
        assert_equal 0, value.length

        value.push("a")
        value.push("b")
        assert_equal "ab", Typelib.to_ruby(value)
        assert_equal "a_string", Typelib.to_ruby(Typelib.from_ruby("a_string", reg.get("/std/string")))
    end

    def test_std_string_push
        reg = Typelib::CXXRegistry.new
        string_t = reg.get("/std/string")

        str = Typelib.from_ruby("string", string_t)
        str << "1"
        assert_equal "string1", Typelib.to_ruby(str)

        assert_raises(ArgumentError) { str << "longer" }
        assert_raises(ArgumentError) { str << "" }
    end

    def test_std_string_concat
        reg = Typelib::CXXRegistry.new
        string_t = reg.get("/std/string")

        str = Typelib.from_ruby("string1", string_t)
        str.concat("string2")
        assert_equal "string1string2", Typelib.to_ruby(str)
    end

    def test_boolean
        reg = Typelib::CXXRegistry.new

        type = reg.get "bool"

        v = Typelib.from_ruby(true, type)
        assert_kind_of type, v
        assert_equal true, Typelib.to_ruby(v, type)

        v = Typelib.from_ruby(false, type)
        assert_kind_of type, v
        assert_equal false, Typelib.to_ruby(v, type)
    end

    def test_boolean_in_struct
        reg = Typelib::CXXRegistry.new
        reg.create_compound "/BoolHandling" do |c|
            c.add "value", "/bool"
        end

        type = reg.get "BoolHandling"
        value = type.new

        value.value = true
        assert_equal true, value.value

        value.value = false
        assert_equal false, value.value
    end

    def test_vector_complex_get_returns_same_wrapper
        vector_t = registry.create_container "/std/vector", compound_t
        vector = vector_t.new
        5.times do
            vector << compound_t.new
        end

        assert_same vector[3], vector[3]
    end

    def test_vector_freeze
        registry = Typelib::CXXRegistry.new
        vector_t = registry.create_container "/std/vector", "/double"
        vector = vector_t.new

        10.times do |i|
            vector.push(i)
        end
        vector.freeze
        assert(vector.frozen?)
        assert_raises(TypeError) { vector.push(10) }
        assert_raises(TypeError) { vector.erase(10) }
        assert_raises(TypeError) { vector.delete_if {} }
        assert_raises(TypeError) { vector[0] = 10 }
        assert_equal(5, vector[5])
    end

    def test_vector_invalidate_refuses_toplevel_values
        registry = Typelib::CXXRegistry.new
        vector_t = registry.create_container "/std/vector", "/double"
        vector = vector_t.new
        assert_raises(ArgumentError) { vector.invalidate }
    end

    def test_vector_invalidate
        main_t = make_registry.get("StdCollections")
        main = main_t.new
        vector = main.dbl_vector

        10.times do |i|
            vector.push(i)
        end
        vector.invalidate
        assert(vector.invalidated?)
        assert_raises(TypeError) { vector.push(10) }
        assert_raises(TypeError) { vector.erase(10) }
        assert_raises(TypeError) { vector.delete_if {} }
        assert_raises(TypeError) { vector[0] }
        assert_raises(TypeError) { vector[0] = 10 }
    end

    def test_vector_erase_invalidates_last_elements
        std = make_registry.get("StdCollections")
        value_t = std[:v_of_v]

        value   = value_t.new
        element = value_t.deference.new
        10.times { value.push(element) }

        last = value[9]
        value.erase(element)
        assert last.invalidated?
    end

    def test_vector_delete_if_invalidates_last_elements
        std = make_registry.get("StdCollections")
        value_t = std[:v_of_v]

        value   = value_t.new
        element = value_t.deference.new
        10.times { value.push(element) }

        last = value[9]
        bool = false
        value.delete_if do |el|
            if bool = !bool
                true
            else break
            end
        end
        assert last.invalidated?
    end

    def test_compound_type_with_enum_fields_can_be_pretty_printed
        reg = Typelib::CXXRegistry.new
        reg.create_enum "/E" do |e|
            e.add "VAL", 1
        end
        compound_t = reg.create_compound "/C" do |c|
            c.add "e", "/E"
        end
        PP.pp(compound_t, "")
    end

    def test_compound_type_invalidated_raises_TypeError_on_field_access # rubocop:disable Naming/MethodName
        reg = Typelib::CXXRegistry.new
        reg.create_compound("/C") { |c| c.add "field", "/double" }
        container = reg.create_container("/std/vector", "/C").new
        container << Hash[field: 0]
        v = container[0]
        v.invalidate
        assert_raises(TypeError) { v.field }
    end

    def test_container_type_invalidation_invalidates_children_if_modified
        reg = Typelib::CXXRegistry.new
        container = reg.create_container("/std/vector", "/double").new
        container << 0
        element = container.raw_get(0)
        container.handle_invalidation do
            flexmock(container).should_receive(:contained_memory_id).and_return(0)
        end
        assert !container.invalidated?
        assert element.invalidated?
    end

    def test_container_type_does_not_access_already_invalidated_accessors
        reg = Typelib::CXXRegistry.new
        reg.create_container("/std/vector", "/double")
        c_of_c = reg.create_container("/std/vector", "/std/vector</double>").new
        c_of_c << [0]
        c = c_of_c.raw_get(0)
        element = c.raw_get(0)
        c_of_c.handle_invalidation do
            flexmock(c_of_c).should_receive(:contained_memory_id).and_return(0)
            flexmock(c).should_receive(:contained_memory_id).never
        end
        assert !c_of_c.invalidated?
        assert c.invalidated?
        assert element.invalidated?
    end

    def test_std_string_to_simple_value_returns_the_string
        reg = Typelib::CXXRegistry.new
        value = Typelib.from_ruby("test string", reg.get("/std/string"))
        # We have to check for the type explicitely
        assert_kind_of String, value.to_simple_value
        assert_equal "test string", value.to_simple_value
    end
end
