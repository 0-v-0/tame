// Modified from https://github.com/MartinNowak/lock-free/blob/master/src/lock_free/dlist.d
module tame.lockfree.dlist;

import core.atomic;
import std.algorithm;
import tame.unsafe.ptrop;

/// lock-free implementation
shared class AtomicDList(T) {
	shared struct Node {
		private Node* _prev, _next;
		private T _payload;

		this(shared T payload) shared {
			_payload = payload;
		}

		@property shared(Node)* prev() => clearLSB(_prev);

		@property shared(Node)* next() => clearLSB(_next);
	}

	private Node _head, _tail;
	enum bottom = clearLSB(cast(shared(Node)*)0xdeadbeafdeadbeaf);
	//  enum bottom = null;

	this() {
		_head._prev = bottom;
		_head._next = &_tail;
		_tail._prev = &_head;
		_tail._next = bottom;
	}

	bool empty() => _head._next == &_tail;

	void pushFront(shared T value) {
		auto newNode = new shared Node(value);
		auto prev = &_head;
		typeof(prev) next;
		do {
			next = prev.next;
			newNode._prev = prev;
			newNode._next = next;
		}
		while (!cas(&prev._next, next, newNode));
		linkPrev(newNode, next);
	}

	void pushBack(shared T value) {
		auto newNode = new shared Node(value);
		auto next = &_tail;
		auto prev = next._prev;
		while (true) {
			newNode._prev = prev;
			newNode._next = next;
			if (cas(&prev._next, next, newNode))
				break;
			if (correctPrev(prev, next))
				prev = clearLSB(next._prev);
		}
		linkPrev(newNode, next);
	}

	@property shared(T)* popFront() {
		auto prev = &_head;
		while (true) {
			auto node = prev._next;
			if (node == &_tail)
				return null;

			auto next = node._next;
			if (hasLSB(next)) {
				setMark(&node._prev);
				cas(&prev._next, node, clearLSB(next));
				continue;
			}

			if (cas(&node._next, next, setLSB(next))) {
				correctPrev(prev, next);
				return &node._payload;
			}
		}
	}

	@property shared(T)* popBack() {
		auto next = &_tail;
		auto node = next._prev;
		while (true) {
			if (node._next != next) {
				if (correctPrev(node, next))
					node = clearLSB(next._prev);
				continue;
			}
			if (node == &_head)
				return null;

			if (cas(&node._next, next, setLSB(next))) {
				correctPrev(clearLSB(node._prev), next);
				return &node._payload;
			}
		}
	}

	bool next(ref shared(Node)* cursor)
	in (!hasLSB(cursor)) {
		while (true) {
			if (cursor == &_tail)
				return false;
			auto next = clearLSB(cursor._next);
			auto d = hasLSB(next._next);
			if (d && cursor._next != setLSB(next)) {
				setMark(&next._prev);
				cas(&cursor._next, next, clearLSB(next._next));
				continue;
			}
			cursor = next;
			if (!d && next != &_tail)
				assert(next != bottom);
			return true;
		}
	}

	bool prev(ref shared(Node)* cursor)
	in (!hasLSB(cursor)) {
		while (true) {
			if (cursor == &_head)
				return false;

			auto prev = clearLSB(cursor._prev);
			if (prev._next == cursor && !hasLSB(cursor._next)) {
				cursor = prev;
				if (prev != &_head)
					return true;
			} else if (hasLSB(cursor._next)) {
				next(cursor);
			} else {
				correctPrev(prev, cursor);
			}
		}
	}

	shared(T)* remove(ref shared(Node)* cursor)
	in (!hasLSB(cursor)) {
		auto node = cursor;
		if (node == &_head || node == &_tail)
			return null;

		while (true) {
			auto next = cursor._next;
			if (hasLSB(next))
				return null;
			if (cas(&node._next, next, setLSB(next))) {
				shared(Node)* prev;
				while (true) {
					prev = node._prev;
					if (hasLSB(prev) || cas(&node._prev, prev, setLSB(prev)))
						break;
				}

				assert(!hasLSB(next));
				correctPrev(clearLSB(prev), next);
				return &node._payload;
			}
		}
	}

	void insertBefore(ref shared(Node)* in_cursor, shared T value)
	in (!hasLSB(in_cursor)) {
		auto cursor = in_cursor;

		if (cursor == &_head)
			return insertAfter(cursor, value);
		auto node = new shared Node(value);
		shared(Node)* next;
		auto prev = clearLSB(cursor._prev);

		while (true) {
			while (hasLSB(cursor._next)) {
				this.next(cursor);
				if (correctPrev(prev, cursor))
					prev = clearLSB(cursor._prev);
			}
			assert(!hasLSB(cursor));
			next = cursor;
			node._prev = prev;
			node._next = next;
			if (cas(&prev._next, next, node))
				break;
			if (correctPrev(prev, cursor))
				prev = clearLSB(cursor._prev);
		}
		cursor = cast(shared)node;
		correctPrev(prev, next);
	}

	void insertAfter(ref shared(Node)* cursor, shared T value)
	in (!hasLSB(cursor)) {
		if (cursor == &_tail)
			return insertBefore(cursor, value);
		auto node = new shared Node(value);
		auto prev = cursor;
		shared(Node)* next;

		while (true) {
			next = clearLSB(prev._next);
			node._next = next;
			node._prev = prev;
			if (cas(&cursor._next, next, node))
				break;

			if (hasLSB(prev._next)) {
				// delete node
				return insertBefore(cursor, value);
			}
		}
		cursor = cast(shared)node;
		correctPrev(prev, next);
	}

private:

	void linkPrev(shared(Node)* node, shared(Node)* next) {
		shared(Node)* link1;
		do {
			link1 = next._prev;
			if (hasLSB(link1) || node._next != next)
				return;
		}
		while (!cas(&next._prev, link1, clearLSB(node)));

		if (hasLSB(node._prev))
			correctPrev(node, next);
	}

	bool correctPrev(shared(Node)* prev, shared(Node)* node) {
		assert(!hasLSB(prev));
		assert(!hasLSB(node));
		assert(prev != bottom);
		assert(node != bottom);

		shared(Node)* lastlink = bottom;
		while (true) {
			//! store link1 for later cas
			auto link1 = node._prev;
			if (hasLSB(node._next))
				return false;
			auto prev2 = prev._next;

			if (hasLSB(prev2)) {
				if (lastlink == bottom) {
					prev = clearLSB(prev._prev);
					//          prev = prev._prev;
				} else {
					setMark(&prev._prev);
					//          assert(!hasLSB(lastlink._next));
					cas(&lastlink._next, prev, clearLSB(prev2));
					prev = lastlink;
					lastlink = bottom;
				}
				continue;
			}

			if (prev2 != node) {
				lastlink = prev;
				prev = prev2;
				continue;
			}

			if (cas(&node._prev, link1, clearLSB(prev))) {
				if (!hasLSB(prev._prev))
					break;
			}
		}
		return true;
	}

	void setMark(shared(Node*)* link) {
		shared(Node)* p;
		do {
			p = *link;
		}
		while (!hasLSB(p) && !cas(link, p, setLSB(p)));
	}
}

