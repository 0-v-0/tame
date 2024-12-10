module tame.util;

import std.ascii,
std.meta,
std.traits;

package:

T* alloc(T, bool init = true)() {
	import core.stdc.stdlib;

	if (T* p = cast(T*)(init ? calloc(1, T.sizeof) : malloc(T.sizeof)))
		return p;
	import core.exception : onOutOfMemoryError;

	onOutOfMemoryError();
}

int numDigits(T : ulong)(T num, uint radix = 10) @trusted {
	alias U = AliasSeq!(uint, ulong)[T.sizeof / 8];
	static if (isSigned!T) {
		int digits = void;
		U n = void;
		if (num <= 0) {
			digits = 1;
			n = -num;
		} else {
			digits = 0;
			n = num;
		}
	} else {
		int digits = num == 0;
		U n = num;
	}
	for (; n; n /= radix)
		digits++;
	return digits;
}

@safe unittest {
	assert(numDigits(0) == 1);
	assert(numDigits(11) == 2);
	assert(numDigits(-1) == 2);
	assert(numDigits(-123) == 4);

	assert(numDigits(int.min) == 11);
	assert(numDigits(int.max) == 10);
	assert(numDigits(long.min) == 20);
	assert(numDigits(long.max) == 19);
	assert(numDigits(ulong.min) == 1);
	assert(numDigits(ulong.max) == 20);

	foreach (i; 0 .. 20) {
		assert(numDigits(10UL ^^ i) == i + 1);
	}
}

/++
	Match types like `std.typecons.Nullable` ie `mir.core.Nullable`
+/
template isStdNullable(T) {
	T* aggregate;

	enum bool isStdNullable =
		hasMember!(T, "isNull") &&
		hasMember!(T, "get") &&
		is(typeof(__traits(getMember, aggregate, "isNull")()) == bool) &&
		!is(typeof(__traits(getMember, aggregate, "get")()) == void);
}

version (D_Exceptions) unittest {
	import std.typecons : Nullable;

	static assert(isStdNullable!(Nullable!string));
}

// Edited From https://github.com/AuburnSounds/Dplug/blob/master/core/dplug/core/nogc.d

// This module provides many utilities to deal with @nogc nothrow, in a situation with the runtime disabled.

//
// Fake @nogc
//

debug {
	auto assumeNoGC(T)(T t) if (isFunctionPointer!T || isDelegate!T) {
		enum attrs = functionAttributes!T | FunctionAttribute.nogc;
		return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs))t;
	}

	auto assumeNothrowNoGC(T)(T t) if (isFunctionPointer!T || isDelegate!T) {
		enum attrs = functionAttributes!T | FunctionAttribute.nogc | FunctionAttribute.nothrow_;
		return cast(SetFunctionAttributes!(T, functionLinkage!T, attrs))t;
	}

	unittest {
		void funcThatDoesGC() {
			int a = 4;
			int[] _ = [a, a];
		}

		void anotherFunction() nothrow @nogc {
			assumeNothrowNoGC(() { funcThatDoesGC(); })();
		}

		void aThirdFunction() @nogc {
			assumeNoGC(() { funcThatDoesGC(); })();
		}
	}
}
