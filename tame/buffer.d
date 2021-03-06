module tame.buffer;

enum maxAlloca = 2048;

/*
 *
 * Fixed maximum number of items on the stack. Memory is a static stack buffer.
 * This buffer can be filled up and cleared for reuse.
 *
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

		@property bool empty() const {
			return pos == 0;
		}

		@property T[] data() {
			return buf[0 .. pos];
		}

		void clear() {
			pos = 0;
		}
	}

	/// ditto
	this(F)(F oFunc) if (is(typeof(oFunc(null)))) {
		outputFunc = cast(OutputFunc)oFunc;
	}

	T opCast(T : bool)() const {
		return !empty();
	}

	T opCast(T)() const if (!is(T : bool)) {
		return cast(T)buf[0 .. pos];
	}

	/// assignment
	auto opAssign(in T[] rhs)
	in (rhs.length <= LEN) {
		pos = rhs.length;
		buf[0 .. pos] = rhs;
		return rhs;
	}

	/// append
	auto opOpAssign(string op : "~", S)(S rhs) if (S.sizeof == 1) {
		if (pos == LEN) {
			outputFunc(buf[]);
			pos = 0;
		}
		buf[pos++] = cast(T)rhs;
	}

	/// ditto
	auto opOpAssign(string op : "~", S)(ref S rhs) if (S.sizeof > 1) {
		this ~= (cast(T*)&rhs)[0 .. S.sizeof];
	}

	/// ditto
	auto ref opOpAssign(string op : "~")(in void[] rhs) {
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
	//dfmt off
	T[] opSlice() { return slice[]; }
	T[] opSlice(size_t a, size_t b) { return slice[a .. b]; }
	T[] opSliceAssign(const(T)[] value, size_t a, size_t b) { return slice[a .. b] = value; }
	ref T opIndex(size_t idx) { return slice[idx]; }
	@property size_t size() { return T.sizeof * slice.length; }
	@property size_t length() { return slice.length; }
	alias opDollar = length;
	@property T* ptr() @trusted { return slice.ptr; } // must use .ptr here for zero length strings

	alias ptr this;

	auto makeOutputRange() {
		struct OutputRange {
			T* ptr;
			size_t idx;

			void put(T)(auto ref T t) { ptr[idx++] = t; }

			T[] opSlice() { return ptr[0 .. idx]; }
		}

		return OutputRange(slice.ptr, 0);
	}
	//dfmt on
}

TempBuffer!T tempBuffer(T, alias length, size_t maxAlloca = .maxAlloca)(
	void* buffer = (T.sizeof * length <= maxAlloca) ? alloca(T.sizeof * length) : null) {
	return TempBuffer!T((cast(T*)(
			buffer ? buffer
			: malloc(T.sizeof * length)))[0 .. length],
		buffer is null);
}

/*
 *
 * Returns a structure to your stack that contains a buffer of $(D size) size.
 * Memory is allocated by calling `.alloc!T(count)` on it in order to get
 * `count` elements of type `T`. The return value will be a RAII structure
 * that releases the memory back to the stack buffer upon destruction, so it can
 * be reused. The pointer within that RAII structure is aligned to
 * `T.alignof`. If the internal buffer isn't enough to fulfill the request
 * including padding from alignment, then `malloc()` is used instead.
 *
 * Warning:
 *   Always keep the return value of `.alloc()` around on your stack until
 *   you are done with its contents. Never pass it directly into functions as
 *   arguments!
 *
 * Params:
 *   size = The size of the buffer on the stack.
 *
 * Returns:
 *   A stack buffer allocator.
 *
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

		T[] opSlice() pure {
			return start[0 .. ptr - start];
		}
	}

	static assert(isOutputRange!(PointerRange, T));
	return PointerRange(t, t);
}

package:

struct StackBuffer(size_t size) {
private:

	void[size] space = void;
	StackBufferEntry!void* last;
	void* sentinel;

public:

	@disable this(this);

	@trusted
	StackBufferEntry!T alloc(T)(size_t howMany) {
		enum max = size_t.max / T.sizeof;
		alias SBE = StackBufferEntry!T;
		T* target = cast(T*)(cast(uintptr_t)last.ptr / T.alignof * T.alignof);
		if (target > space.ptr && cast(uintptr_t)(target - cast(T*)space.ptr) >= howMany)
			return SBE(target - howMany, last);
		else // TODO: Respect alignment here as well by padding. Optionally also embed a length in the heap block, so we can provide slicing of the whole thing.
			return SBE(howMany <= max ? cast(T*)malloc(T.sizeof * howMany) : null);
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
		ref inout(T) opIndex(size_t idx) @system inout {
			return ptr[idx];
		}

		inout(T)[] opSlice(size_t a, size_t b) @system inout {
			return ptr[a .. b];
		}

		@property auto range() @safe {
			return ptr.asOutputRange();
		}
	}
}
