module tame.hash.museair;

import core.bitop : bs = bswap;
import core.builtins : likely, unlikely;
import core.int128 : Cent, mul;
import std.compiler : version_minor;

/// MuseAir hash version
enum MUSEAIR_ALGORITHM_VERSION = "0.4-rc4";

pure nothrow @nogc:

private:

ulong UINT64_C(ulong n) => n;

auto u64x(size_t n) => n * 8;

enum ulong[7] MUSEAIR_CONSTANT = [
	UINT64_C(0x5ae31e589c56e17a), UINT64_C(0x96d7bb04e64f6da9),
	UINT64_C(0x7ab1006b26f9eb64),
	UINT64_C(0x21233394220b8457), UINT64_C(0x047cb9557c9f3b43),
	UINT64_C(0xd24f2590c0bcee28),
	UINT64_C(0x33ea8f71bb6016d8)
];

pragma(inline, true)
ulong museair_read_u64(bool bswap)(in ubyte* p) {
	static if (bswap)
		return bs(*cast(ulong*)p);
	else
		return *cast(ulong*)p;
}

pragma(inline, true)
ulong museair_read_u32(bool bswap)(in ubyte* p) {
	static if (bswap)
		return bs(*cast(uint*)p);
	else
		return *cast(uint*)p;
}

pragma(inline, true)
void museair_read_short(bool bswap)(in ubyte* bytes, size_t len, ref ulong i, ref ulong j) {
	if (len >= 4) {
		auto off = (len & 24) >> (len >> 3); // len >= 8 ? 4 : 0
		i = (museair_read_u32!bswap(bytes) << 32) | museair_read_u32!bswap(bytes + len - 4);
		j = (museair_read_u32!bswap(bytes + off) << 32) | museair_read_u32!bswap(
			bytes + len - 4 - off);
	} else if (len > 0) {
		// MSB <-> LSB
		// [0] [0] [0] for len == 1 (0b01)
		// [0] [1] [1] for len == 2 (0b10)
		// [0] [1] [2] for len == 3 (0b11)
		i = (cast(ulong)bytes[0] << 48) | (cast(ulong)bytes[len >> 1] << 24) | cast(
			ulong)bytes[len - 1];
		j = 0;
	} else {
		i = 0;
		j = 0;
	}
}

static if (version_minor < 112) {
	version (X86_64) {
		version (GNU) version = GNU_OR_LDC_X86_64;
		version (LDC) version = GNU_OR_LDC_X86_64;
	}

	/****************************
	* Multiply 64-bit operands u1 * u2 in 128-bit precision.
	* Params:
	*      u1 = operand 1
	*      u2 = operand 2
	* Returns:
	*      u1 * u2 in 128-bit precision
	*/
	pure
	Cent mul(ulong u1, ulong u2) {
		if (!__ctfe) {
			version (GNU_OR_LDC_X86_64) {
				Cent ret = void;
				asm pure @trusted nothrow @nogc {
					"mulq %3" : "=a"(ret.lo), "=d"(ret.hi) : "a"(u1), "r"(u2) : "cc";
				}
				return ret;
			} else version (D_InlineAsm_X86_64) {
				U lo = void;
				U hi = void;
				asm pure @trusted nothrow @nogc {
					mov RAX, u1;
					mul u2;
					mov lo, RAX;
					mov hi, RDX;
				}
				//dfmt off
				return Cent(lo : lo, hi : hi);
				//dfmt on
			}
		}

		return .mul(Cent(lo : u1), Cent(lo : u2));
	}
}

// 64x64->128 multiplication [rhi:rlo = a * b]
pragma(inline, true)
void mult64_128(ref ulong rlo, ref ulong rhi, ulong a, ulong b) {
	const c = mul(a, b);
	rlo = c.lo;
	rhi = c.hi;
}

