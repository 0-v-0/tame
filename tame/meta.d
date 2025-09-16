module tame.meta;

public import std.meta : IndexOf = staticIndexOf,
	Seq = AliasSeq,
	SeqMap = staticMap,
	Uniq = NoDuplicates;
import std.traits;

@safe:

/++
	Returns the index of the last occurrence of `args[0]` in the
	sequence `args[1 .. $]`. `args` may be types or compile-time values.
	If not found, `-1` is returned.
	Params:
		args = A sequence of types or compile-time values, where the first
		element is the one to search for in the rest of the sequence.
+/
template LastIndexOf(args...)
if (args.length >= 1) {
	enum LastIndexOf = {
		static foreach_reverse (idx, arg; args[1 .. $])
			static if (isSame!(args[0], arg)) // `if (__ctfe)` is redundant here but avoids the "Unreachable code" warning.
				if (__ctfe)
					return idx;
		return -1;
	}();
}

///
unittest {
	static assert(LastIndexOf!(int, float, int, string, int) == 3);
	static assert(LastIndexOf!(int, float, string) == -1);
	static assert(LastIndexOf!(3, 1, 2, 3, 4, 3) == 4);
	static assert(LastIndexOf!(3, 1, 2, 4) == -1);
}

/++
	Returns a sequence created from `args[1 .. $]` with the first occurrence,
	if any, of `args[0]` removed.
	Params:
		args = A sequence of types or compile-time values, where the first
		element is the one to remove from the rest of the sequence.
+/
template EraseLast(args...)
if (args.length >= 1) {
	private enum pos = LastIndexOf!(args[0], args[1 .. $]);
	static if (pos < 0)
		alias EraseLast = args[1 .. $];
	else
		alias EraseLast = Seq!(args[1 .. pos + 1], args[pos + 2 .. $]);
}

///
unittest {
	static assert(is(EraseLast!(int, float, int, string, int) == Seq!(float, int, string)));
	static assert(is(EraseLast!(int, float, string) == Seq!(float, string)));
	static assert(EraseLast!(3, 1, 2, 3, 4, 3) == Seq!(1, 2, 3, 4));
	static assert(EraseLast!(3, 1, 2, 4) == Seq!(1, 2, 4));
}

/++
	Returns a sequence created from `args[2 .. $]` with the first occurrence,
	if any, of `args[0]` replaced by `args[1]`.
	Params:
		args = A sequence of types or compile-time values, where the first
		element is the one to replace in the rest of the sequence, and the
		second element is the replacement.
+/
template Replace(args...)
if (args.length >= 2) {
	private enum pos = IndexOf!(args[0], args[2 .. $]);
	static if (pos < 0)
		alias Replace = args[2 .. $];
	else
		alias Replace = Seq!(args[2 .. pos + 2], args[1], args[pos + 3 .. $]);
}

///
unittest {
	alias Types = Seq!(int, long, long, int, float);

	alias TL = Replace!(long, char, Types);
	static assert(is(TL == Seq!(int, char, long, int, float)));
}

/++
	Returns a sequence created from `args[2 .. $]` with the last occurrence,
	if any, of `args[0]` replaced by `args[1]`.
	Params:
		args = A sequence of types or compile-time values, where the first
		element is the one to replace in the rest of the sequence, and the
		second element is the replacement.
+/
template ReplaceLast(args...)
if (args.length >= 2) {
	private enum pos = LastIndexOf!(args[0], args[2 .. $]);
	static if (pos < 0)
		alias ReplaceLast = args[2 .. $];
	else
		alias ReplaceLast = Seq!(args[2 .. pos + 2], args[1], args[pos + 3 .. $]);
}

///
unittest {
	alias Types = Seq!(int, long, long, int, float);
	alias TL = ReplaceLast!(long, char, Types);
	static assert(is(TL == Seq!(int, long, char, int, float)));
}

struct Import(string mod) {
	template opDispatch(string name) {
		mixin("import opDispatch = ", mod, ".", name, ";");
	}
}

template Forward(string member) {
	pragma(inline, true) ref auto opDispatch(string field, A...)(auto ref A args) {
		import std.functional : forward;

		static if (A.length)
			return mixin(member, ".", field, "(forward!args);");
		else
			return mixin(member, ".", field, ";");
	}
}

template Iota(int begin, int end) {
	alias Iota = Seq!();
	static foreach (i; begin .. end)
		Iota = Seq!(Iota, i);
}

