module tame.bitop;

import core.bitop : bsr;
import std.traits : Unqual;

pure nothrow @nogc:

/**
Count leading zeroes.

Params:
	u = the unsigned value to scan

Returns:
	The number of leading zero bits before the first one bit. If `u` is `0`,
	the result is undefined.
*/
version (LDC) {
	pragma(inline, true)
	U clz(U)(U u)
	if (is(Unqual!U : size_t)) {
		import ldc.intrinsics;

		return llvm_ctlz(u, false);
	}
} else version (GNU) {
	import gcc.builtins;

	alias clz = __builtin_clz;
	version (X86) {
		uint clz(ulong u) {
			const uint hi = u >> 32;
			return hi ? __builtin_clz(hi) : 32 + __builtin_clz(u);
		}
	} else
		alias clz = __builtin_clzl;
} else {
	pragma(inline, true)
	U clz(U)(U u)
	if (is(Unqual!U : size_t)) {
		enum U max = 8 * U.sizeof - 1;
		return max - bsr(u);
	}

	version (X86) {
		pragma(inline, true)
		uint clz(U)(U u)
		if (is(Unqual!U == ulong)) {
			uint hi = u >> 32;
			return hi ? 31 - bsr(hi) : 63 - bsr(cast(uint)u);
		}
	}
}

///
@safe unittest {
	assert(clz(0x01234567) == 7);
	assert(clz(0x0123456701234567UL) == 7);
	assert(clz(0x0000000001234567UL) == 7 + 32);
}

/++
Aligns a pointer to the closest multiple of `alignment`,
which is equal to or larger than `value`.
+/
T* alignTo(T)(return scope T* ptr, size_t alignment)
in (alignment.isPowerOf2)
	=> cast(T*)((cast(size_t)ptr + alignment - 1) & -alignment);

/// ditto
size_t alignTo(size_t alignment)(size_t n)
if (alignment.isPowerOf2)
	=> (n + alignment - 1) & -alignment;

unittest {
	assert(alignTo(cast(void*)65, 64) == cast(void*)128);
}

@safe:
/// Returns: whether the (positive) argument is an integral power of two.
bool isPowerOf2(size_t n)
	=> n > 0 && (n & n - 1) == 0;

///
unittest {
	assert(isPowerOf2(1));
	assert(isPowerOf2(2));
	assert(isPowerOf2(4));
	assert(isPowerOf2(8));
	assert(isPowerOf2(16));
	assert(!isPowerOf2(0));
	assert(!isPowerOf2(3));
}

/// Returns: the next power of two greater than or equal to `v`.
/// If `v` is zero, the result is zero.
size_t roundPow2(size_t v)
	=> v ? size_t(1) << bsr(v) : 0;

///
unittest {
	assert(roundPow2(0) == 0);
	assert(roundPow2(3) == 2);
	assert(roundPow2(4) == 4);
}

version (LDC) {
	import ldc.gccbuiltins_x86;

	alias moveMask = __builtin_ia32_pmovmskb128;
} else version (GNU) {
	import gcc.builtins;

	alias moveMask = __builtin_ia32_pmovmskb128;
}
