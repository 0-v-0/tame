module tame.hash.xxh3;

version (Have128BitInteger) import core.int128;

import core.bitop : rol, bswap;

version (X86)
	version = HaveUnalignedLoads;
else version (X86_64)
	version = HaveUnalignedLoads;

alias XXH32_hash_t = uint;
alias XXH64_hash_t = ulong;
/** Storage for 128bit hash digest */
align(16) struct XXH128_hash_t {
	XXH64_hash_t low64; /** `value & 0xFFFFFFFFFFFFFFFF` */
	XXH64_hash_t high64; /** `value >> 64` */
}

@safe pure nothrow @nogc:

private:
enum XXH_PRIME32_1 = 0x9E3779B1U; /** 0b10011110001101110111100110110001 */
enum XXH_PRIME32_2 = 0x85EBCA77U; /** 0b10000101111010111100101001110111 */
enum XXH_PRIME32_3 = 0xC2B2AE3DU; /** 0b11000010101100101010111000111101 */
enum XXH_PRIME32_4 = 0x27D4EB2FU; /** 0b00100111110101001110101100101111 */
enum XXH_PRIME32_5 = 0x165667B1U; /** 0b00010110010101100110011110110001 */

ulong xxh_read64(const void* ptr)
@trusted {
	ulong val;
	version (HaveUnalignedLoads)
		val = *(cast(ulong*)ptr);
	else
		(cast(ubyte*)&val)[0 .. ulong.sizeof] = (cast(ubyte*)ptr)[0 .. ulong.sizeof];
	return val;
}

ulong xxh_readLE64(const void* ptr) {
	version (LittleEndian)
		return xxh_read64(ptr);
	else
		return bswap(xxh_read64(ptr));
}

enum XXH_PRIME64_1 = 0x9E3779B185EBCA87; /** 0b1001111000110111011110011011000110000101111010111100101010000111 */
enum XXH_PRIME64_2 = 0xC2B2AE3D27D4EB4F; /** 0b1100001010110010101011100011110100100111110101001110101101001111 */
enum XXH_PRIME64_3 = 0x165667B19E3779F9; /** 0b0001011001010110011001111011000110011110001101110111100111111001 */
enum XXH_PRIME64_4 = 0x85EBCA77C2B2AE63; /** 0b1000010111101011110010100111011111000010101100101010111001100011 */
enum XXH_PRIME64_5 = 0x27D4EB2F165667C5; /** 0b0010011111010100111010110010111100010110010101100110011111000101 */

ulong xxh64_avalanche(ulong hash) {
	hash ^= hash >> 33;
	hash *= XXH_PRIME64_2;
	hash ^= hash >> 29;
	hash *= XXH_PRIME64_3;
	hash ^= hash >> 32;
	return hash;
}

/* *********************************************************************
*  XXH3
*  New generation hash designed for speed on small keys and vectorization
************************************************************************ */

enum XXH3_SECRET_SIZE_MIN = 136; /// The bare minimum size for a custom secret.
enum XXH3_SECRET_DEFAULT_SIZE = 192; /* minimum XXH3_SECRET_SIZE_MIN */
enum XXH_SECRET_DEFAULT_SIZE = 192; /* minimum XXH3_SECRET_SIZE_MIN */
enum XXH3_INTERNALBUFFER_SIZE = 256; ///The size of the internal XXH3 buffer.

/* Structure for XXH3 streaming API.
 *
 * Note: ** This structure has a strict alignment requirement of 64 bytes!! **
 * Do not allocate this with `malloc()` or `new`, it will not be sufficiently aligned.
 *
 * Do never access the members of this struct directly.
 *
 * See: XXH3_INITSTATE() for stack initialization.
 * See: XXH32_state_s, XXH64_state_s
 */
align(64) struct XXH3_state_t {
	align(64) XXH64_hash_t[8] acc;
	/** The 8 accumulators. See XXH32_state_s::v and XXH64_state_s::v */
	align(64) ubyte[XXH3_SECRET_DEFAULT_SIZE] customSecret;
	/** Used to store a custom secret generated from a seed. */
	align(64) ubyte[XXH3_INTERNALBUFFER_SIZE] buffer;
	/** The internal buffer. See: XXH32_state_s::mem32 */
	XXH32_hash_t bufferedSize;
	/** The amount of memory in buffer, See: XXH32_state_s::memsize */
	XXH32_hash_t useSeed;
	/** Reserved field. Needed for padding on 64-bit. */
	size_t nbStripesSoFar;
	/** Number or stripes processed. */
	XXH64_hash_t totalLen;
	/** Total length hashed. 64-bit even on 32-bit targets. */
	size_t nbStripesPerBlock;
	/** Number of stripes per block. */
	size_t secretLimit;
	/** Size of customSecret or extSecret */
	XXH64_hash_t seed;
	/** Seed for _withSeed variants. Must be zero otherwise, See: XXH3_INITSTATE() */
	XXH64_hash_t reserved64;
	/** Reserved field. */
	const(ubyte)* extSecret;
	/** Reference to an external secret for the _withSecret variants, null
     *   for other variants. */
	/* note: there may be some padding at the end due to alignment on 64 bytes */
} /* typedef'd to XXH3_state_t */

