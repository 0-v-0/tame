module tame.data.yaml.node;

import tame.data.yaml.util;

enum NodeType {
	nil,
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

@safe:

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

	package {
		alias NT = NodeType;
		NT typ;
		Mark mark_;
	}

	@property pure @nogc nothrow const {

		NT type() => typ;

		Mark mark() => mark_;

		bool empty() @trusted {
			switch (typ) {
			case NT.nil,
				NT.merge:
				return true;
			case NT.sequence:
				return children.length == 0;
			case NT.map:
				return map.length == 0;
			default:
			}
			return false;
		}
	}

	this(typeof(null)) pure {
		typ = NT.nil;
	}

	this(T)(T value) @trusted pure if (isScalarType!T) {
		static if (isFloatingPoint!T) {
			typ = NT.decimal;
			alias T = double;
		} else static if (isBoolean!T)
			typ = NT.boolean;
		else
			typ = NT.integer;

		*cast(T*)&b = value;
	}

	this(T : const(char)[])(in T value) @trusted {
		typ = NT.string;
		str = value;
	}

	/// Construct a scalar node
	unittest {
		auto Integer = Node(5);
		auto String = Node("Hello world!");
		auto Float = Node(5.0f);
		auto Boolean = Node(true);
		auto Time = Node(SysTime(DateTime(2005, 6, 15, 20, 0, 0)));
	}

	this(T)(T value) @trusted if (isArray!T && !is(T : const(char)[])) {
		static if (is(Unqual!(ElementType!T) == Node)) {
			children = value;
		} else {
			children.reserve(value.length);
			foreach (item; value)
				children ~= Node(item);
		}
		typ = NT.sequence;
	}

	this(SysTime value) @trusted pure {
		typ = NT.timestamp;
		time = value;
	}

	this(T)(T value) @trusted pure if (is(T : V[string], V)) {
		static if (is(Unqual!T : Node[string]))
			map = value;
		else
			foreach (k, v; value)
				map[k] = Node(v);
		typ = NT.map;
	}

	/// Construct a map node
	pure unittest {
		auto map = Node(["1": "a", "2": "b"]);
	}

