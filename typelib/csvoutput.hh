#ifndef TYPELIB_DISPLAY_HH
#define TYPELIB_DISPLAY_HH
#include <string>
#include <iosfwd>

namespace Typelib
{
    class Type;

    class CSVOutput
    {
        Type const& m_type;
        std::string m_separator;

    public:
        CSVOutput(Type const& type, std::string const& sep);

        /** Displays the header */
        void header(std::ostream& out, std::string const& basename);
        void display(std::ostream& out, void* value);
    };


    namespace details {
        struct csvheader
        {
            CSVOutput output;
            std::string basename;

            csvheader(Type const& type, std::string const& basename_, std::string const& sep = " ")
                : output(type, sep), basename(basename_) {}
        };
        struct csvline
        {
            CSVOutput output;
            void* value;

            csvline(Type const& type_, void* value_, std::string const& sep_ = " ")
                : output(type_, sep_), value(value_) {}
        };
        inline std::ostream& operator << (std::ostream& stream, csvheader header)
        {
            header.output.header(stream, header.basename);
            return stream;
        }
        inline std::ostream& operator << (std::ostream& stream, csvline line)
        {
            line.output.display(stream, line.value);
            return stream;
        }
    }

    /** Display a CSV header matching a Type object
     * @arg type        the type to display
     * @arg basename    the basename to use. For simple type, it is the variable name. For compound types, names in the header are &lt;basename&gt;.&lt;fieldname&gt;
     * @arg sep         the separator to use
     */
    inline details::csvheader csv_header(Type const& type, std::string const& basename, std::string const& sep = " ")
    { return details::csvheader(type, basename, sep); }

    /** Display a CSV line for a Type object and some raw data
     * @arg type        the data type
     * @arg value       the data as a void* pointer
     * @arg sep         the separator to use
     */
    inline details::csvline   csv(Type const& type, void* value, std::string const& sep = " ")
    { return details::csvline(type, value, sep); }
};

#endif

