module tame.unsafe.ptrop;

pure nothrow @nogc:

/++
Template for creating a compact pointer type.
This is useful for storing a pointer within a field of a struct, without
increasing the size of the struct. This is done by storing the pointer in
the lower bits of a size_t field.

Params:
TF = the type of the field
field = the field name
T = the type of the pointer
+/
template CompactPtr(TF, string field, T = void*) if (TF.sizeof <= 2) {
	version (X86_64) {
		version (LittleEndian) {
			private enum PtrMask = 0xFF_FF_FF_FF_FF_FF;
		}
	}

	static if (is(typeof(PtrMask))) {
		union {
			struct {
				byte[6] pad;
				mixin("TF ", field, ";");
			}

			size_t p;
		}

		@property pure nothrow @nogc @system {
			T ptr()
				=> cast(T)(p & PtrMask);

			void ptr(T val) {
				p &= ~PtrMask;
				p |= PtrMask & cast(size_t)val;
			}
		}
	} else {
		T ptr;
		mixin("TF ", field);
	}
}

unittest {
	struct S {
		mixin CompactPtr!(ushort, "flag");
	}

	S s;
	assert(s.ptr is null);
	s.ptr = &s;
	s.flag = 42;
	assert(s.ptr is &s);
	assert(s.flag == 42);
	static assert(!__traits(compiles, {
		struct A {
			mixin CompactPtr!(uint, "flag");
		}
	}));
}

// LSB helper

/// Returns true if the least significant bit of the pointer is set.
bool hasLSB(in void* p) => (cast(size_t)p & 1) != 0;

bool hasLSB(in shared void* p) => hasLSB(cast(void*)p);

/// Sets the least significant bit of the pointer.
T* setLSB(T)(T* p) => cast(T*)(cast(size_t)p | 1);

/// Clears the least significant bit of the pointer.
T* clearLSB(T)(T* p) => cast(T*)(cast(size_t)p & ~1);
