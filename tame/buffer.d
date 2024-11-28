module tame.buffer;

enum maxAlloca = 2048;

/**
 * Fixed maximum number of items on the stack. Memory is a static stack buffer.
 * This buffer can be filled up and cleared for reuse.
 */

struct FixedBuffer(size_t LEN, T = char) if (T.sizeof == 1) {
	invariant (pos <= LEN);

	alias OutputFunc = void delegate(in T[]) @nogc;
	T[LEN] buf = void;
	alias buf this;
	size_t pos;
	OutputFunc outputFunc;

	pure @nogc nothrow @safe {
		/// constructor
		this(in T[] rhs) {
			this = rhs;
		}

		@property bool empty() const => pos == 0;

		@property T[] data() => buf[0 .. pos];

		void clear() {
			pos = 0;
		}
	}

	/// ditto
	this(F)(F oFunc) if (is(typeof(oFunc(null)))) {
		outputFunc = cast(OutputFunc)oFunc;
	}

	T opCast(T : bool)() const => !empty();

	T opCast(T)() const if (!is(T : bool)) => cast(T)buf[0 .. pos];

	/// assignment
	auto opAssign(in T[] rhs)
	in (rhs.length <= LEN) {
		pos = rhs.length;
		buf[0 .. pos] = rhs;
		return rhs;
	}

	/// append
	void opOpAssign(string op : "~", S)(S rhs) if (S.sizeof == 1) {
		if (pos == LEN) {
			outputFunc(buf[]);
			pos = 0;
		}
		buf[pos++] = cast(T)rhs;
	}

	/// ditto
	void opOpAssign(string op : "~", S)(ref S rhs) if (S.sizeof > 1) {
		this ~= (cast(T*)&rhs)[0 .. S.sizeof];
	}

	/// ditto
	ref opOpAssign(string op : "~")(in void[] rhs) @trusted {
		import core.stdc.string;

		auto s = cast(void[])rhs;
		auto remain = pos + s.length;
		for (;;) {
			auto outlen = remain < LEN ? remain : LEN;
			outlen -= pos;
			memcpy(buf.ptr + pos, s.ptr, outlen);
			s = s[outlen .. $];
			if (outlen + pos != LEN)
				break;
			pos = 0;
			remain -= LEN;
			outputFunc(buf[]);
		}
		pos = remain;
		return this;
	}

	pragma(inline, true)
	auto put(S)(S x) => opOpAssign!"~"(x);

	pragma(inline, true)
	auto put(S)(ref S x) => opOpAssign!"~"(x);

	alias length = pos;

	auto flush() {
		if (!pos)
			return false;
		outputFunc(buf[0 .. pos]);
		clear();
		return true;
	}
}

import core.stdc.stdlib;

struct TempBuffer(T) {
	T[] slice;
	bool callFree;

	@disable this(this);

	~this() nothrow {
		if (callFree)
			free(slice.ptr);
	}

pure nothrow @safe:
	T[] opSlice() => slice[];
	T[] opSlice(size_t a, size_t b) => slice[a .. b];
	T[] opSliceAssign(const(T)[] value, size_t a, size_t b) => slice[a .. b] = value;
	ref T opIndex(size_t i) => slice[i];
	@property size_t size() => T.sizeof * slice.length;
	@property size_t length() => slice.length;
	alias opDollar = length;
	@property T* ptr() @trusted => slice.ptr;

	alias ptr this;

	@property outputRange() {
		struct OutputRange {
			T* ptr;
			size_t idx;

			void put(T)(auto ref T t) {
				ptr[idx++] = t;
			}

			T[] opSlice() => ptr[0 .. idx];
		}

		return OutputRange(slice.ptr, 0);
	}
}

auto tempBuffer(T, alias length, size_t maxAlloca = .maxAlloca)(
	void* buffer = (T.sizeof * length <= maxAlloca) ? alloca(T.sizeof * length) : null)
	=> TempBuffer!T(cast(T*)(
			buffer ? buffer : malloc(T.sizeof * length))[0 .. length],
		buffer is null);

/**
Returns a structure to your stack that contains a buffer of $(D size) size.
Memory is allocated by calling `.alloc!T(count)` on it in order to get
`count` elements of type `T`. The return value will be a RAII structure
that releases the memory back to the stack buffer upon destruction, so it can
be reused. The pointer within that RAII structure is aligned to
`T.alignof`. If the internal buffer isn't enough to fulfill the request
including padding from alignment, then `malloc()` is used instead.

Warning:
	Always keep the return value of `.alloc()` around on your stack until
	you are done with its contents. Never pass it directly into functions as
	arguments!

Params:
	e = The size of the buffer on the stack.

Returns:
	ack buffer allocator.
 */
