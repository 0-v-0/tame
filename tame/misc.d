module tame.misc;

import std.ascii,
std.meta,
std.traits;

package:

int numDigits(T : ulong)(T num) @trusted {
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
	for (; n; digits++)
		n /= 10;
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

/**
 * Match types like `std.typecons.Nullable` ie `mir.core.Nullable`
 */
template isStdNullable(T) {
	T* aggregate;

	enum bool isStdNullable =
		hasMember!(T, "isNull") &&
		hasMember!(T, "get") &&
		hasMember!(T, "nullify") &&
		is(typeof(__traits(getMember, aggregate, "isNull")()) == bool) &&
		!is(typeof(__traits(getMember, aggregate, "get")()) == void) &&
		is(typeof(__traits(getMember, aggregate, "nullify")()) == void);
}

version (D_Exceptions) unittest {
	import std.typecons : Nullable;

	static assert(isStdNullable!(Nullable!string));
}
