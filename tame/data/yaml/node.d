module tame.data.yaml.node;

import tame.data.yaml.util;

enum NodeType {
	null_,
	merge,
	boolean,
	integer,
	decimal,
	binary,
	timestamp,
	string,
	map,
	sequence
}

/// Exception thrown at node related errors.
// Construct a NodeException.
//
// Params:  msg   = Error message.
//          start = Start position of the node.
class NodeException : Exception {
	// Construct a NodeException.
	//
	// Params:  msg   = Error message.
	//          start = Start position of the node.
	package this(string msg, Mark start, string file = __FILE__, size_t line = __LINE__)
	@safe pure nothrow {
		super(msg ~ "\nNode at: " ~ start.toString(), file, line);
	}
}

struct Node {
	import std.datetime;
	import std.exception;
	import std.traits;
	import tame.format;

	package NodeType typ;
	package Mark mark_;

	@property @safe pure @nogc nothrow const {

		NodeType type() => typ;

		Mark mark() => mark_;

		bool empty() @trusted {
			switch (typ) {
			case NodeType.null_,
				NodeType.merge:
				return true;
			case NodeType.sequence:
				return children.length == 0;
			case NodeType.map:
				return map.length == 0;
			default:
			}
			return false;
		}
	}

	this(typeof(null)) {
		typ = NodeType.null_;
	}

	this(T)(T value) @trusted if (isScalarType!T) {
		static if (isFloatingPoint!T) {
			typ = NodeType.decimal;
			alias T = double;
		} else static if (isBoolean!T)
			typ = NodeType.boolean;
		else
			typ = NodeType.integer;

		*cast(T*)&p = value;
	}

	this(T : const(char)[])(in T value) @trusted {
		typ = NodeType.string;
		*cast(T*)&p = value;
	}

	/// Construct a scalar node
	@safe unittest {
		auto Integer = Node(5);
		auto String = Node("Hello world!");
		auto Float = Node(5.0f);
		auto Boolean = Node(true);
		auto Time = Node(SysTime(DateTime(2005, 6, 15, 20, 0, 0), UTC()));
	}

	this(T)(T value) @trusted if (isArray!T && !is(T : const(char)[])) {
		static if (is(Unqual!(ElementType!T) == Node)) {
			children = value;
		} else {
			children.reserve(value.length);
			foreach (item; value)
				children ~= Node(item);
		}
		typ = NodeType.sequence;
	}

	this(in SysTime value) @trusted {
		typ = NodeType.timestamp;
		time = value;
	}

	this(T)(T value) @trusted if (is(T : V[string], V)) {
		static if (is(Unqual!T : Node[string]))
			map = value;
		else
			foreach (k, v; value)
				map[k] = Node(v);
		typ = NodeType.map;
	}

	/// Construct a map node
	@safe unittest {
		auto map = Node(["1": "a", "2": "b"]);
	}

	@safe {
		/// Construct a sequence node
		unittest {
			// Will be emitted as a sequence (default for arrays)
			auto seq = Node([1, 2, 3, 4, 5]);
			// Can also store arrays of arrays
			auto node = Node([[1, 2], [3, 4]]);
		}

		unittest {
			auto a = Node(42);
			assert(a.type == NodeType.integer);
			assert(a.as!int == 42 && a.as!float == 42.0f);

			auto b = Node("foo");
			assert(b.as!string == "foo");
		}

		unittest {
			with (Node([1, 2, 3])) {
				assert(typ == NodeType.sequence);
				assert(length == 3);
				assert(opIndex(2).as!int == 3);
			}
		}

		unittest {
			auto a = ["1": 1, "2": 2];
			with (Node(a)) {
				assert(type == NodeType.map);
				assert(length == 2);
				assert(opIndex("2").as!int == 2);
			}
		}
	}

	this(K : const(char)[], V)(K[] keys, V[] values) @trusted
	in (keys.length == values.length, "Lengths of keys and values arrays mismatch") {
		foreach (i, k; keys)
			map[k] = Node(values[i]);
		typ = NodeType.map;
	}

	alias as = get;

	T get(T)() const if (is(T == enum)) => cast(T)get!(OriginalType!T);

	T get(T)() @trusted const if (isScalarType!T && !is(T == enum)) {
		switch (typ) with (NodeType) {
		case boolean:
			return cast(T)*cast(bool*)&p;
		case integer:
			return cast(T)*cast(long*)&p;
		case decimal:
			return cast(T)*cast(double*)&p;
		case string:
			static if (is(T : const(char)[]))
				return cast(Unqual!T)(*cast(.string*)&p);
		default:
		}
		throw new NodeException(text("Cannot convert ", typ, " to " ~ T.stringof), mark_);
	}