/// synchronized implementation
synchronized class SyncedDList(T) {
	struct Node {
		private Node* _prev, _next;
		private union {
			uint sentinel;
			T _payload;
		}

		this(shared T payload) {
			_payload = payload;
		}

		@property shared(Node)* next() shared => _next;

		@property shared(Node)* prev() shared => _prev;
	}

	private Node _head, _tail;
	enum bottom = clearLSB(cast(Node*)0xdeadbeafdeadbeaf);

	this() {
		_head._prev = bottom;
		_head._next = &_tail;
		_head.sentinel = 0xdeadbeef;
		_tail._prev = &_head;
		_tail._next = bottom;
		_tail.sentinel = 0xdeadbeef;
	}

	bool empty() => _head._next == &_tail;

	void pushFront(shared T value) {
		auto newNode = new shared Node(value);
		newNode._next = _head._next;
		newNode._prev = &_head;
		_head._next = newNode;
		newNode._next._prev = newNode;
	}

	void pushBack(shared T value) {
		auto newNode = new shared Node(value);
		newNode._next = &_tail;
		newNode._prev = _tail._prev;
		_tail._prev = newNode;
		newNode._prev._next = newNode;
	}

	@property shared(T)* popFront() {
		if (empty)
			return null;

		shared(Node)* node = _head._next;
		_head._next = node._next;
		node._next._prev = &_head;
		return &node._payload;
	}

	@property shared(T)* popBack() {
		if (empty)
			return null;

		shared(Node)* node = _tail._prev;
		_tail._prev = node._prev;
		node._prev._next = &_tail;
		return &node._payload;
	}

	bool next(ref shared(Node)* cursor) {
		if (cursor == &_tail)
			return false;

		cursor = cursor._next;
		return true;
	}

	bool prev(ref shared(Node)* cursor) {
		if (cursor == &_head)
			return false;

		cursor = cursor._prev;
		return true;
	}

	shared(T)* remove(ref shared(Node)* cursor) {
		if (cursor == &_head || cursor == &_tail)
			return null;

		shared(Node)* node = cursor;
		node._prev._next = node._next;
		node._next._prev = node._prev;
		return &node._payload;
	}

	void insertBefore(ref shared(Node)* cursor, shared T value) {
		if (cursor == &_head)
			return insertAfter(cursor, value);

		auto node = cast(shared)new Node(value);
		node._next = cursor;
		node._prev = cursor._prev;
		cursor._prev._next = node;
		cursor._prev = node;
	}

	void insertAfter(ref shared(Node)* cursor, in T value) {
		if (cursor == &_tail)
			return insertBefore(cursor, value);

		auto node = cast(shared)new Node(value);
		node._prev = cursor;
		node._next = cursor._next;
		cursor._next._prev = node;
		cursor._next = node;
	}
}

