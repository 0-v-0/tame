module tame.nogc;

import core.stdc.stdlib;
import core.stdc.string;
import std.exception : assumeUnique;
import std.traits;

// Edited From https://github.com/AuburnSounds/Dplug/blob/master/core/dplug/core/nogc.d

// This module provides many utilities to deal with @nogc nothrow, in a situation with the runtime disabled.

version (LDC) {
	pragma(LDC_no_moduleinfo);
}

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

nothrow @nogc:

/// Allocates a slice with `malloc`.
T[] mallocSlice(T)(size_t count) {
	T[] slice = mallocSliceNoInit!T(count);
	static if (is(T == struct)) {
		// we must avoid calling struct destructors with uninitialized memory
		for (size_t i = 0; i < count; ++i) {
			T uninitialized;
			memcpy(&slice[i], &uninitialized, T.sizeof);
		}
	} else
		slice[0 .. count] = T.init;
	return slice;
}

/// Allocates a slice with `malloc`, but does not initialize the content.
T[] mallocSliceNoInit(T)(size_t count) {
	T* p = cast(T*)malloc(count * T.sizeof);
	return p[0 .. count];
}

/// Frees a slice allocated with `mallocSlice`.
void freeSlice(T)(const(T)[] slice) {
	free(cast(void*)slice.ptr); // const cast here
}

/// Duplicates a slice with `malloc`. Equivalent to `.dup`
/// Has to be cleaned-up with `free(slice.ptr)` or `freeSlice(slice)`.
T[] mallocDup(T)(const(T)[] slice) if (!is(T == struct)) {
	T[] copy = mallocSliceNoInit!T(slice.length);
	memcpy(copy.ptr, slice.ptr, slice.length * T.sizeof);
	return copy;
}

/// Duplicates a slice with `malloc`. Equivalent to `.idup`
/// Has to be cleaned-up with `free(slice.ptr)` or `freeSlice(slice)`.
immutable(T)[] mallocIDup(T)(const(T)[] slice) if (!is(T == struct)) =>
	assumeUnique(mallocDup!T(slice));

/// Duplicates a zero-terminated string with `malloc`, return a `char[]`. Equivalent to `.dup`
/// Has to be cleaned-up with `free(s.ptr)`.
/// Note: The zero-terminating byte is preserved. This allow to have a string which also can be converted
/// to a C string with `.ptr`. However the zero byte is not included in slice length.
char[] stringDup(const(char)* cstr) {
	assert(cstr !is null);
	size_t len = strlen(cstr);
	char* copy = strdup(cstr);
	return copy[0 .. len];
}

char[] stringDup(string str) => stringDup(str.ptr);

/// Duplicates a zero-terminated string with `malloc`, return a `string`. Equivalent to `.idup`
/// Has to be cleaned-up with `free(s.ptr)`.
/// Note: The zero-terminating byte is preserved. This allow to have a string which also can be converted
/// to a C string with `.ptr`. However the zero byte is not included in slice length.
string stringIDup(const(char)* cstr) => assumeUnique(stringDup(cstr));
