module tame.meta;

import std.traits;
import std.meta : AliasSeq;

struct Import(string Module) {
	template opDispatch(string name) {
		mixin("import opDispatch = " ~ Module ~ "." ~ name ~ ";");
	}
}

template Forward(string member) {
	pragma(inline, true) ref auto opDispatch(string field, A...)(auto ref A args) {
		import std.functional : forward;

		static if (A.length)
			mixin("return ", member, ".", field, "(forward!args);");
		else
			mixin("return ", member, ".", field, ";");
	}
}

template staticIota(int begin, int end) {
	alias staticIota = AliasSeq!();
	static foreach (i; begin .. end)
		staticIota = AliasSeq!(staticIota, i);
}

///
unittest {
	static assert(staticIota!(0, 0) == AliasSeq!());
	static assert(staticIota!(0, 5) == AliasSeq!(0, 1, 2, 3, 4));
}

template getUDA(alias sym, T) {
	static foreach (uda; __traits(getAttributes, sym))
		static if (is(typeof(uda) == T))
			alias getUDA = uda;
	static if (is(typeof(getUDA) == void))
		alias getUDA = T.init;
}

alias CutOut(size_t I, T...) = AliasSeq!(T[0 .. I], T[I + 1 .. $]);

/**
 * Generates a mixin string for repeating code. It can be used to unroll variadic arguments.
 * A format string is instantiated a certain number times with an incrementing parameter.
 * The results are then concatenated using an optional joiner.
 *
 * Params:
 *   length = Number of elements you want to join. It is passed into format() as an incrementing number from [0 .. count$(RPAREN).
 *   fmt = The format string to apply on each instanciation. Use %1d$ to refer to the current index multiple times when necessary.
 *   joiner = Optional string that will be placed between instances. It could be a space or an arithmetic operation.
 *
 * Returns:
 *   The combined elements as a mixin string.
 *
 * See_Also:
 *   $(LINK2 http://forum.dlang.org/thread/vqfvihyezbmwcjkmpzin@forum.dlang.org, A simple way to do compile time loop unrolling)
 */
auto ctfeJoin(size_t length)(in string fmt, in string joiner = null) {
	import std.range : iota;
	import std.algorithm : map;

	// BUG: Cannot use, join(), as it "cannot access the nested function 'ctfeJoin'".
	string result;
	foreach (inst; map!(i => format(fmt, i))(iota(length))) {
		if (result && joiner)
			result ~= joiner;
		result ~= inst;
	}
	return result;
}

auto ParameterDefaultsCount(func...)() {
	template PDC(alias func, size_t cnt) {
		static if (__traits(compiles, func(Parameters!func[0 .. cnt])))
			enum PDC = PDC!(func, cnt - 1);
		else
			enum PDC = arity!func - cnt;
	}

	size_t n;
	foreach (f; func)
		n += PDC!(f, arity!f);
	return n;
}

unittest {
	import tame.ascii;

	static assert(ParameterDefaultsCount!classify == 0);
}

/++
`_` is a enum that provides overloaded `=` operator. That overload takes a value and promptly throws it away.
Examples:
---
_ = 2 + 3;
_ = new A();
---
+/
enum _ = Impl();

private struct Impl {
	/++
	Take an argument, throw it away and do nothing.
	Params:
		first = value to be ignored.
	+/
	pragma(inline, true)
	void opAssign(T)(in T) inout {
	}
}
///
unittest {
	_ = 2;
	_ = _;
}

/++
A copy of std::tie from C++.
TODO: write proper documentation for this
+/
auto tie(T...)(ref T args) {
	struct Impl {
		void opAssign(U)(U tuple) if (U.length >= T.length) {
			static foreach (i; 0 .. T.length)
				args[i] = tuple[i];
		}
	}

	return Impl();
}
///
unittest {
	import std.typecons;

	int a;
	string b;
	tie(a, b) = tuple(3, "hi");
	assert(a == 3 && b == "hi");
}
