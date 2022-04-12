# Common tests for all C++ importers
#
# The module is meant to be included in a test class, which must set the @loader
# instance variable with a {Typelib::CXX}-compatible loader object, and may
# update the importer_options hash with default options that must be passed to
# the loader
module CXXCommonTests
    attr_reader :loader, :loader_name, :importer_options

    def setup
        super
        @importer_options ||= {}
    end

    def setup_loader(loader_name, name: loader_name, **options)
        if test_selected_loader = ENV["TYPELIB_CXX_LOADER"]
            if test_selected_loader != loader_name
                skip "test environment selected #{test_selected_loader} as loader, skipping #{loader_name}"
            end
        end

        if loader = Typelib::CXX::CXX_LOADERS[loader_name]
            @loader = loader
            @loader_name = name
            importer_options.merge!(options)
        else
            raise ArgumentError, "unknown loader #{loader_name}"
        end
    end

    def assert_equivalent_types(expected_type, actual_type, error_message)
        if expected_type != actual_type
            pp = PP.new(error_message)
            name.pretty_print(pp)
            pp.breakable
            pp.text "Expected: "
            pp.breakable
            pp.text expected_type.to_xml
            pp.breakable
            pp.text "Actual: "
            pp.breakable
            pp.text actual_type.to_xml
            flunk(error_message)
        end

        expected_type.metadata.each do |key, expected_metadata|
            unless actual_type.metadata.include?(key)
                flunk("#{actual_type.name} was expected to have a metadata value for #{key} equal to #{expected_metadata}, but does not have any")
            end
            if key == "source_file_line" # resolve paths relatively to the test dir
                expected_metadata = expected_metadata.map do |path|
                    File.expand_path(path, cxx_test_dir)
                end
            end
            actual_metadata = actual_type.metadata.get(key).to_set
            if actual_metadata != expected_metadata.to_set
                flunk("#{actual_type.name} was expected to have a metadata value for #{key} equal to #{expected_metadata}, but it is equal to #{actual_metadata.to_a}")
            end
        end
    end

    # The bulk of the C++ tests are made of a C++ file and an expected tlb file.
    # This method generate one test method per such file
    #
    # @param [String] dir the directory containing the tests
    def self.generate_common_tests(dir)
        singleton_class.class_eval do
            define_method(:cxx_test_dir) { dir }
        end

        Dir.glob(File.join(dir, "*.hh")) do |file|
            basename = File.basename(file, ".hh")
            prefix   = File.join(dir, basename)
            opaques  = "#{prefix}.opaques"
            tlb      = "#{prefix}.tlb"
            next unless File.file?(tlb)
            next unless File.file?(tlb)

            define_method "test_cxx_common_#{basename}" do
                reg = Typelib::Registry.new
                reg.import(opaques, "tlb") if File.file?(opaques)
                loader.load(reg, file, "c", importer_options)

                importer_specific_tlb = "#{tlb}.#{loader_name}"
                has_specific_tlb = File.file?(importer_specific_tlb)

                expected = Typelib::Registry.from_xml(File.read(tlb))
                assert_registry_match(expected, reg, require_equivalence: !has_specific_tlb)

                if has_specific_tlb
                    expected = Typelib::Registry.from_xml(File.read(importer_specific_tlb))
                    assert_registry_match(expected, reg, require_equivalence: true)
                end
            end
        end
    end

    def assert_registry_match(expected, actual, require_equivalence: true)
        names = Set.new
        expected.each(with_aliases: true) do |name, expected_type|
            names << name
            begin
                actual_type = actual.build(name)
            rescue Typelib::NotFound => e
                kind = if name == expected_type.name then "type"
                       else "alias"
                       end
                raise e, "#{kind} in expected registry not found in actual one, #{e.message}: known types are #{actual.each.map(&:name).sort.join(", ")}"
            end

            assert_equivalent_types expected_type, actual_type,
                                    "failed expected and actual definitions type for #{name} differ\n"
        end

        if require_equivalence
            actual_names = actual.each(with_aliases: true).map { |n, _| n }.to_set
            remaining = actual_names - names
            unless remaining.empty?
                flunk("#{remaining.size} types defined that were not in the expected registry: #{remaining.to_a.sort.join(", ")}")
            end
        end
    end

    cxx_test_dir = File.expand_path("cxx_import_tests", File.dirname(__FILE__))
    generate_common_tests(cxx_test_dir)

    def cxx_test_dir
        CXXCommonTests.cxx_test_dir
    end

    def test_import_virtual_methods
        reg = Typelib::Registry.import File.join(cxx_test_dir, "virtual_methods.h"), "c", cxx_importer: loader
        assert !reg.include?("/Class")
    end

    def test_import_virtual_inheritance
        reg = Typelib::Registry.import File.join(cxx_test_dir, "virtual_inheritance.h"), "c", cxx_importer: loader
        assert reg.include?("/Base")
        assert !reg.include?("/Derived")
    end

    def test_import_private_base_class
        reg = Typelib::Registry.import File.join(cxx_test_dir, "private_base_class.h"), "c", cxx_importer: loader
        assert reg.include?("/Base")
        assert !reg.include?("/Derived")
    end

    def test_import_ignored_base_class
        reg = Typelib::Registry.import File.join(cxx_test_dir, "ignored_base_class.h"), "c", cxx_importer: loader
        assert !reg.include?("/Base")
        assert !reg.include?("/Derived")
    end

    def test_import_template_of_container
        reg = Typelib::Registry.import File.join(cxx_test_dir, "template_of_container.h"), "c", cxx_importer: loader
        assert reg.include?("/BaseTemplate</std/vector</double>>"), "cannot find /BaseTemplate</std/vector</double>>, vectors in registry: #{reg.map(&:name).grep(/vector/).sort.join(", ")}"
    end

    def test_import_documentation_parsing_handles_opening_bracket_and_struct_definition_on_different_lines
        reg = Typelib::Registry.import File.join(cxx_test_dir, "documentation_with_struct_and_opening_bracket_on_different_lines.h"), "c", cxx_importer: loader
        assert_equal ["this is a multiline\ndocumentation block"], reg.get("/DocumentedType").metadata.get("doc")
    end

    def test_import_documentation_parsing_handles_spaces_between_opening_bracket_and_struct_definition
        reg = Typelib::Registry.import File.join(cxx_test_dir, "documentation_with_space_between_struct_and_opening_bracket.h"), "c", cxx_importer: loader
        assert_equal ["this is a multiline\ndocumentation block"], reg.get("/DocumentedType").metadata.get("doc")
    end

    def test_import_documentation_parsing_handles_opening_bracket_and_struct_definition_on_the_same_line
        reg = Typelib::Registry.import File.join(cxx_test_dir, "documentation_with_struct_and_opening_bracket_on_the_same_line.h"), "c", cxx_importer: loader
        assert_equal ["this is a multiline\ndocumentation block"], reg.get("/DocumentedType").metadata.get("doc")
    end

    def test_import_documentation_extracts_metadata_tags
        reg = Typelib::Registry.import File.join(cxx_test_dir, "documentation_metadata_tags.h"), "c", cxx_importer: loader
        assert_equal ["struct_metadata"], reg.get("/DocumentedType").metadata.get("test")
        assert_equal ["field_metadata"], reg.get("/DocumentedType").field_metadata["field"].get("test")
    end

    def test_trailing_spaces_are_removed_from_metadata_tag_values
        reg = Typelib::Registry.import File.join(cxx_test_dir, "documentation_metadata_tags.h"), "c", cxx_importer: loader
        assert_equal ["without_trailing_space"], reg.get("/DocumentedType").metadata.get("strip")
    end

    def test_import_supports_utf8
        reg = Typelib::Registry.import File.join(cxx_test_dir, "documentation_utf8.h"), "c", cxx_importer: loader
        assert_equal ["this is a \u9999 multiline with \u1290 unicode characters"], reg.get("/DocumentedType").metadata.get("doc")
    end

    def test_resolves_opaques_to_their_true_name
        registry = Typelib::Registry.new
        registry.import(File.join(cxx_test_dir, "bug_opaque_import.hh"), "c", cxx_importer: loader, opaques: ["/OpaquePoint"])
    end
end
