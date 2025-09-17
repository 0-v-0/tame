module tame.atomic;

import core.atomic;
import std.traits : CommonType, isInstanceOf;

/++
A simple atomic wrapper around a value of type `T`.
Params:
	T = the type of the value to store
	ms = the memory order to use for atomic operations, defaults to `MemoryOrder.seq`
+/
struct Atomic(T, MemoryOrder ms = MemoryOrder.seq) {
	this(const T val) {
		value = val;
	}

	this(R)(const ref Atomic!R val)
	if (is(typeof(cast(T)val))) {
		value = cast(T)val;
	}

	/++
		Assign some `value` to atomic storage.
		Params:
			val = assign value.
	+/
	auto opAssign(const T val) {
		atomicStore!ms(value, val);
		return val;
	}
	/++
		Assign some `value` value to atomic storage.
		Params:
			val = assign value.
	+/
	auto opAssign(R)(const ref Atomic!R val)
	if (is(typeof(cast(T)val))) {
		atomicStore!ms(value, cast(T)atomicLoad!ms(val.value));
		return val;
	}

	/++
		Atomic load and exchange rvalue.
		Params:
			op = the operation to perform, one of `+ - * / % ^^ & | ^ << >> >>>`
			val = value for exchange.
	+/
	auto opOpAssign(string op)(const T val)
		=> atomicOp!(op ~ '=')(value, val);

	/// Atomic load and exchange rvalue.
	auto opUnary(string op)() const
	if (op != "++" && op != "--")
		=> mixin(op ~ "atomicLoad!ms(value);");

	/// Atomic increment/decrement.
	auto opUnary(string op)()
	if (op == "++" || op == "--")
		=> atomicOp!(op[0] ~ "=")(value, 1);

	/// Atomic load and compare.
	bool opEquals(R)(const ref Atomic!R rhs) const {
		alias CT = CommonType!(T, R);
		return cast(CT)this == cast(CT)rhs;
	}

	/// ditto
	bool opEquals(R)(const R rhs) const
	if (!isInstanceOf!(Atomic, R)) {
		static if (is(typeof(cast(T)rhs))) {
			alias U = T;
		} else {
			alias U = R;
		}
		return cast(U)this == cast(U)rhs;
	}

	/// Atomic load and compare.
	int opCmp(R)(const ref Atomic!R rhs) const {
		alias CT = CommonType!(T, R);
		CT left = cast(CT)this;
		CT right = cast(CT)rhs;
		return (left > right) - (left < right);
	}

	/// ditto
	int opCmp(R)(const R rhs) const
	if (is(typeof(cast(T)rhs)) || is(typeof(cast(R)this))) {
		static if (is(typeof(cast(T)rhs))) {
			T left = cast(T)this;
			T right = cast(T)rhs;
		} else {
			R left = cast(R)this;
			R right = cast(R)rhs;
		}
		return (left > right) - (left < right);
	}

	/// Atomic load and exchange rvalue.
	auto opBinary(string op, R)(const Atomic!R rhs) const
	if (!is(CommonType!(T, R) == void)) {
		alias CT = CommonType!(T, R);
		return mixin("cast(CT)this" ~ op ~ "cast(CT)rhs;");
	}

	/// ditto
	auto opBinary(string op, R)(const R rhs) const
	if (is(typeof(cast(T)rhs)) || is(typeof(cast(R)this))) {
		static if (is(typeof(cast(T)rhs))) {
			alias U = T;
		} else {
			alias U = R;
		}

		return mixin("cast(U)this" ~ op ~ "cast(U)rhs;");
	}

	/// Atomic load and convert to convertible type.
	U opCast(U)() const => cast(U)atomicLoad!ms(value);

	/// Unsupported operations will result in call atomicLoad for get rvalue copy (const)
	alias opCast this;

	shared T value;
}
