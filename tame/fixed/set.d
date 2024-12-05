module tame.fixed.set;

import tame.fixed.map;

@safe pure nothrow @nogc:

struct Set(T, size_t N = 16, alias hasher = hashOf) {
	static assert(!((N - 1) & N), "N must be 0 or a power of 2");
pure:
	struct Bucket {
	private:
		size_t hash;
		T val;

		@property bool empty() const => hash == Hash.empty;

		@property bool deleted() const => hash == Hash.deleted;

		@property bool filled() const => cast(ptrdiff_t)hash < 0;
	}

	private {
		Bucket[N] buckets;
		uint used;
		uint deleted;

		size_t calcHash(in T pkey) {
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

		inout(Bucket)* findSlotLookup(size_t hash, in T val) inout {
			size_t n;
			for (size_t i = hash & mask; n < buckets.length; ++n) {
				if (buckets[i].hash == hash && val == buckets[i].val)
					return &buckets[i];
				i = (i + 1) & mask;
			}
			return null;
		}
	}

	enum mask = N - 1;

	enum capacity = buckets.length;

	@property {
		uint length() const
		in (used >= deleted) => used - deleted;

		bool empty() const => length == 0;

		bool full() const => length == buckets.length;
	}

	bool add(in T val) {
		if (length == N)
			return false;

		const hash = calcHash(val);
		if (auto p = findSlotLookup(hash, val))
			return false;

		auto p = findSlotInsert(hash);
		if (p.deleted)
			--deleted;

		// check load factor and possibly grow
		else if (++used > capacity)
			return false;

		p.hash = hash;
		p.val = val;
		return true;
	}

	bool remove(in T val) {
		if (!length)
			return false;

		const hash = calcHash(val);
		if (auto p = findSlotLookup(hash, val)) {
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

	T* opBinaryRight(string op : "in")(in T val) {
		if (!length)
			return null;

		const keyHash = calcHash(val);
		if (auto p = findSlotLookup(keyHash, val))
			return &p.val;
		return null;
	}

	bool has(in T val) => (val in this) !is null;
}

unittest {
	Set!(int, 4) s;
	assert(s.empty);
	assert(s.add(1));
	assert(s.add(2));
	assert(!s.add(2));
	assert(s.add(3));
	assert(s.length == 3);
	assert(s.add(4));
	assert(s.length == 4);
	assert(!s.add(5));
	assert(s.length == 4);
	assert(s.remove(2));
	assert(s.length == 3);
	assert(s.add(5));
	assert(s.length == 4);
	assert(s.remove(5));
	assert(s.length == 3);
}

unittest {
	Set!(int, 0) s;
	assert(s.empty);
}