static assert(XXH_SECRET_DEFAULT_SIZE >= XXH3_SECRET_SIZE_MIN, "default keyset is not large enough");

/** Pseudorandom secret taken directly from FARSH. */
align(64) immutable ubyte[XXH3_SECRET_DEFAULT_SIZE] xxh3_kSecret = [
	0xb8, 0xfe, 0x6c, 0x39, 0x23, 0xa4, 0x4b, 0xbe, 0x7c, 0x01, 0x81, 0x2c,
	0xf7, 0x21, 0xad, 0x1c, 0xde, 0xd4, 0x6d, 0xe9, 0x83, 0x90, 0x97, 0xdb,
	0x72, 0x40, 0xa4, 0xa4, 0xb7, 0xb3, 0x67, 0x1f, 0xcb, 0x79, 0xe6, 0x4e,
	0xcc, 0xc0, 0xe5, 0x78, 0x82, 0x5a, 0xd0, 0x7d, 0xcc, 0xff, 0x72, 0x21,
	0xb8, 0x08, 0x46, 0x74, 0xf7, 0x43, 0x24, 0x8e, 0xe0, 0x35, 0x90, 0xe6,
	0x81, 0x3a, 0x26, 0x4c, 0x3c, 0x28, 0x52, 0xbb, 0x91, 0xc3, 0x00, 0xcb,
	0x88, 0xd0, 0x65, 0x8b, 0x1b, 0x53, 0x2e, 0xa3, 0x71, 0x64, 0x48, 0x97,
	0xa2, 0x0d, 0xf9, 0x4e, 0x38, 0x19, 0xef, 0x46, 0xa9, 0xde, 0xac, 0xd8,
	0xa8, 0xfa, 0x76, 0x3f, 0xe3, 0x9c, 0x34, 0x3f, 0xf9, 0xdc, 0xbb, 0xc7,
	0xc7, 0x0b, 0x4f, 0x1d, 0x8a, 0x51, 0xe0, 0x4b, 0xcd, 0xb4, 0x59, 0x31,
	0xc8, 0x9f, 0x7e, 0xc9, 0xd9, 0x78, 0x73, 0x64, 0xea, 0xc5, 0xac, 0x83,
	0x34, 0xd3, 0xeb, 0xc3, 0xc5, 0x81, 0xa0, 0xff, 0xfa, 0x13, 0x63, 0xeb,
	0x17, 0x0d, 0xdd, 0x51, 0xb7, 0xf0, 0xda, 0x49, 0xd3, 0x16, 0x55, 0x26,
	0x29, 0xd4, 0x68, 0x9e, 0x2b, 0x16, 0xbe, 0x58, 0x7d, 0x47, 0xa1, 0xfc,
	0x8f, 0xf8, 0xb8, 0xd1, 0x7a, 0xd0, 0x31, 0xce, 0x45, 0xcb, 0x3a, 0x8f,
	0x95, 0x16, 0x04, 0x28, 0xaf, 0xd7, 0xfb, 0xca, 0xbb, 0x4b, 0x40, 0x7e,
];

uint xxh_read32(const void* ptr) @trusted {
	uint val;
	version (HaveUnalignedLoads)
		val = *(cast(uint*)ptr);
	else
		(cast(ubyte*)&val)[0 .. uint.sizeof] = (cast(ubyte*)ptr)[0 .. uint.sizeof];
	return val;
}

uint xxh_readLE32(const void* ptr) {
	version (LittleEndian)
		return xxh_read32(ptr);
	else
		return bswap(xxh_read32(ptr));
}

/* This performs a 32x32 -> 64 bit multiplikation */
ulong xxh_mult32to64(uint x, uint y) => ulong(x) * y;

/** Calculates a 64 to 128-bit long multiply.
 *
 * Param: lhs , rhs The 64-bit integers to be multiplied
 * Return: The 128-bit result represented in an XXH128_hash_t structure.
 */