	T get(T : const(char)[])() @trusted const if (!is(T == enum)) {
		switch (typ) with (NodeType) {
		case null_:
			return null;
		case boolean:
			return *cast(bool*)&p ? "true" : "false";
		case timestamp:
			return time.toString();
		case string:
			return *cast(T*)&p;
		default:
		}
		throw new NodeException(text("Cannot convert ", typ, " to string"), mark_);
	}

	@safe unittest {
		const c = Node(42);
		assert(c.get!int == 42);
		try {
			c.get!string;
			assert(0);
		} catch (NodeException) {
		}
		assert(c.get!double == 42.0);

		immutable i = Node(42);
		assert(i.get!int == 42);
		try {
			i.get!string;
			assert(0);
		} catch (NodeException) {
		}
		assert(i.get!double == 42.0);
		assert(i.get!(const double) == 42.0);
		assert(i.get!(immutable double) == 42.0);
	}

	T get(T : SysTime)() const {
		if (typ != NodeType.timestamp)
			throw new NodeException(text("Cannot convert ", typ, " to timestamp"), mark_);
		return time;
	}

	const(T) get(T : const(Node)[])() const @trusted if (!is(T == enum)) {
		if (typ == NodeType.null_)
			return null;
		if (typ != NodeType.sequence)
			throw new NodeException(text("Cannot convert ", typ, " to array"), mark_);
		return children;
	}

	const(T) get(T : const(Node[string]))() const @trusted if (!is(T == enum)) {
		if (typ == NodeType.null_)
			return null;
		if (typ != NodeType.map)
			throw new NodeException(text("Cannot convert ", typ, " to map"), mark_);
		return map;
	}

	T get(T : string[string])() const @trusted if (!is(T == enum)) {
		string[string] m;
		foreach (key, val; get!(Node[string])) {
			m[key] = val.get!string;
		}
		return m;
	}

	@safe unittest {
		assertThrown(Node("foo").get!int);
		assertThrown(Node("4.2").get!int);
	}

	/** If this is a collection, return its _length.
	 *
	 * Otherwise, return 0.
	 *
	 * Returns: Number of elements in a sequence or key-value pairs in a map.
	 */
	@property size_t length() const pure @trusted {
		switch (typ) {
		case NodeType.sequence:
			return children.length;
		case NodeType.map:
			return map.length;
		default:
		}
		return 0;
	}

	@safe unittest {
		auto node = Node([1, 2, 3]);
		assert(node.length == 3);
		const cNode = Node([1, 2, 3]);
		assert(cNode.length == 3);
		immutable iNode = Node([1, 2, 3]);
		assert(iNode.length == 3);
	}

	auto ref opIndex(T)(T index) const @trusted {
		switch (typ) {
		case NodeType.sequence:
			static if (isIntegral!T)
				return children[index];
			else
				throw new NodeException("Only integers may index sequence nodes", mark_);
		case NodeType.map:
			static if (is(T : string))
				return map[index];
		default:
		}
		throw new NodeException(text("Trying to index a ", typ, " node"), mark_);
	}

	//@property opDispatch(string s)() => opIndex(s);

	///
	unittest {
		import core.exception;

		Node arr = Node([11, 12, 13, 14]);
		Node map = Node(["11", "12", "13", "14"], [11, 12, 13, 14]);

		assert(arr[0].as!int == 11);
		assert(collectException!ArrayIndexError(arr[42]));
		assert(map["11"].as!int == 11);
		assert(map["14"].as!int == 14);
	}

	unittest {
		import core.exception;

		Node arr = Node([11, 12, 13, 14]);
		Node map = Node(["11", "12", "13", "14"], [11, 12, 13, 14]);

		assert(arr[0].as!int == 11);
		assert(collectException!ArrayIndexError(arr[42]));
		// BUG: collectException!NodeException(map[11].as!int) will
		// segfault, so we have to use try-catch.
		try {
			map[11].as!int;
			assert(0);
		} catch (NodeException) {
		}
		assert(map["11"].as!int == 11);
		assert(map["14"].as!int == 14);
		assert(collectException!RangeError(map["42"]));

		arr.add(null);
		map.add(null, "Nothing");
		assert(map[null].as!string == "Nothing");
	}

