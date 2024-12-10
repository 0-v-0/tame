module tame.unsafe.scoped;

import std.traits;
import tame.bitop : alignTo;

/**
Allocates a `class` object right inside the current scope,
therefore avoiding the overhead of `new`. This facility is unsafe;
it is the responsibility of the user to not escape a reference to the
object outside the scope.

The class destructor will be called when the result of `scoped()` is
itself destroyed.

Scoped class instances can be embedded in a parent `class` or `struct`,
just like a child struct instance. Scoped member variables must have
type `typeof(scoped!Class(args))`, and be initialized with a call to
scoped. See below for an example.

Note:
It's illegal to move a class instance even if you are sure there
are no pointers to it. As such, it is illegal to move a scoped object.
*/
template scoped(T) if (classInstanceAlignment!T <= ubyte.max) {
	// _d_newclass now use default GC alignment (looks like (void*).sizeof * 2 for
	// small objects). We will just use the maximum of filed alignments.
	enum alignment = classInstanceAlignment!T;
	enum size = __traits(classInstanceSize, T);
	alias aligned = alignTo!alignment;

	static struct Scoped {
		// Addition of `alignment` is required as `_store` can be misaligned in memory.
		private void[aligned(size) + alignment] _store = void;

		@property inout(T) payload() inout {
			void* alignedStore = cast(void*)aligned(cast(size_t)_store.ptr);
			// As `Scoped` can be unaligned moved in memory class instance should be moved accordingly.
			immutable size_t d = alignedStore - _store.ptr;
			assert(d < alignment);
			auto currD = cast(ubyte*)&_store[$ - ubyte.sizeof];
			if (d != *currD) {
				import core.stdc.string : memmove;

				memmove(alignedStore, _store.ptr + *currD, size);
				*currD = cast(ubyte)d;
			}
			return cast(inout(T))alignedStore;
		}

		alias payload this;

		@disable this();
		@disable this(this);
		// dfmt off
		static if (hasMember!(T, "__xdtor"))
			~this() {
				// `destroy` will also write .init but we have no functions in druntime
				// for deterministic finalization and memory releasing for now.
				destroy(payload);
			}
// dfmt on
	}

	/** Returns the _scoped object.
    Params: args = Arguments to pass to `T`'s constructor.
    */
	@system auto scoped(A...)(auto ref A args) {
		import core.lifetime : emplace, forward;

		Scoped result = void;
		void* alignedStore = cast(void*)aligned(cast(size_t)result._store.ptr);
		immutable size_t d = alignedStore - result._store.ptr;
		assert(d < alignment);
		*cast(ubyte*)&result._store[$ - ubyte.sizeof] = cast(ubyte)d;
		emplace!(Unqual!T)(result._store[d .. $ - ubyte.sizeof], forward!args);
		return result;
	}
}

///
unittest {
	class A {
		int x;
		this() {
			x = 0;
		}

		this(int i) {
			x = i;
		}

		~this() {
		}
	}

	// Standard usage, constructing A on the stack
	auto a1 = scoped!A();
	a1.x = 42;

	// Result of `scoped` call implicitly converts to a class reference
	A aRef = a1;
	assert(aRef.x == 42);

	// Scoped destruction
	{
		auto a2 = scoped!A(1);
		assert(a2.x == 1);
		aRef = a2;
		// a2 is destroyed here, calling A's destructor
	}
	// aRef is now an invalid reference

	// Here the temporary scoped A is immediately destroyed.
	// This means the reference is then invalid.
	version (Bug) {
		// Wrong, should use `auto`
		A invalid = scoped!A();
	}

	// Restrictions
	version (Bug) {
		import std.algorithm.mutation : move;

		auto invalid = a1.move; // illegal, scoped objects can't be moved
	}
	static assert(!is(typeof({
				auto e1 = a1; // illegal, scoped objects can't be copied
				assert([a1][0].x == 42); // ditto
			})));
	static assert(!is(typeof({
				alias ScopedObject = typeof(a1);
				auto e2 = ScopedObject(); // illegal, must be built via scoped!A
				auto e3 = ScopedObject(1); // ditto
			})));

	// Use with alias
	alias makeScopedA = scoped!A;
	auto a3 = makeScopedA();
	auto a4 = makeScopedA(1);

	// Use as member variable
	struct B {
		typeof(scoped!A()) a; // note the trailing parentheses

		this(int i) {
			// construct member
			a = scoped!A(i);
		}
	}

	// Stack-allocate
	auto b1 = B(5);
	aRef = b1.a;
	assert(aRef.x == 5);
	destroy(b1); // calls A's destructor for b1.a
	// aRef is now an invalid reference

	// Heap-allocate
	auto b2 = new B(6);
	assert(b2.a.x == 6);
	destroy(*b2); // calls A's destructor for b2.a
}

