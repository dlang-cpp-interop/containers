/**
 * D header file for interaction with C++ std::vector.
 *
 * Copyright: Copyright (c) 2018 D Language Foundation
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Guillaume Chatelet
 *            Manu Evans
 * Source:    $(DRUNTIMESRC core/stdcpp/vector.d)
 */

module core.experimental.stdcpp.vector;

///////////////////////////////////////////////////////////////////////////////
// std::vector declaration.
//
// Current caveats :
// - missing noexcept
// - nothrow @trusted @nogc for most functions depend on knowledge
//   of T's construction/destruction/assignment semantics
///////////////////////////////////////////////////////////////////////////////

import core.experimental.stdcpp.allocator;

enum DefaultConstruct { value }

/// Constructor argument for default construction
enum Default = DefaultConstruct();

extern(C++, "std"):

extern(C++, class) struct vector(T, Alloc = allocator!T)
{
    import core.lifetime;
    static assert(!is(T == bool), "vector!bool not supported!");
extern(D):

    ///
    alias size_type = size_t;
    ///
    alias difference_type = ptrdiff_t;
    ///
    alias value_type = T;
    ///
    alias allocator_type = Alloc;
    ///
    alias pointer = T*;
    ///
    alias const_pointer = const(T)*;

    ///
    alias as_array this;

    /// MSVC allocates on default initialisation in debug, which can't be modelled by D `struct`
    @disable this();

    ///
    alias length = size;
    ///
    alias opDollar = length;

    ///
    ref inout(T) front() inout nothrow @safe                                { return this[0]; }
    ///
    ref inout(T) back() inout nothrow @safe                                 { return this[$-1]; }


    // WIP...

//    this(size_type count);
//    this(size_type count, ref const(value_type) val);
//    this(size_type count, ref const(value_type) val, ref const(allocator_type) al);
//    this(ref const(vector) x);
//    this(iterator first, iterator last);
//    this(iterator first, iterator last, ref const(allocator_type) al = defaultAlloc);
//    this(const_iterator first, const_iterator last);
//    this(const_iterator first, const_iterator last, ref const(allocator_type) al = defaultAlloc);
//    this(T[] arr)                                                     { this(arr.ptr, arr.ptr + arr.length); }
//    this(T[] arr, ref const(allocator_type) al = defaultAlloc)        { this(arr.ptr, arr.ptr + arr.length); }
//    this(const(T)[] arr)                                              { this(arr.ptr, arr.ptr + arr.length); }
//    this(const(T)[] arr, ref const(allocator_type) al = defaultAlloc) { this(arr.ptr, arr.ptr + arr.length); }

//    ref vector opAssign(ref const(vector) s);
//
//    void clear() nothrow;
//    void resize(size_type n);
//    void resize(size_type n, T c);
//    void reserve(size_type n = 0) @trusted @nogc;
//    void shrink_to_fit();

//    ///
//    ref basic_string opOpAssign(string op : "~")(const(T)[] str)            { return append(str); }
    ///
    ref vector opOpAssign(string op : "~")(auto ref T item)           { push_back(forward!item); return this; }

    // Modifiers
    void push_back(U)(auto ref U element)
    {
        emplace_back(forward!element);
    }

    version (CppRuntime_Microsoft)
    {
        //----------------------------------------------------------------------------------
        // Microsoft runtime
        //----------------------------------------------------------------------------------

        ///
        this(DefaultConstruct)                                              { _Alloc_proxy(); }
        ///
        this(size_t count)                                                  { T def; this(count, def); }
        ///
        this(size_t count, ref T val)
        {
            _Alloc_proxy();
            _Buy(count);
            scope(failure) _Tidy();
            for (size_t i = 0; i < count; ++i)
                emplace(&_Get_data()._Myfirst[i], val);
            _Get_data()._Mylast = _Get_data()._Myfirst + count;
        }
//        ///
//        this(Range)(Range r)
////            if (isInputRange!Range && !isInfinite!Range && (hasLength!Range || isForwardRange!Range)) // wtf phobos?!
//        {
//            _Alloc_proxy();
//            static if (false) // hasLength...
//            {
//                // reserve and copy elements
//            }
//            else
//            {
//                // use a push_back loop
//            }
//        }

        ///
        this(this)
        {
            _Alloc_proxy();
            size_t len = size(); // the alloc len should probably keep a few in excess? (check the MS implementation)
            T* src = _Get_data()._Myfirst;
            _Buy(len);
            scope(failure) _Tidy();
            for (size_t i = 0; i < len; ++i)
                emplace(&_Get_data()._Myfirst[i], src[i]);
            _Get_data()._Mylast = _Get_data()._Myfirst + len;
        }

        ///
        ~this()                                                             { _Tidy(); }

        ///
        ref inout(Alloc) get_allocator() inout                              { return _Getal(); }

        ///
        size_type max_size() const nothrow @safe                            { return ((size_t.max / T.sizeof) - 1) / 2; } // HACK: clone the windows version precisely?

        ///
        size_type size() const nothrow @safe @nogc                          { return _Get_data()._Mylast - _Get_data()._Myfirst; }
        ///
        size_type capacity() const nothrow @safe @nogc                      { return _Get_data()._Myend - _Get_data()._Myfirst; }
        ///
        bool empty() const nothrow @safe @nogc                              { return _Get_data()._Myfirst == _Get_data()._Mylast; }
        ///
        inout(T)* data() inout nothrow @safe @nogc                          { return _Get_data()._Myfirst; }
        ///
        inout(T)[] as_array() inout @trusted @nogc                          { return _Get_data()._Myfirst[0 .. size()]; }
        ///
        ref inout(T) at(size_type i) inout @trusted @nogc                   { return _Get_data()._Myfirst[0 .. size()][i]; }

        ///
        ref T emplace_back(Args...)(auto ref Args args)
        {
            if (_Has_unused_capacity())
            {
                emplace(_Get_data()._Mylast, forward!args);
                _Orphan_range(_Get_data()._Mylast, _Get_data()._Mylast);
                return *_Get_data()._Mylast++;
            }
            return *_Emplace_reallocate(_Get_data()._Mylast, forward!args);
        }

        void pop_back()
		{
            static if (_ITERATOR_DEBUG_LEVEL == 2)
            {
                assert(!empty(), "vector empty before pop");
                _Orphan_range(_Get_data()._Mylast - 1, _Get_data()._Mylast);
            }
            destroy!true(_Get_data()._Mylast[-1]);
            --_Get_data()._Mylast;
		}

    private:
        import core.experimental.stdcpp.xutility : MSVCLinkDirectives;

        // Make sure the object files wont link against mismatching objects
        mixin MSVCLinkDirectives!true;

        pragma(inline, true)
        {
            ref inout(_Base.Alloc) _Getal() inout nothrow @safe @nogc       { return _Base._Mypair._Myval1; }
            ref inout(_Base.ValTy) _Get_data() inout nothrow @safe @nogc    { return _Base._Mypair._Myval2; }
        }

        void _Alloc_proxy() nothrow
        {
            static if (_ITERATOR_DEBUG_LEVEL > 0)
                _Base._Alloc_proxy();
        }

        void _AssignAllocator(ref const(allocator_type) al) nothrow
        {
            static if (_Base._Mypair._HasFirst)
                _Getal() = al;
        }

        bool _Buy(size_type _Newcapacity) @trusted @nogc
		{
            _Get_data()._Myfirst = null;
            _Get_data()._Mylast = null;
            _Get_data()._Myend = null;

            if (_Newcapacity == 0)
                return false;

            // TODO: how to handle this in D? kinda like a range exception...
//            if (_Newcapacity > max_size())
//                _Xlength();

            _Get_data()._Myfirst = _Getal().allocate(_Newcapacity);
            _Get_data()._Mylast = _Get_data()._Myfirst;
            _Get_data()._Myend = _Get_data()._Myfirst + _Newcapacity;

            return true;
		}

        void _Destroy(pointer _First, pointer _Last)
        {
            for (auto i = _Get_data()._Myfirst; i != _Get_data()._Mylast; ++i)
                destroy!true(*i);
        }

        void _Tidy()
        {
            _Base._Orphan_all();
            if (_Get_data()._Myfirst)
			{
                _Destroy(_Get_data()._Myfirst, _Get_data()._Mylast);
                _Getal().deallocate(_Get_data()._Myfirst, capacity());
                _Get_data()._Myfirst = null;
                _Get_data()._Mylast = null;
                _Get_data()._Myend = null;
			}
        }

        size_type _Unused_capacity() const pure nothrow @trusted @nogc
		{
            return _Get_data()._Myend - _Get_data()._Mylast;
		}

        bool _Has_unused_capacity() const pure nothrow @trusted @nogc
		{
            return _Get_data()._Myend != _Get_data()._Mylast;
		}

        pointer _Emplace_reallocate(_Valty...)(const pointer _Whereptr, auto ref _Valty _Val)
		{
            const size_type _Whereoff = _Whereptr - _Get_data()._Myfirst;
            const size_type _Oldsize = size();

            // TODO: what should we do in D? kinda like a range overflow?
//            if (_Oldsize == max_size())
//                _Xlength();

            const size_type _Newsize = _Oldsize + 1;
            const size_type _Newcapacity = _Calculate_growth(_Newsize);

            pointer _Newvec = _Getal().allocate(_Newcapacity);
            pointer _Constructed_last = _Newvec + _Whereoff + 1;
            pointer _Constructed_first = _Constructed_last;

            try
            {
                emplace(_Newvec + _Whereoff, forward!_Val);
                _Constructed_first = _Newvec + _Whereoff;
                for (size_t i = _Whereoff; i > 0; )
                {
                    --i;
                    _Get_data()._Myfirst[i].moveEmplace(_Newvec[i]);
                    _Constructed_first = _Newvec + i;
                }
            }
            catch (Throwable e)
            {
                _Destroy(_Constructed_first, _Constructed_last);
                _Getal().deallocate(_Newvec, _Newcapacity);
                throw e;
            }

            _Change_array(_Newvec, _Newsize, _Newcapacity);
            return _Get_data()._Myfirst + _Whereoff;
		}

        void _Change_array(pointer _Newvec, const size_type _Newsize, const size_type _Newcapacity)
		{
            _Base._Orphan_all();

            if (_Get_data()._Myfirst != null)
			{
                _Destroy(_Get_data()._Myfirst, _Get_data()._Mylast);
                _Getal().deallocate(_Get_data()._Myfirst, capacity());
			}

            _Get_data()._Myfirst = _Newvec;
            _Get_data()._Mylast = _Newvec + _Newsize;
            _Get_data()._Myend = _Newvec + _Newcapacity;
		}

        size_type _Calculate_growth(const size_type _Newsize) const pure nothrow @nogc @safe
		{
            const size_type _Oldcapacity = capacity();
            if (_Oldcapacity > max_size() - _Oldcapacity/2)
                return _Newsize;
            const size_type _Geometric = _Oldcapacity + _Oldcapacity/2;
            if (_Geometric < _Newsize)
                return _Newsize;
            return _Geometric;
		}

        static if (_ITERATOR_DEBUG_LEVEL == 2)
        {
            void _Orphan_range(pointer _First, pointer _Last) const
		    {
//                assert(false, "TODO");
//                _Lockit _Lock(_LOCK_DEBUG);
//
//                const_iterator ** _Pnext = reinterpret_cast<const_iterator **>(this->_Getpfirst());
//
//                if (_Pnext)
//			    {
//                    while (*_Pnext)
//				    {
//                        if ((*_Pnext)->_Ptr < _First || _Last < (*_Pnext)->_Ptr)
//					    {	// skip the iterator
//                            _Pnext = reinterpret_cast<const_iterator **>((*_Pnext)->_Getpnext());
//					    }
//                        else
//					    {	// orphan the iterator
//                            (*_Pnext)->_Clrcont();
//                            *_Pnext = *reinterpret_cast<const_iterator **>((*_Pnext)->_Getpnext());
//					    }
//				    }
//			    }
		    }
        }
        else
        {
            void _Orphan_range(pointer, pointer) const {}
        }

        _Vector_alloc!(_Vec_base_types!(T, Alloc)) _Base;
    }
    else version (None)
    {
        size_type size() const nothrow @safe @nogc                          { return 0; }
        size_type capacity() const nothrow @safe @nogc                      { return 0; }
        bool empty() const nothrow @safe @nogc                              { return true; }

        inout(T)* data() inout nothrow @safe @nogc                          { return null; }
        inout(T)[] as_array() inout nothrow @trusted @nogc                  { return null; }
        ref inout(T) at(size_type i) inout @trusted @nogc                   { data()[0]; }
    }
    else
    {
        static assert(false, "C++ runtime not supported");
    }

private:
    // HACK: because no rvalue->ref
    __gshared static immutable allocator_type defaultAlloc;
}


