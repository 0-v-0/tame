module tame.internal;

package:

version (X86_64) {
	enum isAMD64 = true;
	enum isX86 = false;
} else version (X86) {
	enum isAMD64 = false;
	enum isX86 = true;
} else {
	enum isX86 = false;
	enum isAMD64 = false;
}

version (LDC) {
	enum isLDC = true;
	enum isGDC = false;
	enum isDMD = false;
} else version (GNU) {
	enum isLDC = false;
	enum isGDC = true;
	enum isDMD = false;
} else version (DigitalMars) {
	enum isLDC = false;
	enum isGDC = false;
	enum isDMD = true;
}

version (DigitalMars) {
	enum noinline;
	enum forceinline;
	enum sse4;
} else version (GNU) {
	import gcc.attribute;

	enum noinline = gcc.attribute.attribute("noinline");
	enum forceinline = gcc.attribute.attribute("forceinline");
	enum sse4_2 = gcc.attribute.attribute("target", "sse4.2");
} else version (LDC) {
	import ldc.attributes;

	enum noinline = ldc.attributes.optStrategy("none");
	enum forceinline = ldc.attributes.llvmAttr("always_inline", "true");
	enum sse4_2 = ldc.attributes.target("+sse4.2");
}
import std.traits : Unqual;

pure nothrow @nogc:

/*******************************************************************************
 *
 * Count leading zeroes.
 *
 * Params:
 *   u = the unsigned value to scan
 *
 * Returns:
 *   The number of leading zero bits before the first one bit. If `u` is `0`,
 *   the result is undefined.
 *
 **************************************/
version (DigitalMars) {
	import core.bitop : bsr, bsf;

	pragma(inline, true)
	U clz(U)(U u) if (is(Unqual!U : size_t)) {
		enum U max = 8 * U.sizeof - 1;
		return max - bsr(u);
	}

	static if (isX86) {
		pragma(inline, true)
		uint clz(U)(U u) if (is(Unqual!U == ulong)) {
			uint hi = u >> 32;
			return hi ? 31 - bsr(hi) : 63 - bsr(cast(uint)u);
		}
	}
} else version (GNU) {
	import gcc.builtins;

	alias clz = __builtin_clz;
	static if (isX86) {
		uint clz(ulong u) {
			uint hi = u >> 32;
			return hi ? __builtin_clz(hi) : 32 + __builtin_clz(cast(uint)u);
		}
	} else
		alias clz = __builtin_clzl;
} else version (LDC) {
	pragma(inline, true)
	U clz(U)(U u) if (is(Unqual!U : size_t)) {
		import ldc.intrinsics;

		return llvm_ctlz(u, false);
	}

	static if (size_t.sizeof == 4) {
		pragma(inline, true)
		uint clz(U)(U u) if (is(Unqual!U == ulong)) {
			import ldc.intrinsics;

			return cast(uint)llvm_ctlz(u, false);
		}
	}
}

@safe unittest {
	assert(clz(0x01234567) == 7);
	assert(clz(0x0123456701234567UL) == 7);
	assert(clz(0x0000000001234567UL) == 7 + 32);
}

/**
 * Aligns a pointer to the closest multiple of $(D pot) (a power of two),
 * which is equal to or larger than $(D value).
 */
T* alignPtrNext(T)(scope T* ptr, size_t pot)
in (pot > 0 && pot.isPowerOf2) => cast(T*)((cast(size_t)ptr + (pot - 1)) & -pot);

unittest {
	assert(alignPtrNext(cast(void*)65, 64) == cast(void*)128);
}

@safe {
	/// Returns whether the (positive) argument is an integral power of two.
	@property bool isPowerOf2(size_t n)
	in (n > 0) => (n & n - 1) == 0;

	version (LDC) {
		import core.simd;

		pragma(LDC_intrinsic, "llvm.x86.sse2.pmovmskb.128")
		uint moveMask(ubyte16);
	} else version (GNU) {
		import gcc.builtins;

		alias moveMask = __builtin_ia32_pmovmskb128;
	}

	template SIMDFromScalar(V, alias scalar) {
		// This wrapper is needed for optimal performance with LDC and
		// doesn't hurt GDC's inlining.
		V SIMDFromScalar() {
			enum V asVectorEnum = scalar;
			return asVectorEnum;
		}
	}
}
