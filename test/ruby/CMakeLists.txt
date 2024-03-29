CONFIGURE_FILE(test_config.rb.in ${CMAKE_CURRENT_BINARY_DIR}/test_config.rb @ONLY)
file(COPY runner.in cxx_tlbgen.in
    DESTINATION ${CMAKE_CURRENT_BINARY_DIR}
    FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE)
file(RENAME ${CMAKE_CURRENT_BINARY_DIR}/runner.in ${CMAKE_CURRENT_BINARY_DIR}/runner)
file(RENAME ${CMAKE_CURRENT_BINARY_DIR}/cxx_tlbgen.in ${CMAKE_CURRENT_BINARY_DIR}/cxx_tlbgen)

file(GLOB_RECURSE testfiles RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/*.rb)
foreach(test_file ${testfiles})
    set(test_requires "${test_requires}require '${test_file}';")
endforeach()
# running implicitly against the plugins installed in the install-location
ADD_TEST(NAME RubyInstalledPlugins
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMAND ${RUBY_EXECUTABLE} -w -I${CMAKE_CURRENT_SOURCE_DIR}/../../bindings/ruby/lib
        -I${CMAKE_CURRENT_SOURCE_DIR}
        -I${CMAKE_CURRENT_BINARY_DIR} -e "${test_requires}")

set(__test_parameters --)
if (ROCK_TEST_LOG_DIR)
    list(APPEND __test_parameters
        --junit
        --junit-filename=${ROCK_TEST_LOG_DIR}/ruby.xml
        --junit-jenkins)
    file(MAKE_DIRECTORY "${ROCK_TEST_LOG_DIR}")
endif()

# the second ruby-test running explicitly against the freshly compiled plugins
# in the build folder
ADD_TEST(NAME RubyLocalPlugins
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMAND ${RUBY_EXECUTABLE} -w -I${CMAKE_CURRENT_SOURCE_DIR}/../../bindings/ruby/lib
        -I${CMAKE_CURRENT_SOURCE_DIR}
        -I${CMAKE_CURRENT_BINARY_DIR} -e "${test_requires}"
        ${__test_parameters})
# the pluginmanager can load plugins from a list of paths set in the
# environment. for testing we don't want to use the plugins in the
# install-folder, but the freshly compiled ones in the build-folder. note that
# the folders set in the env-var are hardcoded...
set_property(TEST RubyLocalPlugins APPEND PROPERTY ENVIRONMENT
    "TYPELIB_PLUGIN_PATH=${CMAKE_BINARY_DIR}/lang/csupport:${CMAKE_BINARY_DIR}/lang/tlb:${CMAKE_BINARY_DIR}/lang/idl")
# there are no typelib-plugins inside _this_ single project which we might
# wanna test
set_property(TEST RubyLocalPlugins APPEND PROPERTY ENVIRONMENT
    "TYPELIB_RUBY_PLUGIN_PATH=")

add_test(
    NAME rubocop
    WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
    COMMAND rubocop
)