///
unittest {
	static assert(Iota!(0, 0) == Seq!());
	static assert(Iota!(0, 5) == Seq!(0, 1, 2, 3, 4));
}

template getUDA(alias sym, T) {
	static foreach (uda; __traits(getAttributes, sym))
		static if (is(typeof(getUDA) == void) && is(typeof(uda) == T))
			alias getUDA = uda;
	static if (is(typeof(getUDA) == void))
		alias getUDA = T.init;
}

alias getAttrs(alias symbol, string member) =
	__traits(getAttributes, __traits(getMember, symbol, member));

template getSymbolsWith(alias attr, symbols...) {
	template hasAttr(alias symbol, string name) {
		static if (is(typeof(getAttrs!(symbol, name))))
			static foreach (a; getAttrs!(symbol, name)) {
				static if (is(typeof(hasAttr) == void)) {
					static if (__traits(isSame, a, attr))
						enum hasAttr = true;
					else static if (__traits(isTemplate, attr)) {
						static if (is(typeof(a) == attr!A, A...))
							enum hasAttr = true;
					} else {
						static if (is(typeof(a) == attr))
							enum hasAttr = true;
					}
				}
			}
		static if (is(typeof(hasAttr) == void))
			enum hasAttr = false;
	}

	alias getSymbolsWith = Seq!();
	static foreach (symbol; symbols) {
		static foreach (name; __traits(derivedMembers, symbol))
			static if (hasAttr!(symbol, name))
				getSymbolsWith = Seq!(getSymbolsWith, __traits(getMember, symbol, name));
	}
}

alias Omit(size_t I, T...) = Seq!(T[0 .. I], T[I + 1 .. $]);

/++
	Generates a mixin string for repeating code. It can be used to unroll variadic arguments.
	A format string is instantiated a certain number times with an incrementing parameter.
	The results are then concatenated using an optional joiner.

	Params:
	length = Number of elements you want to join. It is passed into format() as an incrementing number from [0 .. count).
	fmt = The format string to apply on each instantiation. Use %1d$ to refer to the current index multiple times when necessary.
	joiner = Optional string that will be placed between instances. It could be a space or an arithmetic operation.

	Returns: The combined elements as a mixin string.

	See_Also:
	[A simple way to do compile time loop unrolling](http://forum.dlang.org/thread/vqfvihyezbmwcjkmpzin@forum.dlang.org)
+/
auto ctfeJoin(size_t length)(in string fmt, in string joiner = null) {
	import std.algorithm : map;
	import std.range : iota;

	// BUG: Cannot use, join(), as it "cannot access the nested function 'ctfeJoin'".
	string result;
	foreach (inst; map!(i => format(fmt, i))(iota(length))) {
		if (result && joiner)
			result ~= joiner;
		result ~= inst;
	}
	return result;
}

/++
	Get the number of optional parameters of a function.
	Params:
		f = The function to inspect.
+/
template OptionalParameterCount(alias f) {
	alias defs = ParameterDefaults!f;
	template OPC(alias f, size_t cnt) {
		static if (cnt > defs.length || is(defs[$ - cnt] == void))
			enum OPC = cnt - 1;
		else
			enum OPC = OPC!(f, cnt + 1);
	}

	enum OptionalParameterCount = OPC!(f, 0);
}

///
unittest {
	static assert(OptionalParameterCount!((int a, int b, int c = 0) {}) == 1);
	static assert(OptionalParameterCount!((int a = 0, int b = 0) {}) == 2);
	static assert(OptionalParameterCount!((int a, int b) {}) == 0);
	static assert(OptionalParameterCount!(() {}) == 0);
}

/++
	`_` is a enum that provides overloaded `=` operator.
	That overload takes a value and promptly throws it away.
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
	_ = new Object();
	_ = _;
}

/++
A copy of std::tie from C++.
TODO: write proper documentation for this
+/
auto tie(T...)(ref T args) {
	struct Impl {
		void opAssign(U)(U tuple)
		if (U.length >= T.length) {
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

private:
enum isSame(A, B) = is(A == B);
template isSame(alias a, alias b) {
	static if (!is(typeof(&a && &b)) // at least one is an rvalue
		&& __traits(compiles, { enum isSame = a == b; })) { // c-t comparable
				enum isSame = a == b;
			} else {
			enum isSame = __traits(isSame, a, b);
		}
		}
