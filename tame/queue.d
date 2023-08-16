module tame.queue;
import std.traits : hasMember, hasIndirections;

/*
 * Simple queue implemented as a singly linked list with a tail pointer.
 *
 * Needed in some D:YAML code that needs a queue-like structure without too much
 * reallocation that goes with an array.
 *
 * Allocations are non-GC and are damped by a free-list based on the nodes
 * that are removed. Note that elements lifetime must be managed
 * outside.
 */
struct Queue(T) if (!hasMember!(T, "__xdtor")) {
private:

	// Linked list node containing one element and pointer to the next node.
	struct Node {
		T value;
		Node* next;
	}

	// Start of the linked list - first element added in time (end of the queue).
	Node* first_;
	// Last element of the linked list - last element added in time (start of the queue).
	Node* last_;
	// free-list
	Node* stock;

	// Length of the queue.
	size_t len;

	// allocate a new node or recycle one from the stock.
	Node* make(T value, Node* theNext = null) @trusted nothrow @nogc {
		import std.experimental.allocator : make;
		import std.experimental.allocator.mallocator : Mallocator;

		Node* result;
		if (stock !is null) {
			result = stock;
			stock = result.next;
			result.value = value;
			result.next = theNext;
		} else {
			result = Mallocator.instance.make!Node(value, theNext);
			// GC can dispose T managed member if it thinks they are no used...
			static if (hasIndirections!T) {
				import core.memory : GC;

				GC.addRange(result, Node.sizeof);
			}
		}
		return result;
	}

	// free the stock of available free nodes.
	void freeStock() @trusted @nogc nothrow {
		import std.experimental.allocator.mallocator : Mallocator;

		while (stock) {
			Node* toFree = stock;
			stock = stock.next;
			static if (hasIndirections!T) {
				import core.memory : GC;

				GC.removeRange(toFree);
			}
			Mallocator.instance.deallocate((cast(ubyte*)toFree)[0 .. Node.sizeof]);
		}
	}

public:

	@disable void opAssign(ref Queue);
	@disable bool opEquals(ref Queue);
	@disable int opCmp(ref Queue);

@safe nothrow:
	this(this) @nogc {
		auto node = first_;
		first_ = null;
		last_ = null;
		while (node !is null) {
			Node* newLast = make(node.value);
			if (last_ !is null)
				last_.next = newLast;
			if (first_ is null)
				first_ = newLast;
			last_ = newLast;
			node = node.next;
		}
	}

	~this() {
		freeStock();
		stock = first_;
		freeStock();
	}

	/// Returns a forward range iterating over this queue.
	auto range() {
		static struct Result {
			private Node* cursor;

		@safe pure nothrow @nogc:
			void popFront() {
				cursor = cursor.next;
			}

			ref T front()
			in (cursor) => cursor.value;

			bool empty() => cursor is null;
		}

		return Result(first_);
	}

	/// Push a new item to the queue.
	void push(T item) @nogc {
		Node* newLast = make(item);
		if (last_ !is null)
			last_.next = newLast;
		if (first_ is null)
			first_ = newLast;
		last_ = newLast;
		++len;
	}

	/// Insert a new item putting it to specified index in the linked list.
	void insert(T item, const size_t idx)
	in (idx <= len) {
		if (idx == 0) {
			first_ = make(item, first_);
			++len;
		}  // Adding before last added element, so we can just push.
		else if (idx == len) {
			push(item);
		} else {
			// Get the element before one we're inserting.
			Node* current = first_;
			foreach (i; 1 .. idx)
				current = current.next;

			assert(current);
			// Insert a new node after current, and put current.next behind it.
			current.next = make(item, current.next);
			++len;
		}
	}

	/// Returns: The next element in the queue and remove it.
	T pop()
	in (!empty, "Trying to pop an element from an empty queue") {
		T result = peek();

		Node* oldStock = stock;
		Node* old = first_;
		first_ = first_.next;

		// start the stock from the popped element
		stock = old;
		old.next = null;
		// add the existing "old" stock to the new first stock element
		if (oldStock !is null)
			stock.next = oldStock;

		if (--len == 0) {
			assert(first_ is null);
			last_ = null;
		}

		return result;
	}

pure @nogc:
	/// Returns: The next element in the queue.
	ref inout(T) peek() inout
	in (!empty, "Trying to peek at an element in an empty queue")
		=> first_.value;

	/// Returns: true of the queue empty, false otherwise.
	bool empty() const => first_ is null;

	/// Returns: The number of elements in the queue.
	size_t length() const => len;
}

@safe nothrow unittest {
	auto queue = Queue!int();
	assert(queue.empty);
	foreach (i; 0 .. 65) {
		queue.push(5);
		assert(queue.pop() == 5);
		assert(queue.empty);
		assert(queue.len == 0);
	}

	auto arr = [1, -1, 2, -2, 3, -3, 4, -4, 5, -5];
	foreach (i; arr)
		queue.push(i);

	arr = 42 ~ arr[0 .. 3] ~ 42 ~ arr[3 .. $] ~ 42;
	queue.insert(42, 3);
	queue.insert(42, 0);
	queue.insert(42, queue.length);

	int[] arr2;
	while (!queue.empty) {
		arr2 ~= queue.pop();
	}

	assert(arr == arr2);
}