pragma(inline, true)
void museair_hash_short(bool bswap, bool bfast, bool b128)(in ubyte* bytes,
	const size_t len,
	const ulong seed,
	ref ulong out_lo,
	ref ulong out_hi) {
	ulong lo0 = void, lo1 = void, lo2 = void;
	ulong hi0 = void, hi1 = void, hi2 = void;

	mult64_128(lo2, hi2, seed ^ MUSEAIR_CONSTANT[0], len ^ MUSEAIR_CONSTANT[1]);

	ulong i = void, j = void;
	museair_read_short!bswap(bytes, len <= 16 ? len : 16, i, j);
	i ^= len ^ lo2;
	j ^= seed ^ hi2;

	if (unlikely(len > u64x(2))) {
		ulong u = void, v = void;
		museair_read_short!bswap(bytes + u64x(2), len - u64x(2), u, v);
		mult64_128(lo0, hi0, MUSEAIR_CONSTANT[2], MUSEAIR_CONSTANT[3] ^ u);
		mult64_128(lo1, hi1, MUSEAIR_CONSTANT[4], MUSEAIR_CONSTANT[5] ^ v);
		i ^= lo0 ^ hi1;
		j ^= lo1 ^ hi0;
	}

	static if (b128) {
		mult64_128(lo0, hi0, i, j);
		mult64_128(lo1, hi1, i ^ MUSEAIR_CONSTANT[2], j ^ MUSEAIR_CONSTANT[3]);
		i = lo0 ^ hi1;
		j = lo1 ^ hi0;
		mult64_128(lo0, hi0, i, j);
		mult64_128(lo1, hi1, i ^ MUSEAIR_CONSTANT[4], j ^ MUSEAIR_CONSTANT[5]);
		out_lo = lo0 ^ hi1;
		out_hi = lo1 ^ hi0;
	} else {
		static if (!bfast) {
			mult64_128(lo0, hi0, i ^ MUSEAIR_CONSTANT[2], j ^ MUSEAIR_CONSTANT[3]);
			mult64_128(lo1, hi1, i ^ MUSEAIR_CONSTANT[4], j ^ MUSEAIR_CONSTANT[5]);
			i = lo0 ^ hi1;
			j = lo1 ^ hi0;
			mult64_128(lo2, hi2, i, j);
			out_lo = i ^ j ^ lo2 ^ hi2;
		} else {
			mult64_128(i, j, i ^ MUSEAIR_CONSTANT[2], j ^ MUSEAIR_CONSTANT[3]);
			mult64_128(i, j, i ^ MUSEAIR_CONSTANT[4], j ^ MUSEAIR_CONSTANT[5]);
			out_lo = i ^ j;
		}
	}
}