private:

// Unit Tests

// dfmt off
version (unittest):
// dfmt on
import core.thread;
import std.stdio;

unittest {
	auto testList = new shared TList();
	testList.pushFront(shared TPayload(0));
	auto cursor = &testList._head;
	testList.next(cursor);
	cursor._next = setLSB(cursor._next);
	cursor._prev = setLSB(cursor._prev);
	testList.insertBefore(cursor, shared TPayload(1));
}

unittest {
	auto testList = new shared(TList)();
	assert(testList._head._next == &testList._tail);
	assert(testList._tail._prev == &testList._head);

	testList.pushFront(shared TPayload(0));
	assert(testList._head._next != &testList._tail);
	assert(testList._tail._prev != &testList._head);
	assert(testList._head._next._next == &testList._tail);
	assert(testList._tail._prev._prev == &testList._head);
	assert(testList._head._next._payload == shared TPayload(0));

	auto pValue = testList.popFront();
	assert(testList._head._next == &testList._tail);
	assert(testList._tail._prev == &testList._head);
	assert(*pValue == shared TPayload(0));
}

struct Heavy {
	this(size_t val) {
		this.val[0] = val;
	}

	size_t[16] val;
}

struct Light {
	size_t val;
}

alias TPayload = Light;
alias TList = shared AtomicDList!TPayload;
//alias SyncedDList!(TPayload) TList;
shared TList sList;
enum amount = 10_000;
enum Position {
	Front,
	Back,
}

void adder(Position Where)() {
	size_t count = amount;
	do {
		static if (Where == Position.Front)
			sList.pushFront(shared TPayload(count));
		else
			sList.pushBack(shared TPayload(count));
	}
	while (--count);
}

