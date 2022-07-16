module tame.mlmap;

private enum isSomeString(T) = is(immutable T == immutable C[], C) &&
	(is(C == char) || is(C == wchar) || is(C == dchar));

struct Node(K = string, V = string) {
	V[K] aa;
	alias aa this;
	Node!(K, V)* next;

	@property size_t length() const nothrow @nogc @safe {
		auto len = aa.length;
		if (next)
			len += next.length;
		return len;
	}

	@property bool empty() const nothrow @nogc @safe {
		return length == 0;
	}

	void rehash() nothrow {
		aa.rehash();
		if (next)
			next.rehash();
	}

	V get(scope const K key) nothrow {
		if (auto ret = key in aa)
			return *ret;
		return next ? next.get(key) : V.init;
	}

	alias opIndex = get;

	static if (isSomeString!K)
		@property {
			auto opDispatch(K key)() {
				return get(key);
			}

			auto opDispatch(K key)(scope const V value) {
				return aa[key] = value;
			}
		}

	V* opBinaryRight(string op : "in")(scope const K key) {
		if (auto ret = key in aa)
			return ret;
		if (next)
			return key in *next;
		return null;
	}

	bool remove(scope const K key) @nogc nothrow {
		bool result = aa.remove(key);
		return (next && next.remove(key)) || result;
	}

	bool remove(MLMap!(K, V) node) @nogc nothrow {
		auto tmp = &this;
		while (tmp !is node) {
			tmp = tmp.next;
			if (!tmp)
				return false;
		}
		auto p = tmp.next;
		if (!p)
			return false;
		tmp.next = tmp.next.next;
		return true;
	}

	bool insert(MLMap!(K, V) m, uint level = 0) @nogc nothrow {
		auto tmp = &this;
		for (uint i = level; i--;) {
			tmp = tmp.next;
			if (!tmp)
				return false;
		}
		auto node = m;
		while (node.next)
			node = node.next;
		if (level) {
			node.next = tmp.next;
			tmp.next = m;
		} else
			node.next = tmp;
		return true;
	}

	void popFront() {
		destroy(aa);
		if (next)
			this = *next;
	}

	bool removeAt(uint level) @nogc nothrow {
		auto tmp = &this;
		while (level--) {
			tmp = tmp.next;
			if (!tmp)
				return false;
		}
		auto p = tmp.next;
		if (!p)
			return false;
		tmp.next = tmp.next.next;
		return true;
	}

	void clear() nothrow {
		aa.clear();
		if (next)
			next.clear();
	}

	void free() @nogc nothrow {
		destroy(aa);
		for (auto node = next; node; node = node.next)
			destroy(node.aa);
	}

	auto merge(V[K] aa) {
		MLMap!(K, V) m = mlmap(aa);
		m.next = &this;
		return m;
	}

	auto merge(MLMap!(K, V) m) {
		m.next = &this;
		return m;
	}
}

/// A multilevel map
struct MLMap(K = string, V = string) {
	Node!(K, V)* head;
	alias head this;

	@disable this();

	this(Node!(K, V)* node) {
		head = node;
	}

	MLMap!(K, V) opOpAssign(string op : "~")(MLMap!(K, V) rhs) {
		if (empty)
			return rhs;
		auto m = head;
		while (m.next)
			m = m.next;
		m.next = rhs;
		return mlmap(head);
	}

	MLMap!(K, V) opBinary(string op : "~")(MLMap!(K, V) rhs) {
		auto head = mlmap();
		auto m = head;
		for (auto p = next; p; p = p.next) {
			auto node = mlmap(p.aa);
			m.next = node;
			m = node;
		}
		m.next = rhs;
		return head;
	}
}

auto mlmap(K = string, V = string)() {
	return MLMap!(K, V)(new Node!(K, V));
}

auto mlmap(K, V)(Node!(K, V)* node) {
	return MLMap!(K, V)(node);
}

auto mlmap(K, V)(V[K] aa) {
	return mlmap(new Node!(K, V)(aa));
}

auto mlmap(K, V)(V[K] aa, Node!(K, V)* next) {
	return mlmap(new Node!(K, V)(aa, next));
}

void removeNext(K, V)(MLMap!(K, V) node)
in (!node.empty) {
	node.next = node.next.next;
}

mixin template DefVars() {
	auto a = mlmap(), b = mlmap();
	auto free = { a.free; b.free; };
}

unittest {
	mixin DefVars;
	a.a = "foo";
	b.b = "bar";
	auto r = (a ~ b).b;
	assert(r == "bar", r);
	assert(a.b == "", a.b);
	assert(a.insert(b));
	auto t = b.b;
	assert(t == "bar", t);
	free();
}

unittest {
	mixin DefVars;
	a.a = "foo";
	b.b = "bar";
	a ~= b;
	assert(a.b == "bar", a.b);
	free();
}

unittest {
	mixin DefVars;
	a.a = "foo";
	b.a = "bar";
	a = a.merge(b);
	auto r = a.a;
	assert(r == "bar", r);
	free();
}

unittest {
	mixin DefVars;
	a.a = "foo";
	b.a = "bar";
	a ~= b;
	assert(a.a == "foo", a.a);
	a.popFront();
	assert(a.a == "bar", a.a);
	free();
}