XXH128_hash_t xxh_mult64to128(ulong lhs, ulong rhs) {
	version (Have128BitInteger) {
		Cent cent_lhs;
		cent_lhs.lo = lhs;
		Cent cent_rhs;
		cent_rhs.lo = rhs;
		const Cent product = mul(cent_lhs, cent_rhs);
		XXH128_hash_t r128;
		r128.low64 = product.lo;
		r128.high64 = product.hi;
	} else {
		/* First calculate all of the cross products. */
		const ulong lo_lo = xxh_mult32to64(lhs & 0xFFFFFFFF, rhs & 0xFFFFFFFF);
		const ulong hi_lo = xxh_mult32to64(lhs >> 32, rhs & 0xFFFFFFFF);
		const ulong lo_hi = xxh_mult32to64(lhs & 0xFFFFFFFF, rhs >> 32);
		const ulong hi_hi = xxh_mult32to64(lhs >> 32, rhs >> 32);

		/* Now add the products together. These will never overflow. */
		const ulong cross = (lo_lo >> 32) + (hi_lo & 0xFFFFFFFF) + lo_hi;
		const ulong upper = (hi_lo >> 32) + (cross >> 32) + hi_hi;
		const ulong lower = (cross << 32) | (lo_lo & 0xFFFFFFFF);

		XXH128_hash_t r128 = {lower, upper};
	}
	return r128;
}

/** Calculates a 64-bit to 128-bit multiply, then XOR folds it.
 *
 * The reason for the separate function is to prevent passing too many structs
 * around by value. This will hopefully inline the multiply, but we don't force it.
 *
 * Param: lhs , rhs The 64-bit integers to multiply
 * Return: The low 64 bits of the product XOR'd by the high 64 bits.
 * See: xxh_mult64to128()
 */
ulong xxh3_mul128_fold64(ulong lhs, ulong rhs) {
	XXH128_hash_t product = xxh_mult64to128(lhs, rhs);
	return product.low64 ^ product.high64;
}

/* Seems to produce slightly better code on GCC for some reason. */
ulong xxh_xorshift64(ulong v64, int shift)
in (0 <= shift && shift < 64, "shift out of range") => v64 ^ (v64 >> shift);

/*
 * This is a fast avalanche stage,
 * suitable when input bits are already partially mixed
 */
XXH64_hash_t xxh3_avalanche(ulong h64) {
	h64 = xxh_xorshift64(h64, 37);
	h64 *= 0x165667919E3779F9;
	h64 = xxh_xorshift64(h64, 32);
	return h64;
}

/*
 * This is a stronger avalanche,
 * inspired by Pelle Evensen's rrmxmx
 * preferable when input has not been previously mixed
 */
XXH64_hash_t xxh3_rrmxmx(ulong h64, ulong len) {
	/* this mix is inspired by Pelle Evensen's rrmxmx */
	h64 ^= rol(h64, 49) ^ rol(h64, 24);
	h64 *= 0x9FB21C651E98DF25;
	h64 ^= (h64 >> 35) + len;
	h64 *= 0x9FB21C651E98DF25;
	return xxh_xorshift64(h64, 28);
}

/* ==========================================
 * Short keys
 * ==========================================
 * One of the shortcomings of XXH32 and XXH64 was that their performance was
 * sub-optimal on short lengths. It used an iterative algorithm which strongly
 * favored lengths that were a multiple of 4 or 8.
 *
 * Instead of iterating over individual inputs, we use a set of single shot
 * functions which piece together a range of lengths and operate in constant time.
 *
 * Additionally, the number of multiplies has been significantly reduced. This
 * reduces latency, especially when emulating 64-bit multiplies on 32-bit.
 *
 * Depending on the platform, this may or may not be faster than XXH32, but it
 * is almost guaranteed to be faster than XXH64.
 */

/*
 * At very short lengths, there isn't enough input to fully hide secrets, or use
 * the entire secret.
 *
 * There is also only a limited amount of mixing we can do before significantly
 * impacting performance.
 *
 * Therefore, we use different sections of the secret and always mix two secret
 * samples with an XOR. This should have no effect on performance on the
 * seedless or withSeed variants because everything _should_ be constant folded
 * by modern compilers.
 *
 * The XOR mixing hides individual parts of the secret and increases entropy.
 *
 * This adds an extra layer of strength for custom secrets.
 */
