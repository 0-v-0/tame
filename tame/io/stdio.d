module tame.io.stdio;

import c = core.stdc.stdio,
tame.format,
tame.io.file;

// Undocumented but public because the std* handles are aliasing it.
@property ref File makeGlobal(alias fd)() {
	__gshared File file;

	enum N = uint.max / 2;
	// Use an inline spinlock to make sure the initializer is only run once.
	// We assume there will be at most N threads trying to initialize
	// `handle` at once and steal the high bit to indicate that the globals have
	// been initialized.
	static shared uint spinlock;
	import core.atomic : atomicLoad, atomicOp, MemoryOrder;

	if (atomicLoad!(MemoryOrder.acq)(spinlock) <= N) {
		for (;;) {
			if (atomicLoad!(MemoryOrder.acq)(spinlock) > N)
				break;
			if (atomicOp!"+="(spinlock, 1) == 1) {
				file.handle = fd;
				atomicOp!"+="(spinlock, N);
				break;
			}
			atomicOp!"-="(spinlock, 1);
		}
	}
	return file;
}

/** The standard input stream.

	Returns:
		stdin as a $(LREF File).

	Note:
		The returned $(LREF File) wraps $(REF stdin,core,stdc,stdio), and
		is therefore thread global. Reassigning `stdin` to a different
		`File` must be done in a single-threaded or locked context in
		order to avoid race conditions.

		All reading from `stdin` automatically locks the file globally,
		and will cause all other threads calling `read` to wait until
		the lock is released.
*/
alias stdin = makeGlobal!(c.stdin);

/**
	The standard output stream.

	Returns:
		stdout as a $(LREF File).

	Note:
		The returned $(LREF File) wraps $(REF stdout,core,stdc,stdio), and
		is therefore thread global. Reassigning `stdout` to a different
		`File` must be done in a single-threaded or locked context in
		order to avoid race conditions.

		All writing to `stdout` automatically locks the file globally,
		and will cause all other threads calling `write` to wait until
		the lock is released.
*/
alias stdout = makeGlobal!(c.stdout);

/**
	The standard error stream.

	Returns:
		stderr as a $(LREF File).

	Note:
		The returned $(LREF File) wraps $(REF stderr,core,stdc,stdio), and
		is therefore thread global. Reassigning `stderr` to a different
		`File` must be done in a single-threaded or locked context in
		order to avoid race conditions.

		All writing to `stderr` automatically locks the file globally,
		and will cause all other threads calling `write` to wait until
		the lock is released.
*/
alias stderr = makeGlobal!(c.stderr);

size_t write(T...)(auto ref T args) @trusted if (!is(T[0] : File)) {
	size_t len;
	foreach (i, arg; args)
		static if (is(T[i] : const(void)[]))
			len += stdout.write(arg);
		else
			len += stdout.write(text(arg));
	return len;
}

size_t writeln(T...)(auto ref T args) @trusted if (!is(T[0] : File)) {
	const len = write(args);
	return len + stdout.write('\n');
}