pragma(inline, false)
void museair_hash_loong(bool bswap, bool bfast, bool b128)(in ubyte* bytes,
	const size_t len,
	const ulong seed,
	ref ulong out_lo,
	ref ulong out_hi) {
	const(ubyte)* p = bytes;
	size_t q = len;

	ulong i = void, j = void, k = void;

	ulong lo0 = void, lo1 = void, lo2 = void, lo3 = void, lo4 = void, lo5 = MUSEAIR_CONSTANT[6];
	ulong hi0 = void, hi1 = void, hi2 = void, hi3 = void, hi4 = void, hi5 = void;

	ulong[6] state = [
		MUSEAIR_CONSTANT[0] + seed, MUSEAIR_CONSTANT[1] - seed,
		MUSEAIR_CONSTANT[2] ^ seed,
		MUSEAIR_CONSTANT[3] + seed, MUSEAIR_CONSTANT[4] - seed,
		MUSEAIR_CONSTANT[5] ^ seed
	];
	if (unlikely(q > u64x(12))) {
		do {
			static if (!bfast) {
				state[0] ^= museair_read_u64!bswap(p + u64x(0));
				state[1] ^= museair_read_u64!bswap(p + u64x(1));
				mult64_128(lo0, hi0, state[0], state[1]);
				state[0] += lo5 ^ hi0;

				state[1] ^= museair_read_u64!bswap(p + u64x(2));
				state[2] ^= museair_read_u64!bswap(p + u64x(3));
				mult64_128(lo1, hi1, state[1], state[2]);
				state[1] += lo0 ^ hi1;

				state[2] ^= museair_read_u64!bswap(p + u64x(4));
				state[3] ^= museair_read_u64!bswap(p + u64x(5));
				mult64_128(lo2, hi2, state[2], state[3]);
				state[2] += lo1 ^ hi2;

				state[3] ^= museair_read_u64!bswap(p + u64x(6));
				state[4] ^= museair_read_u64!bswap(p + u64x(7));
				mult64_128(lo3, hi3, state[3], state[4]);
				state[3] += lo2 ^ hi3;

				state[4] ^= museair_read_u64!bswap(p + u64x(8));
				state[5] ^= museair_read_u64!bswap(p + u64x(9));
				mult64_128(lo4, hi4, state[4], state[5]);
				state[4] += lo3 ^ hi4;

				state[5] ^= museair_read_u64!bswap(p + u64x(10));
				state[0] ^= museair_read_u64!bswap(p + u64x(11));
				mult64_128(lo5, hi5, state[5], state[0]);
				state[5] += lo4 ^ hi5;
			} else {
				state[0] ^= museair_read_u64!bswap(p + u64x(0));
				state[1] ^= museair_read_u64!bswap(p + u64x(1));
				mult64_128(lo0, hi0, state[0], state[1]);
				state[0] = lo5 ^ hi0;
				state[1] ^= museair_read_u64!bswap(p + u64x(2));
				state[2] ^= museair_read_u64!bswap(p + u64x(3));
				mult64_128(lo1, hi1, state[1], state[2]);
				state[1] = lo0 ^ hi1;
				state[2] ^= museair_read_u64!bswap(p + u64x(4));
				state[3] ^= museair_read_u64!bswap(p + u64x(5));
				mult64_128(lo2, hi2, state[2], state[3]);
				state[2] = lo1 ^ hi2;
				state[3] ^= museair_read_u64!bswap(p + u64x(6));
				state[4] ^= museair_read_u64!bswap(p + u64x(7));
				mult64_128(lo3, hi3, state[3], state[4]);
				state[3] = lo2 ^ hi3;
				state[4] ^= museair_read_u64!bswap(p + u64x(8));
				state[5] ^= museair_read_u64!bswap(p + u64x(9));
				mult64_128(lo4, hi4, state[4], state[5]);
				state[4] = lo3 ^ hi4;
				state[5] ^= museair_read_u64!bswap(p + u64x(10));
				state[0] ^= museair_read_u64!bswap(p + u64x(11));
				mult64_128(lo5, hi5, state[5], state[0]);
				state[5] = lo4 ^ hi5;
			}
			p += u64x(12);
			q -= u64x(12);
		}
		while (likely(q > u64x(12)));
		state[0] ^= lo5; // don't forget this!
	}

	//dfmt off
    lo0 = 0, lo1 = 0, lo2 = 0, lo3 = 0, lo4 = 0, lo5 = 0;
    hi0 = 0, hi1 = 0, hi2 = 0, hi3 = 0, hi4 = 0, hi5 = 0;
	//dfmt on
	if (likely(q > u64x(4))) {
		state[0] ^= museair_read_u64!bswap(p + u64x(0));
		state[1] ^= museair_read_u64!bswap(p + u64x(1));
		mult64_128(lo0, hi0, state[0], state[1]);
		if (likely(q > u64x(6))) {
			state[1] ^= museair_read_u64!bswap(p + u64x(2));
			state[2] ^= museair_read_u64!bswap(p + u64x(3));
			mult64_128(lo1, hi1, state[1], state[2]);
			if (likely(q > u64x(8))) {
				state[2] ^= museair_read_u64!bswap(p + u64x(4));
				state[3] ^= museair_read_u64!bswap(p + u64x(5));
				mult64_128(lo2, hi2, state[2], state[3]);
				if (likely(q > u64x(10))) {
					state[3] ^= museair_read_u64!bswap(p + u64x(6));
					state[4] ^= museair_read_u64!bswap(p + u64x(7));
					mult64_128(lo3, hi3, state[3], state[4]);
				}
			}
		}
	}

	state[4] ^= museair_read_u64!bswap(p + q - u64x(4));
	state[5] ^= museair_read_u64!bswap(p + q - u64x(3));
	mult64_128(lo4, hi4, state[4], state[5]);

	state[5] ^= museair_read_u64!bswap(p + q - u64x(2));
	state[0] ^= museair_read_u64!bswap(p + q - u64x(1));
	mult64_128(lo5, hi5, state[5], state[0]);

	i = state[0] - state[1];
	j = state[2] - state[3];
	k = state[4] - state[5];

	int rot = cast(int)(len & 63);
	i = (i << rot) | (i >> (64 - rot));
	j = (j >> rot) | (j << (64 - rot));
	k ^= len;

	i += lo3 ^ hi3 ^ lo4 ^ hi4;
	j += lo5 ^ hi5 ^ lo0 ^ hi0;
	k += lo1 ^ hi1 ^ lo2 ^ hi2;

	mult64_128(lo0, hi0, i, j);
	mult64_128(lo1, hi1, j, k);
	mult64_128(lo2, hi2, k, i);

	static if (b128) {
		out_lo = lo0 ^ lo1 ^ hi2;
		out_hi = hi0 ^ hi1 ^ lo2;
	} else {
		out_lo = (lo0 ^ hi2) + (lo1 ^ hi0) + (lo2 ^ hi1);
	}
}

