module lockfree.rwqueue;

import core.atomic;
import core.bitop : bsr;

/**
 * A Lock-Free Single-Reader, Single-Writer (SRSW) FIFO queue.
 */
shared struct RWQueue(T, size_t capacity = roundPow2!(PAGE_SIZE / T.sizeof))
if (T.sizeof) // TODO: Hangs for struct T { double x, y; }, is this a bug or a fundamental limitation?
{
	static assert(capacity, "Cannot have a capacity of 0.");
	static assert(roundPow2!capacity == capacity, "The capacity must be a power of 2");

	@property size_t length() shared const => atomicLoad!(MemoryOrder.acq)(_wpos) - atomicLoad!(
		MemoryOrder.acq)(_rpos);

	@property bool empty() shared const => !length;

	@property bool full() const => length == capacity;

	void push(shared in T t)
	in (!full) {
		immutable pos = atomicLoad!(MemoryOrder.acq)(_wpos);
		_data[pos & mask] = t;
		atomicStore!(MemoryOrder.rel)(_wpos, pos + 1);
	}

	shared(T) pop()
	in (!empty) {
		immutable pos = atomicLoad!(MemoryOrder.acq)(_rpos);
		auto res = _data[pos & mask];
		atomicStore!(MemoryOrder.rel)(_rpos, pos + 1);
		return res;
	}

private:
	//    import std.algorithm; // move

	enum mask = capacity - 1;

	size_t _wpos;
	size_t _rpos;
	T[capacity] _data;
}

private:

enum PAGE_SIZE = 4096;

enum roundPow2(size_t v) = v ? cast(size_t)1 << bsr(v) : 0;

unittest {
	static assert(roundPow2!0 == 0);
	static assert(roundPow2!3 == 2);
	static assert(roundPow2!4 == 4);
}

version (unittest) {
	import core.thread, std.concurrency;

	enum amount = 500_000;

	void push(T)(ref shared(RWQueue!T) queue) {
		foreach (i; 0 .. amount) {
			while (queue.full)
				Thread.yield();
			queue.push(shared T(i));
		}
	}

	void pop(T)(ref shared(RWQueue!T) queue) {
		foreach (i; 0 .. amount) {
			while (queue.empty)
				Thread.yield();
			assert(queue.pop() == shared T(i));
		}
	}
}

unittest {
	import std.stdio, std.datetime.stopwatch;

	StopWatch sw;
	sw.start;

	shared(RWQueue!double) queue;
	auto t0 = new Thread({ push(queue); }),
	t1 = new Thread({ pop(queue); });
	t0.start();
	t1.start();
	t0.join();
	t1.join();

	sw.stop;
	writeln("Duration: ", sw.peek.total!"usecs", " microseconds");
	writeln("Framerate: ", 1e6 / sw.peek.total!"usecs", " frames per second");
}

unittest {
	static struct Data {
		size_t i;
	}

	shared(RWQueue!Data) queue;
	auto t0 = new Thread({ push(queue); }),
	t1 = new Thread({ pop(queue); });
	t0.start();
	t1.start();
	t0.join();
	t1.join();
}
