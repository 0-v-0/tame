module lockfree.rwqueue;

import core.atomic;
import core.bitop : bsr;

/**
 * A Lock-Free Single-Reader, Single-Writer (SRSW) FIFO queue.
 */
struct RWQueue(T, size_t N = roundPow2!(PAGE_SIZE / T.sizeof)) if (T.sizeof) // TODO: Hangs for struct T { double x, y; }, is this a bug or a fundamental limitation?
{
	static assert(N, "Cannot have a capacity of 0.");
	static assert(roundPow2!N == N, "The capacity must be a power of 2");
	enum capacity = N;

	@property size_t length() const => atomicLoad!(MO.acq)(_wpos) - atomicLoad!(MO.acq)(_rpos);

	@property bool empty() const => !length;

	@property bool full() const => length == capacity;

	@property ref front()
	in (!empty) => _data[atomicLoad!(MO.acq)(_rpos) & mask];

	void push(T t)
	in (!full) {
		immutable pos = atomicLoad!(MO.acq)(_wpos);
		_data[pos & mask] = t;
		atomicStore!(MO.rel)(_wpos, pos + 1);
	}

	void push(ref T t)
	in (!full) {
		immutable pos = atomicLoad!(MO.acq)(_wpos);
		_data[pos & mask] = t;
		atomicStore!(MO.rel)(_wpos, pos + 1);
	}

	T pop()
	in (!empty) {
		immutable pos = atomicLoad!(MO.acq)(_rpos);
		auto res = _data[pos & mask];
		atomicStore!(MO.rel)(_rpos, pos + 1);
		return res;
	}

	void clear() {
		atomicStore!(MO.rel)(_wpos, 0);
		atomicStore!(MO.rel)(_rpos, 0);
	}

private:
	enum mask = N - 1;

	size_t _wpos;
	size_t _rpos;
	T[N] _data;
}

private:

alias MO = MemoryOrder;

enum PAGE_SIZE = 4096;

enum roundPow2(size_t v) = v ? size_t(1) << bsr(v) : 0;

unittest {
	static assert(roundPow2!0 == 0);
	static assert(roundPow2!3 == 2);
	static assert(roundPow2!4 == 4);
}

version (unittest) {
	import core.thread, std.concurrency;

	enum amount = 500_000;

	void push(T)(ref RWQueue!T queue) {
		foreach (i; 0 .. amount) {
			while (queue.full)
				Thread.yield();
			queue.push(T(i));
		}
	}

	void pop(T)(ref RWQueue!T queue) {
		foreach (i; 0 .. amount) {
			while (queue.empty)
				Thread.yield();
			assert(queue.pop() == T(i));
		}
	}
}

unittest {
	import std.stdio, std.datetime.stopwatch;

	StopWatch sw;
	sw.start;

	RWQueue!double queue;
	auto t0 = new Thread({ push(queue); }),
	t1 = new Thread({ pop(queue); });
	t0.start();
	t1.start();
	t0.join();
	t1.join();

	sw.stop;
	auto usecs = sw.peek.total!"usecs";
	writeln("Duration: ", usecs, " usecs");
	writeln("Framerate: ", 1e6 * amount / usecs, " frames per second");
}

unittest {
	static struct Data {
		size_t i;
	}

	RWQueue!Data queue;
	auto t0 = new Thread({ push(queue); }),
	t1 = new Thread({ pop(queue); });
	t0.start();
	t1.start();
	t0.join();
	t1.join();
}