auto stackBuffer(size_t size)() @trusted {
	// All that remains of this after inlining is a stack pointer decrement and
	// a mov instruction for the `null`.
	StackBuffer!size buf = void;
	buf.last = cast(StackBufferEntry!void*)&buf.last;
	buf.sentinel = null;
	return buf;
}

auto asOutputRange(T)(T* t) {
	struct PointerRange {
		private T* start, ptr;

		void put()(auto ref const(T) t) {
			*ptr++ = t;
		}

		T[] opSlice() pure => start[0 .. ptr - start];
	}

	static assert(isOutputRange!(PointerRange, T));
	return PointerRange(t, t);
}

import core.memory,
std.algorithm : max, min;

struct Sink(T) {
	T[] buf;
	private size_t _len;
pure @nogc nothrow @safe:
	@disable this(this);

	this(in T[] s) {
		put(s);
	}

	~this() @trusted {
		pureFree(buf.ptr);
	}

	@property length() const => _len;
	@property void length(size_t n) {
		_len = n;
	}

	@property capacity() const => buf.length;
	@property void capacity(size_t n) scope @trusted {
		import core.checkedint : mulu;
		import core.exception;

		bool overflow;
		size_t reqsize = mulu(T.sizeof, n, overflow);
		if (!overflow) {
			buf = (cast(T*)pureRealloc(buf.ptr, reqsize))[0 .. n];
			if (!buf)
				onOutOfMemoryError();
		} else
			onOutOfMemoryError();
	}

	alias opDollar = length;
	alias opOpAssign(string op : "~") = put;

	void reserve(size_t n) scope {
		if (n > buf.length)
			capacity = n;
	}

	private void ensureAvail(size_t n) scope {
		import core.bitop : bsr;

		if ((n += _len) > buf.length) {

			// Note: new length calculation taken from std.array.appenderNewCapacity
			const mult = 100 + size_t(1000) / (bsr(n) + 1);
			capacity = max(n, (n * min(mult, 200) + 99) / 100);
		}
	}

	void put(in T c) scope @trusted {
		ensureAvail(1);
		buf[_len++] = cast(T)c;
	}

	void put(in T[] s) scope @trusted {
		ensureAvail(s.length);
		buf[_len .. _len + s.length] = cast(T[])s;
		_len += s.length;
	}

	void clear() scope {
		_len = 0;
	}

	ref inout(T) opIndex(size_t i) inout
	in (i < _len)
		=> buf[i];

	inout(T)[] opSlice() inout => buf[0 .. _len];
	alias data = opSlice;

	inout(T)[] opSlice(size_t a, size_t b) inout
	in (a <= b && b <= _len)
		=> buf[a .. b];
}

alias StringSink = Sink!char;

struct StackBuffer(size_t size) {
private:

	void[size] buf = void;
	StackBufferEntry!void* last;
	void* sentinel;

public:

	@disable this(this);

	StackBufferEntry!T alloc(T)(size_t n) @trusted {
		alias SBE = StackBufferEntry!T;
		T* target = cast(T*)(cast(size_t)last.ptr / T.alignof * T.alignof);
		if (target > buf.ptr && cast(size_t)(target - cast(T*)buf.ptr) >= n)
			return SBE(target - n, last);
		// TODO: Respect alignment here as well by padding. Optionally also embed a length in the heap block, so we can provide slicing of the whole thing.
		return SBE(n <= size_t.max / T.sizeof ? cast(T*)malloc(T.sizeof * n) : null);
	}
}

struct StackBufferEntry(T) {
private:
	StackBufferEntry!void* prev;

	this(T* ptr) {
		this.ptr = ptr;
	}

	this(T* ptr, ref StackBufferEntry!void* last) {
		this(ptr);
		prev = last;
		last = cast(StackBufferEntry!void*)&this;
	}

public:
	T* ptr;

	static if (!is(T == void)) {
		@disable this(this);

		~this() @trusted {
			if (prev) {
				StackBufferEntry!void* it = prev;
				while (it.prev)
					it = it.prev;
				auto last = cast(StackBufferEntry!void**)&prev.ptr;
				*last = prev;
			} else
				free(ptr);
		}

	pure nothrow @nogc:
		ref inout(T) opIndex(size_t i) inout => ptr[i];

		inout(T)[] opSlice(size_t a, size_t b) inout => ptr[a .. b];

		@property auto range() @safe => ptr.asOutputRange();
	}
}
