/**
 * Compiler builtins and attributes, abstracted across GDC, LDC, and DMD.
 *
 * This module provides a uniform set of compiler hints and intrinsics regardless of
 * compiler type. When compiled with a compiler that does not support a
 * given feature, a no-op fallback is provided so that code compiles and runs
 * correctly (albeit without the optimisation hint).
 */
module tame.builtins;

public import core.builtins;

version (GNU) {
	/// Prevent the compiler from inlining the annotated function.
	enum noinline = attribute("noinline");
	/// Request that the compiler always inlines the annotated function.
	enum forceinline = attribute("forceinline");
	/// Require SSE 4.2 support for the annotated function.
	enum sse4_2 = attribute("target", "sse4.2");
	/// Mark a symbol as used, preventing the compiler from removing it.
	enum assumeUsed = attribute("used");
	/// Mark a function as cold (unlikely to be executed), guiding optimisation.
	enum cold = attribute("cold");
	/// Prevent the compiler from using PLT (Procedure Linkage Table) for the annotated symbol.
	enum noplt;
	/// Indicate that a pointer does not alias any other pointer (C99 $(D restrict) semantics).
	enum restrict;
} else version (LDC) {
	import ldc.attributes;
	import ldc.intrinsics;

	public import ldc.attributes : assumeUsed, cold, noplt, restrict;

	/// Prevent the compiler from inlining the annotated function.
	enum noinline = optStrategy("none");
	/// Request that the compiler always inlines the annotated function.
	enum forceinline = llvmAttr("always_inline", "true");
	/// Require SSE 4.2 support for the annotated function.
	enum sse4_2 = target("+sse4.2");
} else {
	/// Prevent the compiler from inlining the annotated function. No-op on DMD.
	enum noinline;
	/// Request that the compiler always inlines the annotated function. No-op on DMD.
	enum forceinline;
	/// Require SSE 4.2 support for the annotated function. No-op on DMD.
	enum sse4_2;
	/// Mark a symbol as used, preventing the compiler from removing it. No-op on DMD.
	enum assumeUsed;
	/// Mark a function as cold (unlikely to be executed). No-op on DMD.
	enum cold;
	/// Prevent the compiler from using PLT for the annotated symbol. No-op on DMD.
	enum noplt;
	/// Indicate that a pointer does not alias any other pointer. No-op on DMD.
	enum restrict;
}