// platform detail
private:
version (CppRuntime_Microsoft)
{
    import core.experimental.stdcpp.xutility : _ITERATOR_DEBUG_LEVEL;

    extern (C++, struct) struct _Vec_base_types(_Ty, _Alloc0)
    {
        alias Ty = _Ty;
        alias Alloc = _Alloc0;
    }

    extern (C++, class) struct _Vector_alloc(_Alloc_types)
    {
        import core.experimental.stdcpp.xutility : _Compressed_pair;
    nothrow @safe @nogc:

        alias Ty = _Alloc_types.Ty;
        alias Alloc = _Alloc_types.Alloc;
        alias ValTy = _Vector_val!Ty;

        void _Orphan_all();

        static if (_ITERATOR_DEBUG_LEVEL > 0)
        {
            void _Alloc_proxy();
            void _Free_proxy();
        }

        _Compressed_pair!(Alloc, ValTy) _Mypair;
    }

    extern (C++, class) struct _Vector_val(T)
    {
        import core.experimental.stdcpp.xutility : _Container_base;
        import core.experimental.stdcpp.type_traits : is_empty;

        static if (!is_empty!_Container_base.value)
        {
            _Container_base _Base;
        }

        T* _Myfirst;   // pointer to beginning of array
        T* _Mylast;    // pointer to current end of sequence
        T* _Myend;     // pointer to end of array
    }
}
