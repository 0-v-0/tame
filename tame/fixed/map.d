module tame.fixed.map;

@safe pure nothrow @nogc:

struct Map(K, V, size_t N = 16, alias hasher = hashOf) {
	static assert(!((N - 1) & N), "N must be 0 or a power of 2");
pure:
	struct Bucket {
	private:
		size_t hash;
		K key;
		V val;

		@property bool empty() const => hash == Hash.empty;

		@property bool deleted() const => hash == Hash.deleted;

		@property bool filled() const => cast(ptrdiff_t)hash < 0;
	}

	private {
		enum mask = N - 1;

		Bucket[N] buckets;
		uint used;
		uint deleted;

		size_t calcHash(in K pkey) {
			// highest bit is set to distinguish empty/deleted from filled buckets
			const hash = hasher(pkey);
			return mix(hash) | Hash.filled;
		}

		inout(Bucket)* findSlotInsert(size_t hash) inout {
			for (size_t i = hash & mask, j = 1;; ++j) {
				if (!buckets[i].filled)
					return &buckets[i];
				i = (i + j) & mask;
			}
		}

		inout(Bucket)* findSlotLookup(size_t hash, in K key) inout {
			size_t n;
			for (size_t i = hash & mask; n < buckets.length; ++n) {
				if (buckets[i].hash == hash && key == buckets[i].key)
					return &buckets[i];
				i = (i + 1) & mask;
			}
			return null;
		}
	}

	enum capacity = buckets.length;

	@property {
		uint length() const
		in (used >= deleted) => used - deleted;

		bool empty() const => length == 0;

		bool full() const => length == buckets.length;
	}

	bool set(in K key, V val) {
		if (length == N)
			return false;

		const keyHash = calcHash(key);
		if (auto p = findSlotLookup(keyHash, key)) {
			p.val = val;
			return true;
		}

		auto p = findSlotInsert(keyHash);
		if (p.deleted)
			--deleted;

		// check load factor and possibly grow
		else if (++used > capacity)
			return false;

		p.hash = keyHash;
		p.key = key;
		p.val = val;
		return true;
	}

	bool remove(in K key) {
		if (!length)
			return false;

		const hash = calcHash(key);
		if (auto p = findSlotLookup(hash, key)) {
			// clear entry
			p.hash = Hash.deleted;
			// just mark it to be disposed

			++deleted;
			return true;
		}
		return false;
	}

	void clear() {
		deleted = used = 0;
		buckets[] = Bucket.init;
	}

	V* opBinaryRight(string op : "in")(in K key) {
		if (!length)
			return null;

		const keyHash = calcHash(key);
		if (auto p = findSlotLookup(keyHash, key))
			return &p.val;
		return null;
	}

	V get(in K key) {
		if (auto ret = key in this)
			return *ret;
		return V.init;
	}

	alias opIndex = get;

	void opIndexAssign(V value, in K key) {
		set(key, value);
	}
}

unittest {
	Map!(int, int, 4) m;
	assert(m.empty);
	assert(m.set(1, 2));
	assert(m.set(2, 3));
	assert(m.set(3, 4));
	assert(m.length == 3);
	assert(m.set(4, 5));
	assert(m.length == 4);
	assert(!m.set(5, 6));
	assert(m.length == 4);
	assert(m.remove(2));
	assert(m.length == 3);
	assert(m.set(5, 6));
	assert(m.length == 4);
	assert(m.remove(5));
	assert(m.length == 3);
}

unittest {
	Map!(int, int, 0) m;
	assert(m.empty);
}

package:
size_t mix(size_t h) {
	enum m = 0x5bd1e995;
	h ^= h >> 13;
	h *= m;
	h ^= h >> 15;
	return h;
}

enum INIT_NUM_BUCKETS = 8;

/// magic hash constants to distinguish empty, deleted, and filled buckets
enum Hash : size_t {
	empty = 0,
	deleted = 0x1,
	filled = size_t(1) << 8 * size_t.sizeof - 1,
}