public:

/++
	MuseAir hash function
	Params:
		bswap = whether to swap byte order (for big-endian input)
		bfast = whether to use BFast variant
		b128  = whether to produce 128-bit output (otherwise 64-bit)
		bytes = input data
		seed  = seed value (default: 0)
	Returns:
		hash value (8 bytes if b128 is false, 16 bytes if b128 is true)
+/
pragma(inline, true) ubyte[b128 ? 16 : 8] museAir(bool bswap, bool bfast, bool b128)(in void[] bytes,
	const ulong seed = 0) {
	ulong out_lo = void, out_hi = void;
	const len = bytes.length;

	if (likely(len <= u64x(4))) {
		museair_hash_short!(bswap, bfast, b128)(cast(const ubyte*)bytes.ptr, len, seed, out_lo, out_hi);
	} else {
		museair_hash_loong!(bswap, bfast, b128)(cast(const ubyte*)bytes.ptr, len, seed, out_lo, out_hi);
	}

	ubyte[b128 ? 16 : 8] out_ = void;
	static if (b128) {
		version (LittleEndian) {
			*cast(ulong*)out_.ptr = out_lo;
			*cast(ulong*)(out_.ptr + 8) = out_hi;
		} else {
			*cast(ulong*)out_.ptr = bs(out_lo);
			*cast(ulong*)(out_.ptr + 8) = bs(out_hi);
		}
	} else {
		version (LittleEndian) {
			*cast(ulong*)out_.ptr = out_lo;
		} else {
			*cast(ulong*)out_.ptr = bs(out_lo);
		}
	}
	return out_;
}

///
unittest {
	assert(museAir64("") == x"e8eb79d81ee50ba8");
	assert(museAir64bf("") == x"3472756087f8eebf");
	assert(museAir128("") == x"bb32484bd55e3bc21508f43f36942870");
	assert(museAir128bf("") == x"bb32484bd55e3bc21508f43f36942870");
	assert(museAir64("abc") == x"5fc7290c48d62574");
	assert(museAir64bf("abc") == x"99ffb5d365eb2585");
	assert(museAir128("abc") == x"d491a1d5c0abe795a5566e75543a0d7a");
	assert(museAir128bf("abc") == x"d491a1d5c0abe795a5566e75543a0d7a");
}

unittest {
	enum data = "The quick brown fox jumps over the lazy dog";
	assert(museAir64(data) == x"8f76f44fb62c91f8");
	assert(museAir64bf(data) == x"8f76f44fb62c91f8");
	assert(museAir128(data) == x"8fef530f7339edc93c6a47abd34b9fce");
	assert(museAir128bf(data) == x"8fef530f7339edc93c6a47abd34b9fce");
}

alias museAir64 = museAir!(false, false, false);
alias museAir64bf = museAir!(false, true, false);
alias museAir128 = museAir!(false, false, true);
alias museAir128bf = museAir!(false, true, true);