	/** Set element at specified index in a collection.
	 *
	 * This method can only be called on collection nodes.
	 *
	 * If the node is a sequence, index must be integral.
	 *
	 * If the node is a map, sets the _value corresponding to the first
	 * key matching index (including conversion, so e.g. "42" matches 42).
	 *
	 * If the node is a map and no key matches index, a new key-value
	 * pair is added to the map. In sequences the index must be in
	 * range. This ensures behavior siilar to D arrays and associative
	 * arrays.
	 *
	 * To set element at a null index, use null for index.
	 *
	 * Params:
	 *          value = Value to assign.
	 *          index = Index of the value to set.
	 *
	 * Throws:  NodeException if the node is not a collection
	 */
	auto opIndexAssign(K, V)(V value, K key) @trusted {
		if (empty) {
			static if (isIntegral!K)
				typ = NodeType.sequence;
			else
				typ = NodeType.map;
		}
		switch (typ) {
		case NodeType.sequence:
			static if (isIntegral!K) {
				static if (is(Unqual!V == Node))
					return children[key] = value;
				else
					return children[key] = Node(value);
			} else
				assert(0, "Only integers may index sequence nodes");
		case NodeType.map:
			static if (is(Unqual!V == Node))
				return map[key] = value;
			else
				return map[key] = Node(value);
		default:
			throw new NodeException(text("Trying to index a ", typ, " node"), mark_);
		}
	}

	/** Add an element to a sequence.
	 *
	 * This method can only be called on sequence nodes.
	 *
	 * If value is a node, it is copied to the sequence directly. Otherwise
	 * value is converted to a node and then stored in the sequence.
	 *
	 * $(P When emitting, all values in the sequence will be emitted. When
	 * using the !!set tag, the user needs to ensure that all elements in
	 * the sequence are unique, otherwise $(B null_) YAML code will be
	 * emitted.)
	 *
	 * Params:  value = Value to _add to the sequence.
	 */
	void add(T)(T value) @trusted {
		if (empty) {
			typ = NodeType.sequence;
			children = null;
		} else {
			static if (is(Unqual!T == Node))
				if (typ == NodeType.string) {
					typ = NodeType.map;
					auto key = *cast(string*)&p;
					map = null;
					map[key] = value;
					return;
				}
			if (typ != NodeType.sequence)
				throw new NodeException(text("Trying to add an element to a ", typ,
						" node"), mark_);
		}
		static if (is(Unqual!T == Node))
			children ~= value;
		else
			children ~= Node(value);
	}

	@safe unittest {
		with (Node([1, 2, 3, 4])) {
			add(5.0f);
			assert(opIndex(4).as!float == 5.0f);
		}
		with (Node()) {
			add(5.0f);
			assert(opIndex(0).as!float == 5.0f);
		}
		with (Node(5.0f)) {
			assertThrown!NodeException(add(5.0f));
		}
		with (Node(["5": true])) {
			assertThrown!NodeException(add(5.0f));
		}
	}

	/** Add a key-value pair to a map.
	 *
	 * This method can only be called on map nodes.
	 *
	 * If key and/or value is a node, it is copied to the map directly.
	 * Otherwise it is converted to a node and then stored in the map.
	 *
	 * $(P It is possible for the same key to be present more than once in a
	 * map. When emitting, all key-value pairs will be emitted.
	 * This is useful with the "!!pairs" tag, but will result in
	 * $(B null_) YAML with "!!map" and "!!omap" tags.)
	 *
	 * Params:  key   = Key to _add.
	 *          value = Value to _add.
	 */
	void add(K : const(char)[], V)(K key, V value) @trusted {
		if (empty) {
			typ = NodeType.map;
			map = null;
		} else if (typ != NodeType.map)
			throw new NodeException(text("Trying to add a key-value pair to a ", typ, " node"), mark_);

		static if (is(Unqual!V == Node))
			map[cast(string)key] = value;
		else
			map[cast(string)key] = Node(value);
	}

	@safe unittest {
		with (Node(["1", "2"], [3, 4])) {
			add("5", "6");
			assert(opIndex("5").as!string == "6");
		}
		with (Node()) {
			add("5", "6");
			assert(opIndex("5").as!string == "6");
		}
		with (Node(5.0f)) {
			assertThrown!NodeException(add("5", "6"));
		}
		with (Node([5.0f])) {
			assertThrown!NodeException(add("5", "6"));
		}
	}

	/** Determine whether a key is in a map, and access its value.
	 *
	 * This method can only be called on map nodes.
	 *
	 * Params:   key = Key to search for.
	 *
	 * Returns:  A pointer to the value (as a Node) corresponding to key,
	 *           or null if not found.
	 *
	 * Note:     Any modification to the node can invalidate the returned
	 *           pointer.
	 */
	inout(Node*) opBinaryRight(string op : "in", K)(K key) inout @trusted {
		if (typ == NodeType.map)
			return key in map;
		if (typ == NodeType.sequence)
			foreach (ref x; children)
				if (x.get!K == key)
					return &x;
		return null;
	}

	@safe unittest {
		auto map = Node(["foo", "baz"], ["bar", "qux"]);
		assert("bad" !in map);
		auto foo = "foo" in map;
		assert(foo && *foo == Node("bar"));
		assert(foo.get!string == "bar");
		*foo = Node("newfoo");
		assert(map["foo"] == Node("newfoo"));
		auto mNode = Node(["1", "2", "3"]);
		assert("2" in mNode);
		const cNode = Node(["1", "2", "3"]);
		assert("2" in cNode);
		immutable iNode = Node(["1", "2", "3"]);
		assert("2" in iNode);
	}

