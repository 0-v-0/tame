// Modified from https://github.com/jnschulze/LockFreeQueue.d/blob/master/collection/LockFreeQueue.d
module tame.lockfree.queue;

import core.atomic : CAS = cas, MemoryOrder;

private alias cas = CAS!(MemoryOrder.raw, MemoryOrder.raw);

shared struct LockFreeQueue(T) {
	this(T payload) @trusted {
		head = tail = new Node(payload);
	}

	@disable this();

	@property bool empty() const => head == tail;

	void enqueue(T payload) {
		auto node = new Node(payload, null);

		shared(Node)* oldTail, oldNext;

		bool updated;

		while (!updated) {
			// make local copies of the tail and its Next link, but in
			// getting the latter use the local copy of the tail since
			// another thread may have changed the value of tail
			oldTail = tail;
			oldNext = oldTail.next;

			// providing that the tail field has not changed...
			if (tail == oldTail) {
				// ...and its Next field is null
				if (oldNext == null) {
					// ...try to update the tail's Next field
					updated = cas!(shared(Node)*, Node*, Node*)(&tail.next, cast(shared(Node)*)null, node);
				} else {
					// if the tail's Next field was non-null, another thread
					// is in the middle of enqueuing a new node, so try and
					// advance the tail to point to its Next node
					cas!(shared(Node)*, Node*, Node*)(&tail, oldTail, oldNext);
				}
			}
		}

		// try and update the tail field to point to our node; don't
		// worry if we can't, another thread will update it for us on
		// the next call to enqueue()
		cas!(shared(Node)*, Node*, Node*)(&tail, oldTail, node);

		//atomicOp!("+=", size_t, size_t)(_count, 1);
	}

	bool dequeue(ref T payload) {
		bool haveAdvancedHead = false;

		while (!haveAdvancedHead) {
			shared(Node)* oldHead = head,
			oldTail = tail,
			oldHeadNext = oldHead.next;

			if (oldHead == head) {
				// providing that the head field has not changed...
				if (oldHead == oldTail) {
					// ...and it is equal to the tail field
					if (oldHeadNext == null)
						return false;

					// if the head's Next field is non-null and head was equal to the tail
					// then we have a lagging tail: try and update it
					cas!(shared(Node)*, Node*, Node*)(&tail, oldTail, oldHeadNext);
				} else {
					// otherwise the head and tail fields are different
					// grab the item to dequeue, and then try to advance the head reference
					payload = oldHeadNext.payload;
					haveAdvancedHead = cas!(shared(Node)*, Node*, Node*)(&head, oldHead, oldHeadNext);

					//atomicOp!("-=", size_t, size_t)(_count, 1);
				}
			}
		}
		return true;
	}

	/+
	@property size_t count() => _count;
	+/
private:
	shared struct Node {
		T payload;
		Node* next;
	}

	Node* head, tail;
	//size_t _count;
}

unittest {
	import core.thread;
	import std.datetime.stopwatch;
	import std.stdio;

	enum amount = 500_000;

	void push(T)(ref shared(LockFreeQueue!T) queue) {
		foreach (i; 0 .. amount)
			queue.enqueue(cast(shared T)i);
	}

	void pop(T)(ref shared(LockFreeQueue!T) queue) {
		foreach (i; 0 .. amount) {
			T t;
			while (!queue.dequeue(t))
				Thread.yield();
			assert(t == cast(shared T)i);
		}
	}

	StopWatch sw;
	sw.start;

	auto queue = shared LockFreeQueue!size_t(0);
	auto t0 = new Thread({ push(queue); }),
	t1 = new Thread({ pop(queue); });
	t0.start();
	t1.start();
	t0.join();
	t1.join();

	sw.stop;
	auto usecs = sw.peek.total!"usecs";
	writeln("Duration: ", usecs, " usecs");
	writeln("Framerate: ", 1e6 * amount / usecs, " frames/s");
}