// https://issues.dlang.org/show_bug.cgi?id=6580 testcase
unittest {
	enum alignment = (void*).alignof;

	static class C0 {
	}

	static class C1 {
		byte b;
	}

	static class C2 {
		byte[2] b;
	}

	static class C3 {
		byte[3] b;
	}

	static class C7 {
		byte[7] b;
	}

	static assert(scoped!C0().sizeof % alignment == 0);
	static assert(scoped!C1().sizeof % alignment == 0);
	static assert(scoped!C2().sizeof % alignment == 0);
	static assert(scoped!C3().sizeof % alignment == 0);
	static assert(scoped!C7().sizeof % alignment == 0);

	static class C1long {
		long long_;
		byte byte_ = 4;
		this() {
		}

		this(long _long, ref int i) {
			long_ = _long;
			++i;
		}
	}

	static class C2long {
		byte[2] byte_ = [5, 6];
		long long_ = 7;
	}

	enum longAlignment = long.alignof;
	static assert(scoped!C1long().sizeof % longAlignment == 0);
	static assert(scoped!C2long().sizeof % longAlignment == 0);

	void alignmentTest() {
		int var = 5;
		auto c1long = scoped!C1long(3, var);
		assert(var == 6);
		auto c2long = scoped!C2long();
		assert(cast(uint)&c1long.long_ % longAlignment == 0);
		assert(cast(uint)&c2long.long_ % longAlignment == 0);
		assert(c1long.long_ == 3 && c1long.byte_ == 4);
		assert(c2long.byte_ == [5, 6] && c2long.long_ == 7);
	}

	alignmentTest();

	version (DigitalMars) {
		void test(size_t size) {
			import core.stdc.stdlib : alloca;

			cast(void)alloca(size);
			alignmentTest();
		}

		foreach (i; 0 .. 10)
			test(i);
	} else {
		void test(size_t size)() {
			byte[size] arr;
			alignmentTest();
		}

		static foreach (i; 0 .. 11)
			test!i();
	}
}

// Original https://issues.dlang.org/show_bug.cgi?id=6580 testcase
unittest {
	class C {
		int i;
		byte b;
	}

	auto sa = [scoped!C(), scoped!C()];
	assert(cast(uint)&sa[0].i % int.alignof == 0);
	assert(cast(uint)&sa[1].i % int.alignof == 0); // fails
}

unittest {
	class A {
		int x = 1;
	}

	auto a1 = scoped!A();
	assert(a1.x == 1);
	auto a2 = scoped!A();
	a1.x = 42;
	a2.x = 53;
	assert(a1.x == 42);
}

unittest {
	class A {
		int x = 1;
		this() {
			x = 2;
		}
	}

	auto a1 = scoped!A();
	assert(a1.x == 2);
	auto a2 = scoped!A();
	a1.x = 42;
	a2.x = 53;
	assert(a1.x == 42);
}

