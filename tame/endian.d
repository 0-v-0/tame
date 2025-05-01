module tame.endian;

public import std.bitmanip : swapEndian;

pure:

void swapEndian(T)(ref T t) @safe
if (is(T == struct)) {
	foreach (ref f; t.tupleof) {
		alias F = typeof(f);
		static if (F.sizeof > 1) {
			static if (__traits(isIntegral, F)) {
				f = swapEndian(f);
			} else static if (is(F == struct)) {
				swapEndian(f);
			}
		}
	}
}

void swapEndian(T)(T[] arr) @safe {
	foreach (ref t; arr) {
		swapEndian(t);
	}
}

pragma(inline, true):

ubyte[] toBytes(T)(T[] t) @trusted
	=> cast(ubyte[])t;

ubyte[] toBytes(T)(ref T t) @trusted
	=> (cast(ubyte*)&t)[0 .. T.sizeof];

version (BigEndian) {
	alias toBE = toBytes;
	ubyte[] toLE(T)(ref T t) {
		swapEndian(t);
		return toBytes(t);
	}

	ref fromBE(T)(ref T t) => t;
	ref fromLE(T)(ref T t) {
		swapEndian(t);
		return t;
	}
} else {
	alias toLE = toBytes;
	ubyte[] toBE(T)(ref T t) {
		swapEndian(t);
		return toBytes(t);
	}

	ref fromLE(T)(ref T t) => t;
	ref fromBE(T)(ref T t) {
		swapEndian(t);
		return t;
	}
}
