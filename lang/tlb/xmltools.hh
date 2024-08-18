#ifndef TYPELIB_LANG_TLB_XMLTOOLS_HH
#define TYPELIB_LANG_TLB_XMLTOOLS_HH

#include <libxml/xmlmemory.h>
#include "parsing.hh"
#include <boost/lexical_cast.hpp>

namespace
{
    using std::string;

    template<typename Exception>
    void checkNodeName(xmlNodePtr node, const char* expected)
    {
        if (xmlStrcmp(node->name, reinterpret_cast<const xmlChar*>(expected)))
            throw Exception(reinterpret_cast<const char*>(node->name), expected, "");
    }

    std::pair<bool, std::string> getStringAttribute(xmlNodePtr type, const char* att_name)
    {
        xmlChar* att = xmlGetProp(type, reinterpret_cast<const xmlChar*>(att_name) );
        if (! att) {
            return std::make_pair(false, "");
        }
        std::string ret( reinterpret_cast<const char*>(att));
        xmlFree(att);
        return make_pair(true, ret);
    }

    template<typename T>
    T getAttribute(xmlNodePtr type, char const* att_name, T const& default_value)
    {
        auto optional = getStringAttribute(type, att_name);
        if (optional.first) {
            return boost::lexical_cast<T>(optional.second);
        }

        return default_value;
    }
    template<>
    std::string getAttribute<std::string>(xmlNodePtr type, const char* att_name, std::string const& default_value)
    {
        auto optional = getStringAttribute(type, att_name);
        if (optional.first) {
            return optional.second;
        }

        return default_value;
    }

    template<typename T>
    T getAttribute(xmlNodePtr type, char const* att_name)
    {
        auto optional = getStringAttribute(type, att_name);
        if (optional.first) {
            return boost::lexical_cast<T>(optional.second);
        }

        throw Parsing::MissingAttribute(att_name, "");
    }
    template<>
    std::string getAttribute<std::string>(xmlNodePtr type, const char* att_name)
    {
        auto optional = getStringAttribute(type, att_name);
        if (optional.first) {
            return optional.second;
        }

        throw Parsing::MissingAttribute(att_name, "");
    }
}

#endif