unittest {
	class A {
		int x = 1;
		this(int y) {
			x = y;
		}

		~this() {
		}
	}

	auto a1 = scoped!A(5);
	assert(a1.x == 5);
	auto a2 = scoped!A(42);
	a1.x = 42;
	a2.x = 53;
	assert(a1.x == 42);
}

unittest {
	class A {
		static bool dead;
		~this() {
			dead = true;
		}
	}

	class B : A {
		static bool dead;
		~this() {
			dead = true;
		}
	}

	{
		auto b = scoped!B();
	}
	assert(B.dead, "asdasd");
	assert(A.dead, "asdasd");
}

// https://issues.dlang.org/show_bug.cgi?id=8039 testcase
unittest {
	static int dels;
	static struct S {
		~this() {
			++dels;
		}
	}

	static class A {
		S s;
	}

	dels = 0;
	{
		scoped!A();
	}
	assert(dels == 1);

	static class B {
		S[2] s;
	}

	dels = 0;
	{
		scoped!B();
	}
	assert(dels == 2);

	static struct S2 {
		S[3] s;
	}

	static class C {
		S2[2] s;
	}

	dels = 0;
	{
		scoped!C();
	}
	assert(dels == 6);

	static class D : A {
		S2[2] s;
	}

	dels = 0;
	{
		scoped!D();
	}
	assert(dels == 1 + 6);
}

unittest {
	// https://issues.dlang.org/show_bug.cgi?id=4500
	class A {
		this() {
			a = this;
		}

		this(int i) {
			a = this;
		}

		A a;
		bool check() {
			return this is a;
		}
	}

	auto a1 = scoped!A();
	assert(a1.check());

	auto a2 = scoped!A(1);
	assert(a2.check());

	a1.a = a1;
	assert(a1.check());
}

unittest {
	static class A {
		static int sdtor;

		this() {
			++sdtor;
			assert(sdtor == 1);
		}

		~this() {
			assert(sdtor == 1);
			--sdtor;
		}
	}

	interface Bob {
	}

	static class ABob : A, Bob {
		this() {
			++sdtor;
			assert(sdtor == 2);
		}

		~this() {
			assert(sdtor == 2);
			--sdtor;
		}
	}

	A.sdtor = 0;
	scope (exit)
		assert(A.sdtor == 0);
	auto abob = scoped!ABob();
}

@safe unittest {
	static class A {
		this(int) {
		}
	}

	static assert(!__traits(compiles, scoped!A()));
}

unittest {
	static class A {
		@property inout(int) foo() inout {
			return 1;
		}
	}

	auto a1 = scoped!A();
	assert(a1.foo == 1);
	static assert(is(typeof(a1.foo) == int));

	auto a2 = scoped!(const A)();
	assert(a2.foo == 1);
	static assert(is(typeof(a2.foo) == const(int)));

	auto a3 = scoped!(immutable A)();
	assert(a3.foo == 1);
	static assert(is(typeof(a3.foo) == immutable(int)));

	const c1 = scoped!A();
	assert(c1.foo == 1);
	static assert(is(typeof(c1.foo) == const(int)));

	const c2 = scoped!(const A)();
	assert(c2.foo == 1);
	static assert(is(typeof(c2.foo) == const(int)));

	const c3 = scoped!(immutable A)();
	assert(c3.foo == 1);
	static assert(is(typeof(c3.foo) == immutable(int)));
}

unittest {
	class C {
		this(int rval) {
			assert(rval == 1);
		}

		this(ref int lval) {
			assert(lval == 3);
			++lval;
		}
	}

	auto c1 = scoped!C(1);
	int lval = 3;
	auto c2 = scoped!C(lval);
	assert(lval == 4);
}

unittest {
	class C {
		this() {
		}

		this(int) {
		}

		this(int, int) {
		}
	}

	alias makeScopedC = scoped!C;

	auto a = makeScopedC();
	auto b = makeScopedC(1);
	auto c = makeScopedC(1, 1);

	static assert(is(typeof(a) == typeof(b)));
	static assert(is(typeof(b) == typeof(c)));
}
