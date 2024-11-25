module tame.fixed.queue;

import std.algorithm : swap;

@safe pure nothrow @nogc:

/// Fixed-size queue.
struct Queue(T, uint N = 16) {
	enum capacity = N;

	T[N] data;
	uint head;
	uint tail;

	void push(T value)
	in (!full, "Queue is full") {

		data[tail++] = value;
		tail %= N;
	}

	T pop()
	in (!empty, "Queue is empty") {
		auto value = data[head++];
		head %= N;
		return value;
	}

	@property {
		bool empty() const => head == tail;
		bool full() const => (tail + 1) % N == head;
		ref front() => data[head];
	}
}

unittest {
	Queue!int q;
	assert(q.empty);
	q.push(1);
	assert(!q.empty);
	q.push(2);
	assert(q.pop() == 1);
	assert(q.pop() == 2);
}

struct PriorityQueue(T, uint N = 16) {
	enum capacity = N;
	T[N] data;
	uint size;

	@property {
		bool empty() const => size == 0;
		bool full() const => size == N;

		ref front() => data[0];
	}

	void push(T value)
	in (!full, "Queue is full") {
		data[size] = value;
		for (size_t i = size; i;) {
			auto parent = (i - 1) / 2;
			if (data[i] >= data[parent])
				break;
			swap(data[i], data[parent]);
			i = parent;
		}
		size++;
	}

	T pop()
	in (!empty, "Queue is empty") {
		auto value = data[0];
		data[0] = data[--size];
		for (size_t i;;) {
			auto left = 2 * i + 1;
			if (left >= size)
				break;
			auto right = 2 * (i + 1);
			auto next = i;
			if (data[left] < data[next])
				next = left;
			if (right < size && data[right] < data[next])
				next = right;
			if (next == i)
				break;
			swap(data[i], data[next]);
			i = next;
		}
		return value;
	}
}

unittest {
	PriorityQueue!int q;
	assert(q.empty);
	q.push(2);
	assert(q.front == 2);
	q.push(1);
	assert(q.pop() == 1);
	assert(q.pop() == 2);
	PriorityQueue!(int, 2) r;
	r.push(1);
	r.push(2);
	assert(r.full);
}