	/// Construct a sequence node
	pure unittest {
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

	this(K : const(char)[], V)(K[] keys, V[] values) @trusted
	in (keys.length == values.length, "Lengths of keys and values arrays mismatch") {
		foreach (i, k; keys)
			map[k] = Node(values[i]);
		typ = NT.map;
	}

	alias as = get;

	T get(T)() const if (is(T == enum)) => cast(T)get!(OriginalType!T);

	T get(T)() @trusted const if (isScalarType!T && !is(T == enum)) {
		switch (typ) with (NT) {
		case boolean:
			return cast(T)b;
		case integer:
			return cast(T)l;
		case decimal:
			return cast(T)d;
		case string:
			static if (is(T : const(char)[]))
				return cast(Unqual!T)str;
		default:
		}
		throw new NodeException(text("Cannot convert ", typ, " to " ~ T.stringof), mark_);
	}

	T get(T : const(char)[])() @trusted const if (!is(T == enum)) {
		switch (typ) with (NT) {
		case nil:
			return null;
		case boolean:
			return b ? "true" : "false";
		case timestamp:
			return time.toString();
		case string:
			return cast(T)str;
		default:
		}
		throw new NodeException(text("Cannot convert ", typ, " to string"), mark_);
	}

	unittest {
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

	T get(T : const SysTime)() const @trusted {
		if (typ != NT.timestamp)
			throw new NodeException(text("Cannot convert ", typ, " to timestamp"), mark_);
		return time;
	}

	const(T) get(T : const(Node)[])() const @trusted if (!is(T == enum)) {
		if (typ == NT.nil)
			return null;
		if (typ != NT.sequence)
			throw new NodeException(text("Cannot convert ", typ, " to array"), mark_);
		return children;
	}

	const(T) get(T : const(Node[string]))() const @trusted if (!is(T == enum)) {
		if (typ == NT.nil)
			return null;
		if (typ != NT.map)
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

	unittest {
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
		case NT.sequence:
			return children.length;
		case NT.map:
			return map.length;
		default:
		}
		return 0;
	}

	pure unittest {
		auto m = Node([1, 2, 3]);
		assert(m.length == 3);
		const c = Node([1, 2, 3]);
		assert(c.length == 3);
		immutable i = Node([1, 2, 3]);
		assert(i.length == 3);
	}

	auto ref opIndex(T)(T index) const @trusted {
		switch (typ) {
		case NT.sequence:
			static if (isIntegral!T)
				return children[index];
			else
				throw new NodeException("Only integers may index sequence nodes", mark_);
		case NT.map:
			static if (is(T : string))
				return map[index];
		default:
		}
		throw new NodeException(text("Trying to index a ", typ, " node"), mark_);
	}

	//@property opDispatch(string s)() => opIndex(s);

	///
	@system unittest {
		import core.exception;

		Node arr = Node([11, 12, 13, 14]);
		Node map = Node(["11", "12", "13", "14"], [11, 12, 13, 14]);

		assert(arr[0].as!int == 11);
		assert(collectException!ArrayIndexError(arr[42]));
		assert(map["11"].as!int == 11);
		assert(map["14"].as!int == 14);
	}

	@system unittest {
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
				typ = NT.sequence;
			else
				typ = NT.map;
		}
		switch (typ) {
		case NT.sequence:
			static if (isIntegral!K) {
				static if (is(Unqual!V == Node))
					return children[key] = value;
				else
					return children[key] = Node(value);
			} else
				assert(0, "Only integers may index sequence nodes");
		case NT.map:
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
	 * the sequence are unique, otherwise $(B nil) YAML code will be
	 * emitted.)
	 *
	 * Params:  value = Value to _add to the sequence.
	 */
	void add(T)(T value) @trusted {
		if (empty) {
			typ = NT.sequence;
			children = null;
		} else {
			static if (is(Unqual!T == Node))
				if (typ == NT.string) {
					typ = NT.map;
					auto key = cast(string)str;
					map = null;
					map[key] = value;
					return;
				}
			if (typ != NT.sequence)
				throw new NodeException(text("Trying to add an element to a ", typ,
						" node"), mark_);
		}
		static if (is(Unqual!T == Node))
			children ~= value;
		else
			children ~= Node(value);
	}

	unittest {
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
	 * $(B nil) YAML with "!!map" and "!!omap" tags.)
	 *
	 * Params:  key   = Key to _add.
	 *          value = Value to _add.
	 */
	void add(K : const(char)[], V)(K key, V value) @trusted {
		if (empty) {
			typ = NT.map;
			map = null;
		} else if (typ != NT.map)
			throw new NodeException(text("Trying to add a key-value pair to a ", typ, " node"), mark_);

		static if (is(Unqual!V == Node))
			map[cast(string)key] = value;
		else
			map[cast(string)key] = Node(value);
	}

	unittest {
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
		if (typ == NT.map)
			return key in map;
		if (typ == NT.sequence)
			foreach (ref x; children)
				if (x.get!K == key)
					return &x;
		return null;
	}

	unittest {
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

	unittest {
		auto mNode = Node(["a": 2]);
		assert("a" in mNode);
		const cNode = Node(["a": 2]);
		assert("a" in cNode);
		immutable iNode = Node(["a": 2]);
		assert("a" in iNode);
	}

	bool opEquals(const Node rhs) const => opCmp(rhs) == 0;

	/// Compare with another _node.
	int opCmp(const ref Node rhs) const @trusted {
		import std.math;
		import std.algorithm.comparison : scmp = cmp;

		static int cmp(T)(T a, T b) => a > b ? 1 : a < b ? -1 : 0;

		// Compare validity: if both valid, we have to compare further.
		const v1 = empty;
		const v2 = rhs.empty;
		if (v1)
			return v2 ? -1 : 0;
		if (v2)
			return 1;

		const typeCmp = cmp(type, rhs.type);
		if (typeCmp)
			return typeCmp;

		int cmpCollection(T)() {
			const a = as!T;
			const b = rhs.as!T;
			if (a is b)
				return 0;
			if (a.length != b.length)
				return cmp(a.length, b.length);

			// Equal lengths, compare items.
			static if (is(T : Node[]))
				foreach (i; 0 .. a.length) {
					if (const itemCmp = a[i].opCmp(b[i]))
						return itemCmp;
				}
			else {
				size_t i;
				const keys = b.keys;
				foreach (k, v; a) {
					if (const keyCmp = scmp(k, keys[i])) {
						if (const valCmp = v.opCmp(b[keys[i]]))
							return valCmp;
					}
				}
			}
			return 0;
		}

		switch (typ) {
		case NT.nil:
			return 0;
		case NT.boolean,
			NT.integer:
			return cmp(as!long, rhs.as!long);
		case NT.decimal:
			const a = as!double;
			const b = rhs.as!double;
			if (isNaN(a))
				return isNaN(b) ? 0 : -1;

			if (isNaN(b))
				return 1;

			// Fuzzy equality.
			if (a <= b + double.epsilon && a >= b - double.epsilon)
				return 0;

			return cmp(a, b);
		case NT.timestamp:
			return cmp(time, rhs.as!(const SysTime));
		case NT.string:
			return scmp(str, rhs.as!string);
		case NT.sequence:
			return cmpCollection!(Node[]);
		case NT.map:
			return cmpCollection!(Node[string]);
		default:
		}
		assert(0, text("Cannot compare ", typ, " nodes"));
	}

	// Ensure opCmp is symmetric for collections
	unittest {
		auto a = Node(["New York Yankees", "Atlanta Braves"]);
		auto b = Node(["Detroit Tigers", "Chicago cubs"]);
		assert(a > b);
		assert(b < a);
	}

	// Compute hash of the node.
	size_t toHash() const @trusted pure {
		switch (typ) with (NT) {
		case nil:
			return 0;
		case boolean,
			integer,
		decimal:
			return cast(size_t)(~typ ^ l);
		case timestamp:
			return time.toHash();
		case string:
			return hashOf(str);
		case sequence:
			size_t hash;
			foreach (node; children)
				hash ^= ~node.toHash();
			return hash;
		case map:
			size_t hash;
			foreach (key, value; this.map)
				hash ^= (hashOf(key) << 5) + (value.toHash() ^ 0x38495ab5);
			return hash;
		default:
		}
		assert(0, "Unsupported node type");
	}

	pure unittest {
		assert(Node(42).toHash() != Node(41).toHash());
		assert(Node(42).toHash() != Node("42").toHash());
	}

	union {
	private:
		bool b;
		long l;
		double d;
		const(char)[] str;
		Node[] children;
		Node[string] map;
		const(SysTime) time;
	}
}

unittest {
	import std.algorithm;
	import std.exception;

	Node n1 = Node([1, 2, 3, 4]);
	Node aa = Node(cast(int[string])null);
	const n3 = Node([1, 2, 3, 4]);

	auto r = n1.get!(Node[])
		.map!(x => x.as!int * 10);
	assert(r.equal([10, 20, 30, 40]));

	assertThrown(aa.get!(Node[]));

	foreach (i, x; n3.get!(Node[]))
		assert(x.get!int == i + 1);
}
