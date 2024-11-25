module tame.builtins;

version (GNU)
{
	enum noinline = attribute("noinline");
	enum forceinline = attribute("forceinline");
	enum sse4_2 = attribute("target", "sse4.2");

	/// https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html#index-_005f_005fbuiltin_005fexpect
	alias expect = __builtin_expect;
	/// https://gcc.gnu.org/onlinedocs/gcc/Other-Builtins.html#index-_005f_005fbuiltin_005ftrap
	alias trap = __builtin_trap;
}
else version (LDC)
{
	import ldc.attributes;
	import ldc.intrinsics;

	enum noinline = optStrategy("none");
	enum forceinline = llvmAttr("always_inline", "true");
	enum sse4_2 = target("+sse4.2");

	/// https://llvm.org/docs/LangRef.html#llvm-expect-intrinsic
	alias expect = llvm_expect;
	debug
		/// https://llvm.org/docs/LangRef.html#llvm-debugtrap-intrinsic
		alias trap = llvm_debugtrap;
	else
		/// https://llvm.org/docs/LangRef.html#llvm-trap-intrinsic
		alias trap = llvm_trap;
}
else
{
	enum noinline;
	enum forceinline;
	enum sse4_2;

	pragma(inline, true)
	T expect(T)(T val, T expected) if (__traits(isIntegral, T))
	{
		return val;
	}

	pragma(inline, true)
	void trap()
	{
		debug
		{
			version(D_InlineAsm_X86)
				asm nothrow @nogc pure @trusted { int 3; }
		}
		assert(0);
	}
}

/// Provide static branch hints
pragma(inline, true) bool likely(bool b) => expect(b, true);
///
pragma(inline, true) bool unlikely(bool b) => expect(b, false);