XXH64_hash_t xxh3_len_1to3_64b(
	const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
@trusted pure nothrow @nogc
in (input != null, "input == null")
in (1 <= len && len <= 3, "len out of range")
in (secret != null, "secret == null") {
	/*
     * len = 1: combined = { input[0], 0x01, input[0], input[0] }
     * len = 2: combined = { input[1], 0x02, input[0], input[1] }
     * len = 3: combined = { input[2], 0x03, input[0], input[1] }
     */
	{
		const ubyte c1 = input[0];
		const ubyte c2 = input[len >> 1];
		const ubyte c3 = input[len - 1];
		const uint combined = (cast(uint)c1 << 16) | (
			cast(uint)c2 << 24) | (
			cast(uint)c3 << 0) | (cast(uint)len << 8);
		const ulong bitflip = (xxh_readLE32(secret) ^ xxh_readLE32(secret + 4)) + seed;
		const ulong keyed = cast(ulong)combined ^ bitflip;
		return xxh64_avalanche(keyed);
	}
}

XXH64_hash_t xxh3_len_4to8_64b(
	const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
@trusted
in (input != null, "input == null")
in (secret != null, "secret == null")
in (4 <= len && len <= 8, "len out of range") {
	seed ^= cast(ulong)bswap(cast(uint)seed) << 32;
	{
		const uint input1 = xxh_readLE32(input);
		const uint input2 = xxh_readLE32(input + len - 4);
		const ulong bitflip = (xxh_readLE64(secret + 8) ^ xxh_readLE64(secret + 16)) - seed;
		const ulong input64 = input2 + ((cast(ulong)input1) << 32);
		const ulong keyed = input64 ^ bitflip;
		return xxh3_rrmxmx(keyed, len);
	}
}

XXH64_hash_t xxh3_len_9to16_64b(
	const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
@trusted
in (input != null, "input == null")
in (secret != null, "secret == null")
in (9 <= len && len <= 16, "len out of range") {
	{
		const ulong bitflip1 = (xxh_readLE64(secret + 24) ^ xxh_readLE64(secret + 32)) + seed;
		const ulong bitflip2 = (xxh_readLE64(secret + 40) ^ xxh_readLE64(secret + 48)) - seed;
		const ulong input_lo = xxh_readLE64(input) ^ bitflip1;
		const ulong input_hi = xxh_readLE64(input + len - 8) ^ bitflip2;
		const ulong acc = len + bswap(input_lo) + input_hi + xxh3_mul128_fold64(input_lo,
			input_hi);
		return xxh3_avalanche(acc);
	}
}

bool xxh_likely(bool exp) {
	version (LDC) {
		import ldc.intrinsics;

		return llvm_expect(exp, true);
	} else
		return exp;
}

bool xxh_unlikely(bool exp) {
	version (LDC) {
		import ldc.intrinsics;

		return llvm_expect(exp, false);
	} else
		return exp;
}

XXH64_hash_t xxh3_len_0to16_64b(
	const ubyte* input, size_t len, const ubyte* secret, XXH64_hash_t seed)
@trusted
in (len <= 16, "len > 16") {
	{
		if (xxh_likely(len > 8))
			return xxh3_len_9to16_64b(input, len, secret, seed);
		if (xxh_likely(len >= 4))
			return xxh3_len_4to8_64b(input, len, secret, seed);
		if (len)
			return xxh3_len_1to3_64b(input, len, secret, seed);
		return xxh64_avalanche(seed ^ (xxh_readLE64(secret + 56) ^ xxh_readLE64(secret + 64)));
	}
}

/*
 * DISCLAIMER: There are known *seed-dependent* multicollisions here due to
 * multiplication by zero, affecting hashes of lengths 17 to 240.
 *
 * However, they are very unlikely.
 *
 * Keep this in mind when using the unseeded xxh3_64bits() variant: As with all
 * unseeded non-cryptographic hashes, it does not attempt to defend itself
 * against specially crafted inputs, only random inputs.
 *
 * Compared to classic UMAC where a 1 in 2^31 chance of 4 consecutive bytes
 * cancelling out the secret is taken an arbitrary number of times (addressed
 * in xxh3_accumulate_512), this collision is very unlikely with random inputs
 * and/or proper seeding:
 *
 * This only has a 1 in 2^63 chance of 8 consecutive bytes cancelling out, in a
 * function that is only called up to 16 times per hash with up to 240 bytes of
 * input.
 *
 * This is not too bad for a non-cryptographic hash function, especially with
 * only 64 bit outputs.
 *
 * The 128-bit variant (which trades some speed for strength) is NOT affected
 * by this, although it is always a good idea to use a proper seed if you care
 * about strength.
 */
ulong xxh3_mix16B(const(ubyte)* input, const(ubyte)* secret, ulong seed64)
@trusted {
	{
		const ulong input_lo = xxh_readLE64(input);
		const ulong input_hi = xxh_readLE64(input + 8);
		return xxh3_mul128_fold64(
			input_lo ^ (xxh_readLE64(secret) + seed64),
			input_hi ^ (xxh_readLE64(secret + 8) - seed64));
	}
}

/* For mid range keys, XXH3 uses a Mum-hash variant. */
XXH64_hash_t xxh3_len_17to128_64b(
	const(ubyte)* input, size_t len, const(ubyte)* secret, size_t secretSize, XXH64_hash_t seed)
@trusted
in (secretSize >= XXH3_SECRET_SIZE_MIN, "secretSize < XXH3_SECRET_SIZE_MIN")
in (16 < len && len <= 128, "len out of range") {
	ulong acc = len * XXH_PRIME64_1;
	if (len > 32) {
		if (len > 64) {
			if (len > 96) {
				acc += xxh3_mix16B(input + 48, secret + 96, seed);
				acc += xxh3_mix16B(input + len - 64, secret + 112, seed);
			}
			acc += xxh3_mix16B(input + 32, secret + 64, seed);
			acc += xxh3_mix16B(input + len - 48, secret + 80, seed);
		}
		acc += xxh3_mix16B(input + 16, secret + 32, seed);
		acc += xxh3_mix16B(input + len - 32, secret + 48, seed);
	}
	acc += xxh3_mix16B(input + 0, secret + 0, seed);
	acc += xxh3_mix16B(input + len - 16, secret + 16, seed);

	return xxh3_avalanche(acc);
}

enum XXH3_MIDSIZE_MAX = 240;
enum XXH3_MIDSIZE_STARTOFFSET = 3;
enum XXH3_MIDSIZE_LASTOFFSET = 17;

XXH64_hash_t xxh3_len_129to240_64b(
	const(ubyte)* input, size_t len, const(ubyte)* secret, size_t secretSize, XXH64_hash_t seed)
@trusted
in (secretSize >= XXH3_SECRET_SIZE_MIN, "secretSize < XXH3_SECRET_SIZE_MIN")
in (cast(int)len / 16 >= 8, "nbRounds < 8")
in (128 < len && len <= XXH3_MIDSIZE_MAX, "128 >= len || len > XXH3_MIDSIZE_MAX") {
	ulong acc = len * XXH_PRIME64_1;
	const int nbRounds = cast(int)len / 16;
	int i;
	for (i = 0; i < 8; i++) {
		acc += xxh3_mix16B(input + (16 * i), secret + (16 * i), seed);
	}
	acc = xxh3_avalanche(acc);
	for (i = 8; i < nbRounds; i++) {
		acc += xxh3_mix16B(input + (16 * i),
			secret + (16 * (i - 8)) + XXH3_MIDSIZE_STARTOFFSET, seed);
	}
	/* last bytes */
	acc += xxh3_mix16B(input + len - 16,
		secret + XXH3_SECRET_SIZE_MIN - XXH3_MIDSIZE_LASTOFFSET, seed);
	return xxh3_avalanche(acc);
}

/* =======     Long Keys     ======= */

enum XXH_STRIPE_LEN = 64;
enum XXH_SECRET_CONSUME_RATE = 8; /* nb of secret bytes consumed at each accumulation */
enum XXH_ACC_NB = XXH_STRIPE_LEN / ulong.sizeof;

void xxh_writeLE64(void* dst, ulong v64) @trusted {
	version (BigEndian)
		v64 = bswap(v64);
	(cast(ubyte*)dst)[0 .. v64.sizeof] = (cast(ubyte*)&v64)[0 .. v64.sizeof];
}

/* scalar variants - universal */

enum XXH_ACC_ALIGN = 8;

/* Scalar round for xxh3_accumulate_512_scalar(). */
void xxh3_scalarRound(void* acc, const(void)* input, const(void)* secret, size_t lane)
@trusted
in (lane < XXH_ACC_NB, "lane >= XXH_ACC_NB") {
	version (CheckACCAlignment)
		assert((cast(size_t)acc & (XXH_ACC_ALIGN - 1)) == 0, "(cast(size_t) acc & (XXH_ACC_ALIGN - 1)) != 0");
	ulong* xacc = cast(ulong*)acc;
	ubyte* xinput = cast(ubyte*)input;
	ubyte* xsecret = cast(ubyte*)secret;
	{
		const ulong data_val = xxh_readLE64(xinput + lane * 8);
		const ulong data_key = data_val ^ xxh_readLE64(xsecret + lane * 8);
		xacc[lane ^ 1] += data_val; /* swap adjacent lanes */
		xacc[lane] += xxh_mult32to64(data_key & 0xFFFFFFFF, data_key >> 32);
	}
}

/* Processes a 64 byte block of data using the scalar path. */
void xxh3_accumulate_512_scalar(void* acc, const(void)* input, const(void)* secret) {
	for (size_t i; i < XXH_ACC_NB; i++) {
		xxh3_scalarRound(acc, input, secret, i);
	}
}

/* Scalar scramble step for xxh3_scrambleAcc_scalar().
 *
 * This is extracted to its own function because the NEON path uses a combination
 * of NEON and scalar.
 */
void xxh3_scalarScrambleRound(void* acc, const(void)* secret, size_t lane)
@trusted
in (lane < XXH_ACC_NB, "lane >= XXH_ACC_NB") {
	version (CheckACCAlignment)
		assert(((cast(size_t)acc) & (XXH_ACC_ALIGN - 1)) == 0, "((cast(size_t) acc) & (XXH_ACC_ALIGN - 1)) != 0");
	ulong* xacc = cast(ulong*)acc; /* presumed aligned */
	const ubyte* xsecret = cast(const ubyte*)secret; /* no alignment restriction */{
		const ulong key64 = xxh_readLE64(xsecret + lane * 8);
		ulong acc64 = xacc[lane];
		acc64 = xxh_xorshift64(acc64, 47);
		acc64 ^= key64;
		acc64 *= XXH_PRIME32_1;
		xacc[lane] = acc64;
	}
}

/* Scrambles the accumulators after a large chunk has been read */
void xxh3_scrambleAcc_scalar(void* acc, const(void)* secret) {
	size_t i;
	for (i = 0; i < XXH_ACC_NB; i++) {
		xxh3_scalarScrambleRound(acc, secret, i);
	}
}

void xxh3_initCustomSecret_scalar(void* customSecret, ulong seed64)
@trusted {
	/*
     * We need a separate pointer for the hack below,
     * which requires a non-const pointer.
     * Any decent compiler will optimize this out otherwise.
     */
	const ubyte* kSecretPtr = cast(ubyte*)xxh3_kSecret;
	static assert((XXH_SECRET_DEFAULT_SIZE & 15) == 0, "(XXH_SECRET_DEFAULT_SIZE & 15) != 0");

	/*
     * Note: in debug mode, this overrides the asm optimization
     * and Clang will emit MOVK chains again.
     */
	//assert(kSecretPtr == xxh3_kSecret);

	{
		const int nbRounds = XXH_SECRET_DEFAULT_SIZE / 16;
		int i;
		for (i = 0; i < nbRounds; i++) {
			/*
             * The asm hack causes Clang to assume that kSecretPtr aliases with
             * customSecret, and on aarch64, this prevented LDP from merging two
             * loads together for free. Putting the loads together before the stores
             * properly generates LDP.
             */
			const ulong lo = xxh_readLE64(kSecretPtr + 16 * i) + seed64;
			const ulong hi = xxh_readLE64(kSecretPtr + 16 * i + 8) - seed64;
			xxh_writeLE64(cast(ubyte*)customSecret + 16 * i, lo);
			xxh_writeLE64(cast(ubyte*)customSecret + 16 * i + 8, hi);
		}
	}
}

alias XXH3_f_accumulate_512 = void function(void*, const(void)*, const(void)*) @safe pure nothrow @nogc;
alias XXH3_f_scrambleAcc = void function(void*, const void*) @safe pure nothrow @nogc;
alias XXH3_f_initCustomSecret = void function(void*, ulong) @safe pure nothrow @nogc;

immutable XXH3_f_accumulate_512 xxh3_accumulate_512 = &xxh3_accumulate_512_scalar;
immutable XXH3_f_scrambleAcc xxh3_scrambleAcc = &xxh3_scrambleAcc_scalar;
immutable XXH3_f_initCustomSecret xxh3_initCustomSecret = &xxh3_initCustomSecret_scalar;

enum XXH_PREFETCH_DIST = 384;
/* TODO: Determine how to implement prefetching in D! Disabled for now */
void XXH_PREFETCH(const ubyte* ptr) {
	version (LDC) {
		import ldc.intrinsics;

		llvm_prefetch(ptr, 0 /* rw == read */ , 3, 1);
	}
}

/*
 * xxh3_accumulate()
 * Loops over xxh3_accumulate_512().
 * Assumption: nbStripes will not overflow the secret size
 */
void xxh3_accumulate(
	ulong* acc, const ubyte* input,
	const ubyte* secret, size_t nbStripes, XXH3_f_accumulate_512 f_acc512)
@trusted {
	size_t n;
	for (n = 0; n < nbStripes; n++) {
		const ubyte* in_ = input + n * XXH_STRIPE_LEN;
		XXH_PREFETCH(in_ + XXH_PREFETCH_DIST);
		f_acc512(acc, in_, secret + n * XXH_SECRET_CONSUME_RATE);
	}
}

void xxh3_hashLong_internal_loop(
	ulong* acc, const ubyte* input, size_t len, const ubyte* secret,
	size_t secretSize, XXH3_f_accumulate_512 f_acc512, XXH3_f_scrambleAcc f_scramble)
@trusted
in (secretSize >= XXH3_SECRET_SIZE_MIN, "secretSize < XXH3_SECRET_SIZE_MIN")
in (len > XXH_STRIPE_LEN, "len <= XXH_STRIPE_LEN") {
	const size_t nbStripesPerBlock = (secretSize - XXH_STRIPE_LEN) / XXH_SECRET_CONSUME_RATE;
	const size_t block_len = XXH_STRIPE_LEN * nbStripesPerBlock;
	const size_t nb_blocks = (len - 1) / block_len;

	for (size_t n = 0; n < nb_blocks; n++) {
		xxh3_accumulate(acc, input + n * block_len, secret, nbStripesPerBlock, f_acc512);
		f_scramble(acc, secret + secretSize - XXH_STRIPE_LEN);
	}

	/* last partial block */
	{
		const size_t nbStripes = ((len - 1) - (block_len * nb_blocks)) / XXH_STRIPE_LEN;
		assert(nbStripes <= (secretSize / XXH_SECRET_CONSUME_RATE),
			"nbStripes > (secretSize / XXH_SECRET_CONSUME_RATE)");
		xxh3_accumulate(acc, input + nb_blocks * block_len, secret, nbStripes, f_acc512);

		/* last stripe */{
			const ubyte* p = input + len - XXH_STRIPE_LEN;
			f_acc512(acc, p, secret + secretSize - XXH_STRIPE_LEN - XXH_SECRET_LASTACC_START);
		}
	}
}

enum XXH_SECRET_LASTACC_START = 7; /* not aligned on 8, last secret is different from acc & scrambler */

ulong xxh3_mix2Accs(const(ulong)* acc, const(ubyte)* secret)
@trusted => xxh3_mul128_fold64(acc[0] ^ xxh_readLE64(secret), acc[1] ^ xxh_readLE64(secret + 8));

XXH64_hash_t xxh3_mergeAccs(const(ulong)* acc, const(ubyte)* secret, ulong start)
@trusted {
	ulong result64 = start;
	size_t i = 0;

	for (i = 0; i < 4; i++) {
		result64 += xxh3_mix2Accs(acc + 2 * i, secret + 16 * i);
	}

	return xxh3_avalanche(result64);
}

static immutable XXH3_INIT_ACC = [
	XXH_PRIME32_3, XXH_PRIME64_1, XXH_PRIME64_2, XXH_PRIME64_3,
	XXH_PRIME64_4, XXH_PRIME32_2, XXH_PRIME64_5, XXH_PRIME32_1
];

XXH64_hash_t xxh3_hashLong_64b_internal(
	const(void)* input, size_t len, const(void)* secret, size_t secretSize,
	XXH3_f_accumulate_512 f_acc512, XXH3_f_scrambleAcc f_scramble)
@trusted {
	align(XXH_ACC_ALIGN) ulong[XXH_ACC_NB] acc = XXH3_INIT_ACC; /* NOTE: This doesn't work in D, fails on 32bit NetBSD */

	xxh3_hashLong_internal_loop(&acc[0], cast(const(ubyte)*)input, len,
		cast(const(ubyte)*)secret, secretSize, f_acc512, f_scramble);

	/* converge into final hash */
	static assert(acc.sizeof == 64, "acc.sizeof != 64");
	/* do not align on 8, so that the secret is different from the accumulator */
	assert(secretSize >= acc.sizeof + XXH_SECRET_MERGEACCS_START,
		"secretSize < acc.sizeof + XXH_SECRET_MERGEACCS_START");
	return xxh3_mergeAccs(&acc[0], cast(const(ubyte)*)secret + XXH_SECRET_MERGEACCS_START,
		cast(ulong)len * XXH_PRIME64_1);
}

enum XXH_SECRET_MERGEACCS_START = 11;

/*
 * It's important for performance to transmit secret's size (when it's static)
 * so that the compiler can properly optimize the vectorized loop.
 * This makes a big performance difference for "medium" keys (<1 KB) when using AVX instruction set.
 */
XXH64_hash_t xxh3_hashLong_64b_withSecret(
	const(void)* input, size_t len, XXH64_hash_t seed64, const(ubyte)* secret, size_t secretLen) =>
	xxh3_hashLong_64b_internal(input, len, secret, secretLen,
		xxh3_accumulate_512, xxh3_scrambleAcc);

/*
 * It's preferable for performance that XXH3_hashLong is not inlined,
 * as it results in a smaller function for small data, easier to the instruction cache.
 * Note that inside this no_inline function, we do inline the internal loop,
 * and provide a statically defined secret size to allow optimization of vector loop.
 */
XXH64_hash_t xxh3_hashLong_64b_default(
	const(void)* input, size_t len, XXH64_hash_t seed64, const(ubyte)* secret, size_t secretLen) =>
	xxh3_hashLong_64b_internal(input, len, &xxh3_kSecret[0],
		xxh3_kSecret.sizeof, xxh3_accumulate_512, xxh3_scrambleAcc);

enum XXH_SEC_ALIGN = 8;

/*
 * xxh3_hashLong_64b_withSeed():
 * Generate a custom key based on alteration of default xxh3_kSecret with the seed,
 * and then use this key for long mode hashing.
 *
 * This operation is decently fast but nonetheless costs a little bit of time.
 * Try to avoid it whenever possible (typically when seed == 0).
 *
 * It's important for performance that XXH3_hashLong is not inlined. Not sure
 * why (uop cache maybe?), but the difference is large and easily measurable.
 */
XXH64_hash_t xxh3_hashLong_64b_withSeed_internal(
	const(void)* input, size_t len, XXH64_hash_t seed,
	XXH3_f_accumulate_512 f_acc512,
	XXH3_f_scrambleAcc f_scramble,
	XXH3_f_initCustomSecret f_initSec)
@trusted {
	//#if XXH_SIZE_OPT <= 0
	if (seed == 0)
		return xxh3_hashLong_64b_internal(input, len, &xxh3_kSecret[0],
			xxh3_kSecret.sizeof, f_acc512, f_scramble);
	//#endif
	else {
		align(XXH_SEC_ALIGN) ubyte[XXH_SECRET_DEFAULT_SIZE] secret;
		f_initSec(&secret[0], seed);
		return xxh3_hashLong_64b_internal(input, len, &secret[0],
			secret.sizeof, f_acc512, f_scramble);
	}
}

/*
 * It's important for performance that XXH3_hashLong is not inlined.
 */
XXH64_hash_t xxh3_hashLong_64b_withSeed(const(void)* input, size_t len,
	XXH64_hash_t seed, const(ubyte)* secret, size_t secretLen) => xxh3_hashLong_64b_withSeed_internal(input, len, seed,
	xxh3_accumulate_512, xxh3_scrambleAcc, xxh3_initCustomSecret);

alias XXH3_hashLong64_f = XXH64_hash_t function(
	const(void)*, size_t, XXH64_hash_t, const(ubyte)*, size_t)
@safe pure nothrow @nogc;

XXH64_hash_t xxh3_64bits_internal(const(void)* input, size_t len,
	XXH64_hash_t seed64, const(void)* secret, size_t secretLen, XXH3_hashLong64_f f_hashLong)
in (secretLen >= XXH3_SECRET_SIZE_MIN, "secretLen < XXH3_SECRET_SIZE_MIN") {
	/*
     * If an action is to be taken if `secretLen` condition is not respected,
     * it should be done here.
     * For now, it's a contract pre-condition.
     * Adding a check and a branch here would cost performance at every hash.
     * Also, note that function signature doesn't offer room to return an error.
     */
	if (len <= 16)
		return xxh3_len_0to16_64b(cast(const(ubyte)*)input, len,
			cast(const(ubyte)*)secret, seed64);
	if (len <= 128)
		return xxh3_len_17to128_64b(cast(const(ubyte)*)input, len,
			cast(const(ubyte)*)secret, secretLen, seed64);
	if (len <= XXH3_MIDSIZE_MAX)
		return xxh3_len_129to240_64b(cast(const(ubyte)*)input, len,
			cast(const(ubyte)*)secret, secretLen, seed64);
	return f_hashLong(input, len, seed64, cast(const(ubyte)*)secret, secretLen);
}

public:

/* XXH PUBLIC API */
XXH64_hash_t xxh3_64bits(const(void)* input, size_t length) => xxh3_64bits_internal(input, length, 0, &xxh3_kSecret[0],
	xxh3_kSecret.sizeof, &xxh3_hashLong_64b_default);

XXH64_hash_t xxh3_64Of(T)(T[] input) @trusted => xxh3_64bits_internal(input.ptr,
	input.length * T.sizeof, 0, &xxh3_kSecret[0], xxh3_kSecret.sizeof, &xxh3_hashLong_64b_default);

XXH64_hash_t xxh3_64Of(T)(T[] input, XXH64_hash_t seed) @trusted => xxh3_64bits_internal(input.ptr,
	input.length * T.sizeof, seed, &xxh3_kSecret[0], xxh3_kSecret.sizeof, &xxh3_hashLong_64b_default);

XXH64_hash_t xxh3_len2(ushort input, XXH64_hash_t seed = 0) @trusted => xxh3_len_1to3_64b(
	cast(const(ubyte)*)&input, 2, &xxh3_kSecret[0], seed);

unittest {
	//Simple example, hashing a string using xxh32Of helper function
	auto hash = xxh3_64Of("abc");
	//Let's get a hash string
	assert(hash == 0x78AF5F94892F3950); // XXH3/64
}
