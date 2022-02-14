#include "standard_types.hh"
#include "containers.hh"
#include "typelib/typename.hh"
#include <iostream>

using namespace Typelib;
using std::to_string;

static void addStandardTypes(Typelib::Registry& r)
{
    BOOST_STATIC_ASSERT((Typelib::NamespaceMark == '/'));

    r.add(new NullType("/nil"));
    r.alias("/nil", "/void");

    // Add standard sized integers
    static const int sizes[] = { 1, 2, 4, 8 };
    for (size_t i = 0; i < sizeof(sizes)/sizeof(sizes[0]); ++i)
    {
        std::string suffix = "int" + to_string(sizes[i] * 8) + "_t";
        r.add(new Numeric("/"  + suffix, sizes[i], Numeric::SInt));
        r.add(new Numeric("/u" + suffix, sizes[i], Numeric::UInt));
    }

    std::string normalized_type_name = "/int8_t";
    r.alias("/int8_t", "/signed char");
    r.alias("/uint8_t", "/unsigned char");

    r.add(new Character("/char8_t", 1));
    r.alias("/char8_t", "/char");

    normalized_type_name = "/int" + to_string(std::numeric_limits<short int>::digits + 1) + "_t";
    r.alias(normalized_type_name, "/signed short int");
    r.alias(normalized_type_name, "/signed int short");
    r.alias(normalized_type_name, "/int signed short");
    r.alias(normalized_type_name, "/short signed int");
    r.alias(normalized_type_name, "/signed short int");
    r.alias(normalized_type_name, "/signed short");
    r.alias(normalized_type_name, "/short signed");
    r.alias(normalized_type_name, "/short");
    r.alias(normalized_type_name, "/short int");
    normalized_type_name = "/uint" + to_string(std::numeric_limits<short int>::digits + 1) + "_t";
    r.alias(normalized_type_name, "/short unsigned int");
    r.alias(normalized_type_name, "/short int unsigned");
    r.alias(normalized_type_name, "/int short unsigned");
    r.alias(normalized_type_name, "/unsigned short int");
    r.alias(normalized_type_name, "/short unsigned");
    r.alias(normalized_type_name, "/unsigned short");

    normalized_type_name = "/int" + to_string(std::numeric_limits<int>::digits + 1) + "_t";
    r.alias(normalized_type_name, "/signed int");
    r.alias(normalized_type_name, "/signed");
    r.alias(normalized_type_name, "/int signed");
    r.alias(normalized_type_name, "/int");
    normalized_type_name = "/uint" + to_string(std::numeric_limits<int>::digits + 1) + "_t";
    r.alias(normalized_type_name, "/unsigned int");
    r.alias(normalized_type_name, "/unsigned");
    r.alias(normalized_type_name, "/int unsigned");

    normalized_type_name = "/int" + to_string(std::numeric_limits<long>::digits + 1) + "_t";
    r.alias(normalized_type_name, "/signed long int");
    r.alias(normalized_type_name, "/signed int long");
    r.alias(normalized_type_name, "/int signed long");
    r.alias(normalized_type_name, "/long signed int");
    r.alias(normalized_type_name, "/signed long int");
    r.alias(normalized_type_name, "/signed long");
    r.alias(normalized_type_name, "/long signed");
    r.alias(normalized_type_name, "/long");
    r.alias(normalized_type_name, "/long int");
    normalized_type_name = "/uint" + to_string(std::numeric_limits<long>::digits + 1) + "_t";
    r.alias(normalized_type_name, "/long unsigned int");
    r.alias(normalized_type_name, "/long int unsigned");
    r.alias(normalized_type_name, "/int long unsigned");
    r.alias(normalized_type_name, "/unsigned long int");
    r.alias(normalized_type_name, "/long unsigned");
    r.alias(normalized_type_name, "/unsigned long");

    normalized_type_name = "/int" + to_string(std::numeric_limits<long long>::digits + 1) + "_t";
    r.alias(normalized_type_name, "/signed long long int");
    r.alias(normalized_type_name, "/signed long int long");
    r.alias(normalized_type_name, "/signed int long long");
    r.alias(normalized_type_name, "/int signed long long");
    r.alias(normalized_type_name, "/long signed long int");
    r.alias(normalized_type_name, "/long long signed int");
    r.alias(normalized_type_name, "/long long int signed");
    r.alias(normalized_type_name, "/signed long long");
    r.alias(normalized_type_name, "/long long signed");
    r.alias(normalized_type_name, "/long signed long");
    r.alias(normalized_type_name, "/long long int");
    r.alias(normalized_type_name, "/long int long");
    r.alias(normalized_type_name, "/int long long");
    r.alias(normalized_type_name, "/long long");
    normalized_type_name = "/uint" + to_string(std::numeric_limits<long long>::digits + 1) + "_t";
    r.alias(normalized_type_name, "/unsigned long long int");
    r.alias(normalized_type_name, "/unsigned long int long");
    r.alias(normalized_type_name, "/unsigned int long long");
    r.alias(normalized_type_name, "/int unsigned long long");
    r.alias(normalized_type_name, "/long unsigned long int");
    r.alias(normalized_type_name, "/long long unsigned int");
    r.alias(normalized_type_name, "/long long int unsigned");
    r.alias(normalized_type_name, "/unsigned long long");
    r.alias(normalized_type_name, "/long long unsigned");
    r.alias(normalized_type_name, "/long unsigned long");

    BOOST_STATIC_ASSERT(( sizeof(float) == sizeof(int32_t) ));
    BOOST_STATIC_ASSERT(( sizeof(double) == sizeof(int64_t) ));
    r.add(new Numeric("/float",  4, Numeric::Float));
    r.add(new Numeric("/double", 8, Numeric::Float));

    // Finally, add definition for boolean types
    r.add(new Numeric("/bool", sizeof(bool), Numeric::UInt));
}


void Typelib::CXX::addStandardTypes(Typelib::Registry& registry)
{
    if (!registry.has("/bool"))
        ::addStandardTypes(registry);
    if (!registry.has("/std/string"))
        registry.add(new String(*registry.get("/char8_t")));
}