void remover(Position Where)() {
	size_t count = amount;
	do {
		static if (Where == Position.Front)
			while (sList.popFront() is null) {
			}
		else
			while (sList.popBack() is null) {
			}
	}
	while (--count);
}

void iterAdder(Position Where)() {
	size_t count = amount;
	static if (Where == Position.Front) {
		do {
			auto cursor = &sList._head;
			do
				sList.insertAfter(cursor, shared TPayload(count));
			while (--count && sList.next(cursor));
		}
		while (count);
	} else {
		do {
			auto cursor = &sList._tail;
			do
				sList.insertBefore(cursor, shared TPayload(count));
			while (--count && sList.prev(cursor));
		}
		while (count);
	}
}

void iterRemover(Position Where)() {
	size_t count = amount;
	static if (Where == Position.Front) {
		do {
			auto cursor = &sList._head;
			do
				sList.next(cursor);
			while (sList.remove(cursor) !is null && --count);
		}
		while (count);
	} else {
		do {
			auto cursor = &sList._tail;
			do
				sList.prev(cursor);
			while (sList.remove(cursor) !is null && --count);
		}
		while (count);
	}
}

void iterator(Position Where)() {
	size_t max_steps;
	size_t times = amount;
	do {
		size_t steps;

		static if (Where == Position.Front) {
			auto cursor = &sList._head;
			while (sList.next(cursor))
				++steps;
			assert(cursor == &sList._tail);
		} else {
			auto cursor = &sList._tail;
			while (sList.prev(cursor))
				++steps;
			assert(cursor == &sList._head);
		}

		max_steps = max(max_steps, steps);
	}
	while (--times);
	writefln("size %s", max_steps);
}

unittest {
	import std.concurrency, std.parallelism : totalCPUs;

	sList = new shared TList();
	size_t count = void;
	shared(TList.Node)* p;

	foreach (i; 0 .. totalCPUs) {
		if (i & 1) {
			spawn(&remover!(Position.Back));
			spawn(&adder!(Position.Front));
			spawn(&iterator!(Position.Back));
		} else {
			spawn(&adder!(Position.Back));
			spawn(&remover!(Position.Front));
			spawn(&iterator!(Position.Front));
		}
	}

	thread_joinAll();
	count = 0;
	p = sList._head.next;
	while (p !is &sList._tail) {
		++count;
		p = p.next;
	}
	writeln("queue empty? -> ", count);
	assert(count == 0);

	foreach (i; 0 .. totalCPUs) {
		if (i & 1) {
			spawn(&iterRemover!(Position.Front));
			spawn(&iterAdder!(Position.Back));
			spawn(&iterator!(Position.Back));
		} else {
			spawn(&iterAdder!(Position.Front));
			spawn(&iterRemover!(Position.Back));
			spawn(&iterator!(Position.Front));
		}
	}

	thread_joinAll();
	count = 0;
	p = sList._head.next;
	while (p !is &sList._tail) {
		++count;
		p = p.next;
	}
	writeln("list empty? -> ", count);
	assert(count == 0);

	foreach (i; 0 .. totalCPUs) {
		if (i & 1) {
			spawn(&iterator!(Position.Back));
			spawn(&iterRemover!(Position.Front));
			spawn(&adder!(Position.Front));
			spawn(&iterAdder!(Position.Front));
			spawn(&remover!(Position.Back));
			spawn(&iterator!(Position.Front));
		} else {
			spawn(&iterator!(Position.Front));
			spawn(&iterAdder!(Position.Back));
			spawn(&remover!(Position.Front));
			spawn(&iterRemover!(Position.Front));
			spawn(&adder!(Position.Back));
			spawn(&iterator!(Position.Front));
		}
	}

	thread_joinAll();
	count = 0;

	for (p = sList._head.next; p !is &sList._tail; p = p.next) {
		++count;
	}
	writeln("mixed empty? -> ", count);
	assert(count == 0);
}
