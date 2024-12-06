module tame.buffer;

/++
	Fixed maximum number of items on the stack. Memory is a static stack buffer.
	This buffer can be filled up and cleared for reuse.
+/
struct FixedBuffer(size_t N, T = char) if (T.sizeof == 1) {
	invariant (pos <= N);

	alias OutputFunc = void delegate(in T[]) @nogc;
	T[N] buf = void;
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
	in (rhs.length <= N) {
		pos = rhs.length;
		buf[0 .. pos] = rhs;
		return rhs;
	}

	/// append
	void opOpAssign(string op : "~", S)(S rhs) if (S.sizeof == 1) {
		if (pos == N) {
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
			auto outlen = remain < N ? remain : N;
			outlen -= pos;
			memcpy(buf.ptr + pos, s.ptr, outlen);
			s = s[outlen .. $];
			if (outlen + pos != N)
				break;
			pos = 0;
			remain -= N;
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

import core.memory,
core.stdc.stdlib,
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
		if (!__ctfe)
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

		if (__ctfe) {
			buf.length = n;
			return;
		}
		bool overflow;
		const reqsize = mulu(T.sizeof, n, overflow);
		if (overflow)
			onOutOfMemoryError();
		buf = (cast(T*)pureRealloc(buf.ptr, reqsize))[0 .. n];
		if (!buf)
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
