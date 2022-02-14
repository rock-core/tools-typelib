#include "value.hh"

#include "typevisitor.hh"

namespace Typelib
{
    class StrictValueVisitor::TypeDispatch : public StrictTypeVisitor
    {
        friend class StrictValueVisitor;

        // The dispatching stack
        std::list<uint8_t*> m_stack;

        // The ValueVisitor object
        StrictValueVisitor& m_visitor;

        template<typename T8, typename T16>
        bool char_cast(uint8_t* value, Type const& t)
        {
            switch(t.getSize())
            {
                case 1: return m_visitor.visit_(*reinterpret_cast<char*>(value));
                default:
                    throw UnsupportedType(t, "unsupported character size");
            };
        }

        template<typename T8, typename T16, typename T32, typename T64>
        bool integer_cast(uint8_t* value, Type const& t)
        {
            switch(t.getSize())
            {
                case 1: return m_visitor.visit_(*reinterpret_cast<T8*>(value));
                case 2: return m_visitor.visit_(*reinterpret_cast<T16*>(value));
                case 4: return m_visitor.visit_(*reinterpret_cast<T32*>(value));
                case 8: return m_visitor.visit_(*reinterpret_cast<T64*>(value));
                default:
                    throw UnsupportedType(t, "unsupported integer size");
            };
        }

    protected:
        virtual bool visit_ (NullType const& type)
        {
            Value v(m_stack.back(), type);
            return m_visitor.visit_(v, type);
        }

        virtual bool visit_ (Numeric const& type)
        {
            uint8_t* value(m_stack.back());
            switch(type.getNumericCategory())
            {
                case Numeric::SInt:
                    return integer_cast<int8_t, int16_t, int32_t, int64_t>(value, type);
                case Numeric::UInt:
                    return integer_cast<uint8_t, uint16_t, uint32_t, uint64_t>(value, type);
                case Numeric::Float:
                    switch(type.getSize())
                    {
                        case sizeof(float):  return m_visitor.visit_(*reinterpret_cast<float*>(value));
                        case sizeof(double): return m_visitor.visit_(*reinterpret_cast<double*>(value));
                    }
                default:
                    throw UnsupportedType(type, "unsupported numeric category");
            }
        }

        virtual bool visit_ (Character const& type)
        {
            uint8_t* value(m_stack.back());
            switch(type.getSize())
            {
                case 1: return m_visitor.visit_(*reinterpret_cast<char*>(value));
                default:
                    throw UnsupportedType(
                        type,
                        "unsupported character size " + std::to_string(type.getSize())
                    );
            };
        }

        virtual bool visit_ (Enum const& type)
        {
            Enum::integral_type& v = *reinterpret_cast<Enum::integral_type*>(m_stack.back());
            return m_visitor.visit_(v, type);
        }

        virtual bool visit_ (Container const& type)
        {
            Value v(m_stack.back(), type);
            return m_visitor.visit_(v, type);
        }

        virtual bool visit_ (Pointer const& type)
        {
            Value v(m_stack.back(), type);
            m_stack.push_back( *reinterpret_cast<uint8_t**>(m_stack.back()) );
            bool ret = m_visitor.visit_(v, type);
            m_stack.pop_back();
            return ret;
        }
        virtual bool visit_ (Array const& type)
        {
            Value v(m_stack.back(), type);
            return m_visitor.visit_(v, type);
        }

        virtual bool visit_ (Compound const& type)
        {
            Value v(m_stack.back(), type);
            return m_visitor.visit_(v, type);
        }

        virtual bool visit_ (OpaqueType const& type)
        {
            Value v(m_stack.back(), type);
            return m_visitor.visit_(v, type);
        }

        virtual bool visit_ (Compound const& type, Field const& field)
        {
            m_stack.push_back( m_stack.back() + field.getOffset() );
            bool ret = m_visitor.visit_(Value(m_stack.back(), field.getType()), type, field);
            m_stack.pop_back();
            return ret;
        }

    public:
        TypeDispatch(StrictValueVisitor& visitor)
            : m_visitor(visitor) { }

        void apply(Value value)
        {
            m_stack.clear();
            m_stack.push_back( reinterpret_cast<uint8_t*>(value.getData()));
            StrictTypeVisitor::apply(value.getType());
            m_stack.pop_back();
        }

    };

    bool StrictValueVisitor::visit_(Value const& v, Pointer const& t)
    {
        return m_dispatcher->StrictTypeVisitor::visit_(t);
    }
    bool StrictValueVisitor::visit_(Value const& v, Array const& a)
    {
        uint8_t*  base = static_cast<uint8_t*>(v.getData());
        m_dispatcher->m_stack.push_back(base);
        uint8_t*& element = m_dispatcher->m_stack.back();

        Type const& array_type(a.getIndirection());
        for (size_t i = 0; i < a.getDimension(); ++i)
        {
            element = base + array_type.getSize() * i;
            if (! m_dispatcher->StrictTypeVisitor::visit_(array_type))
                break;
        }

        m_dispatcher->m_stack.pop_back();
        return true;
    }
    bool StrictValueVisitor::visit_(Value const& v, Container const& c)
    {
        return c.visit(v.getData(), *this);
    }
    bool StrictValueVisitor::visit_(Value const&, Compound const& c)
    {
        return m_dispatcher->StrictTypeVisitor::visit_(c);
    }
    bool StrictValueVisitor::visit_(Value const&, Compound const& c, Field const& f)
    {
        return m_dispatcher->StrictTypeVisitor::visit_(c, f);
    }
    bool StrictValueVisitor::visit_(Enum::integral_type&, Enum const& e)
    {
        return true;
    }
    void StrictValueVisitor::dispatch(Value v)
    {
        m_dispatcher->m_stack.push_back(reinterpret_cast<uint8_t*>(v.getData()));
        m_dispatcher->StrictTypeVisitor::visit_(v.getType());
        m_dispatcher->m_stack.pop_back();
    }

}

namespace Typelib
{
    StrictValueVisitor::StrictValueVisitor()
       : m_dispatcher(new TypeDispatch(*this))
    {
    }
    StrictValueVisitor::~StrictValueVisitor()
    {
        delete m_dispatcher;
    }
    void StrictValueVisitor::apply(Value v)
    {
        m_dispatcher->apply(v);
    }
    ValueVisitor::ValueVisitor(bool defval)
       : m_defval(defval)
    {
    }

}