	@safe unittest {
		auto mNode = Node(["a": 2]);
		assert("a" in mNode);
		const cNode = Node(["a": 2]);
		assert("a" in cNode);
		immutable iNode = Node(["a": 2]);
		assert("a" in iNode);
	}

	bool opEquals(const Node rhs) const @safe => opCmp(rhs) == 0;

	/// Compare with another _node.
	int opCmp(const ref Node rhs) const @trusted {
		import std.math;
		import std.algorithm.comparison : scmp = cmp;

		static int cmp(T, U)(T a, U b) => a > b ? 1 : a < b ? -1 : 0;

		// Compare validity: if both valid, we have to compare further.
		const v1 = empty;
		const v2 = rhs.empty;
		if (v1)
			return v2 ? -1 : 0;
		if (v2)
			return 1;

		const typeCmp = cmp(type, rhs.type);
		if (typeCmp != 0)
			return typeCmp;

		int compareCollection(T)() {
			const c1 = as!T;
			const c2 = rhs.as!T;
			if (c1 is c2)
				return 0;
			if (c1.length != c2.length)
				return cmp(c1.length, c2.length);
			// Equal lengths, compare items.
			static if (is(T : Node[]))
				foreach (i; 0 .. c1.length) {
					const itemCmp = c1[i].opCmp(c2[i]);
					if (itemCmp)
						return itemCmp;
				}
			else {
				size_t i;
				const keys = c2.keys;
				foreach (k, v; c1) {
					const keyCmp = scmp(k, keys[i]);
					if (keyCmp) {
						const valCmp = v.opCmp(c2[keys[i]]);
						if (valCmp)
							return valCmp;
					}
				}
			}

			return 0;
		}

		switch (typ) {
		case NodeType.null_:
			return 0;
		case NodeType.boolean,
			NodeType.integer:
			return cmp(as!long, rhs.as!long);
		case NodeType.decimal:
			const r1 = as!double;
			const r2 = rhs.as!double;
			if (isNaN(r1))
				return isNaN(r2) ? 0 : -1;

			if (isNaN(r2))
				return 1;

			// Fuzzy equality.
			if (r1 <= r2 + double.epsilon && r1 >= r2 - double.epsilon)
				return 0;

			return cmp(r1, r2);
		case NodeType.timestamp:
			return cmp(time, rhs.as!SysTime);
		case NodeType.string:
			return scmp(*cast(string*)&p, rhs.as!string);
		case NodeType.sequence:
			return compareCollection!(Node[]);
		case NodeType.map:
			return compareCollection!(Node[string]);
		default:
			assert(0, text("Cannot compare ", typ, " nodes"));
		}
	}

	// Ensure opCmp is symmetric for collections
	@safe unittest {
		auto n1 = Node(["New York Yankees", "Atlanta Braves"]);
		auto n2 = Node(["Detroit Tigers", "Chicago cubs"]);
		assert(n1 > n2);
		assert(n2 < n1);
	}

	// Compute hash of the node.
	size_t toHash() const @trusted pure {
		import tame.hash.xxh3;

		switch (typ) with (NodeType) {
		case null_:
			return 0;
		case boolean,
			integer,
		decimal:
			return cast(size_t)(~typ ^ *cast(long*)&p);
		case timestamp:
			return time.toHash();
		case string:
			return xxh3_64Of(*cast(.string*)&p);
		case sequence:
			size_t hash;
			foreach (node; children)
				hash ^= ~node.toHash();
			return hash;
		case map:
			size_t hash;
			foreach (key, value; this.map)
				hash ^= (xxh3_64Of(key) << 5) + (value.toHash() ^ 0x38495ab5);
			return hash;
		default:
			assert(0, "Unsupported node type");
		}
	}

	@safe unittest {
		assert(Node(42).toHash() != Node(41).toHash());
		assert(Node(42).toHash() != Node("42").toHash());
	}

	union {
	private:
		ubyte p;
		Node[] children;
		Node[string] map;
		SysTime time;
	}
}

@safe unittest {
	import std.algorithm;
	import std.exception;

	Node n1 = Node([1, 2, 3, 4]);
	Node n2 = Node(cast(int[string])null);
	const n3 = Node([1, 2, 3, 4]);

	auto r = n1.get!(Node[])
		.map!(x => x.as!int * 10);
	assert(r.equal([10, 20, 30, 40]));

	assertThrown(n2.get!(Node[]));

	auto r2 = n3.get!(Node[])
		.map!(x => x.as!int * 10);
	assert(r2.equal([10, 20, 30, 40]));
}
