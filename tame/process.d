module tame.process;

import core.stdc.signal : SIGTERM;
import std.datetime : Duration;
public import std.process : ProcessException;
import tame.io.file;
import tame.string;

version (Posix) {
	import core.stdc.errno;
	import core.sys.posix.sys.wait;
	import core.sys.posix.unistd;
}
version (Windows) {
	import core.sys.windows.windows;
}

/++
	Flag options.
	Use bitwise OR to combine flags.
+/
enum Flags {
	none = 0,

	/++
		By default, the child process inherits the parent's environment,
		and any environment variables passed to `spawnProcess` will
		be added to it.  If this flag is set, the only variables in the
		child process' environment will be those given to spawnProcess.
		+/
	newEnv = 1,

	/++
		Unless the child process inherits the standard input/output/error
		streams of its parent, one almost always wants the streams closed
		in the parent when `spawnProcess` returns.  Therefore, by
		default, this is done.  If this is not desirable, pass any of these
		options to spawnProcess.
		+/
	retainStdin = 2,
	retainStdout = 4, /// ditto
	retainStderr = 8, /// ditto

	/++
		On Windows, if the child process is a console application, this
		flag will prevent the creation of a console window.  Otherwise,
		it will be ignored. On POSIX, `suppressConsole` has no effect.
		+/
	suppressConsole = 16,

	/++
		On POSIX, open [file descriptors](http://en.wikipedia.org/wiki/File_descriptor)
		are by default inherited by the child process.  As this may lead
		to subtle bugs when pipes or multiple threads are involved,
		`spawnProcess` ensures that all file descriptors except the
		ones that correspond to standard input/output/error are closed
		in the child process when it starts.  Use `inheritFDs` to prevent
		this.

		On Windows, this option has no effect, and any handles which have been
		explicitly marked as inheritable will always be inherited by the child
		process.
		+/
	inheritFDs = 32,

	/++
		Spawn process in detached state. This removes the need in calling
		`wait` to clean up the process resources.

		Note:
		Calling `wait` or `kill` with the resulting `Pid` is invalid.
		+/
	detached = 64,
}
/// Status codes for Pipe.close()
enum CloseStatus {
	ok,
	readEndError = 1,
	writeEndError = 2,
	bothEndsError = readEndError | writeEndError,
}

/++
	Represents a unidirectional pipe with read and write ends.
+/
struct Pipe {
	private File read, write;

	@property @safe pure nothrow @nogc {
		/// The read end of the pipe.
		File readEnd() => read;
		/// The write end of the pipe.
		File writeEnd() => write;
	}

	/**
	 * Closes both ends of the pipe.
	 * Returns: a bitwise OR of `CloseStatus` flags indicating
	 * whether closing either end failed.
	 */
	CloseStatus close() {
		CloseStatus s;
		if (!read.close())
			s |= CloseStatus.readEndError;
		if (!write.close())
			s |= CloseStatus.writeEndError;
		return s;
	}
}

version (Windows) {
	Pipe pipe() @trusted {
		HANDLE r = void, w = void;
		if (!CreatePipe(&r, &w, null, 0))
			throw ProcessException.newFromLastError("Failed to create pipe");

		return Pipe(File(r, "rb"), File(w, "wb"));
	}

	auto startProcess(in char[] program, in char[] cmd,
		File stdin = File(),
		File stdout = File(),
		File stderr = File(),
		Flags flags = Flags.none) {
		import tame.buffer;
		static import io = tame.io.stdio;
		import tame.unsafe.string;

		StringSink sink;
		if (program.canFind(' ')) {
			sink ~= '"';
			sink ~= program;
			sink ~= '"';
		} else
			sink ~= program;
		sink ~= ' ';
		sink ~= cmd;
		sink ~= '\0';
		auto cmdz = sink[].ptr;
		mixin TempWStr!program;
		mixin TempWStr!(cmdz, "cmdw");

		STARTUPINFOW si;
		//auto si = startInfo(stdin, stdout, stderr);
		PROCESS_INFORMATION pi = void;
		if (!CreateProcess(program.length ? programw : null, cmdw,
				null, null, true, CREATE_UNICODE_ENVIRONMENT | (
				(flags & Flags.suppressConsole) ? CREATE_NO_WINDOW : 0), null, null, &si, &pi))
			throw ProcessException.newFromLastError(
				"Failed to spawn process " ~ cast(string)fromStringz(program));

		version (testProc) {
			if (!(flags & Flags.retainStdin) && stdin !is io.stdin)
				stdin.close();
			if (!(flags & Flags.retainStdout) && stdout !is io.stdout)
				stdout.close();
			if (!(flags & Flags.retainStderr) && stderr !is io.stderr)
				stderr.close();
		}

		CloseHandle(pi.hThread);
		version (testProc)
			if (flags & Flags.detached) {
				CloseHandle(pi.hProcess);
				pi.hProcess = INVALID_HANDLE_VALUE;
			}
		return Pid(pi.dwProcessId, pi.hProcess);
	}
}

/// Represents a process ID and its associated resources.
struct Pid {
	/// Special values for _pid.
	enum invalid = -1, terminated = -2;
	version (Windows)
		HANDLE _handle;
	else version (Posix)
		pid_t _handle;
	/++
	Whether the process can be waited for by wait() for or killed by kill().
    False if process was started as detached. True otherwise.
	+/
	bool owned;

	version (Windows)  ~this() {
		if (_handle != INVALID_HANDLE_VALUE) {
			CloseHandle(_handle);
			_handle = INVALID_HANDLE_VALUE;
		}
	}

	bool tryWait() @safe {
		performWait(false);
		return _pid == terminated;
	}

private:
	version (Windows) {
		this(int pid, HANDLE handle)
		in (pid >= 0, "Invalid process ID") {
			_pid = pid;
			_handle = handle;
			owned = handle != INVALID_HANDLE_VALUE;
		}
	} else {
		this(int pid, bool own)
		in (pid >= 0, "Invalid process ID") {
			_pid = pid;
			_handle = pid;
			owned = own;
		}
	}

	/// The process ID.
	int _pid;
	/+
    Pid.performWait() does the dirty work for wait() and nonBlockingWait().

    If block == true, this function blocks until the process terminates,
    sets _pid to terminated, and returns the exit code or terminating
    signal as described in the wait() documentation.

    If block == false, this function returns immediately, regardless
    of the status of the process.  If the process has terminated, the
    function has the exact same effect as the blocking version.  If not,
    it returns 0 and does not modify _pid.
    +/
	version (Posix)
		int performWait(bool block) @trusted {
		import std.exception : enforce;

		enforce!ProcessException(owned, "Can't wait on a detached process");
		int exitCode;
		while (true) {
			int status;
			auto check = waitpid(_pid, &status, block ? 0 : WNOHANG);
			if (check == -1) {
				if (errno == ECHILD) {
					throw new ProcessException(
						"Process does not exist or is not a child process.");
				} else {
					// waitpid() was interrupted by a signal.  We simply
					// restart it.
					assert(errno == EINTR);
					continue;
				}
			}
			if (!block && check == 0)
				return 0;
			if (WIFEXITED(status)) {
				exitCode = WEXITSTATUS(status);
				break;
			}
			if (WIFSIGNALED(status)) {
				exitCode = -WTERMSIG(status);
				break;
			}
			// We check again whether the call should be blocking,
			// since we don't care about other status changes besides
			// "exited" and "terminated by signal".
			if (!block)
				return 0;

			// Process has stopped, but not terminated, so we continue waiting.
		}
		// Mark Pid as terminated, and cache and return exit code.
		_pid = terminated;
		return exitCode;
	} else version (Windows) {
		int performWait(bool block, uint timeout = INFINITE) @trusted {
			import std.exception : enforce;

			enforce!ProcessException(owned, "Can't wait on a detached process");
			assert(_handle != INVALID_HANDLE_VALUE,
				"Invalid process handle in Pid.performWait");
			if (block) {
				const result = WaitForSingleObject(_handle, timeout);
				if (result != WAIT_OBJECT_0) {
					// Wait time exceeded `timeout` milliseconds?
					if (result == WAIT_TIMEOUT && timeout != INFINITE)
						return 0;

					throw ProcessException.newFromLastError("Wait failed.");
				}
			}
			uint _exitCode;
			if (!GetExitCodeProcess(_handle, cast(LPDWORD)&_exitCode))
				throw ProcessException.newFromLastError();
			if (!block && _exitCode == STILL_ACTIVE)
				return 0;
			CloseHandle(_handle);
			_handle = INVALID_HANDLE_VALUE;
			_pid = terminated;
			return _exitCode;
		}

		int performWait(Duration timeout) @safe {
			import std.exception : enforce;

			const ms = timeout.total!"msecs";

			// Limit this implementation the maximum wait time offered by
			// WaitForSingleObject. One could theoretically break up larger
			// durations into multiple waits but (DWORD.max - 1).msecs
			// (> 7 weeks, 17 hours) should be enough for the usual case.
			// DWORD.max is reserved for INFINITE
			enforce!ProcessException(ms < DWORD.max, "Timeout exceeds maximum wait time!");
			return performWait(true, cast(DWORD)ms);
		}
	}
}

void kill(Pid pid, int codeOrSignal = SIGTERM)
in (codeOrSignal >= 0, "Signal must be non-negative") {
	import std.exception : enforce;

	enforce!ProcessException(pid.owned, "Can't kill detached process");
	version (Windows) {
		// On Windows, TerminateProcess() appears to terminate the
		// *current* process if it is passed an invalid handle...
		if (pid._handle == INVALID_HANDLE_VALUE)
			throw new ProcessException("Invalid process handle");
		if (!TerminateProcess(pid._handle, codeOrSignal))
			throw ProcessException.newFromLastError();
	} else version (Posix) {
		import core.sys.posix.signal : kill;

		if (kill(pid._handle, codeOrSignal) == -1)
			throw ProcessException.newFromErrno();
	}
}

version (testProc) :
private:

// Extract file descriptors and HANDLEs from the streams and make the
// handles inheritable.
auto prepareHandle(in File file, DWORD stdHandle, string which) {
	enum _NO_CONSOLE_FILENO = cast(HANDLE)-2;
	auto handle = file.toHandle();
	// Windows GUI applications have a fd but not a valid Windows HANDLE.
	if (!isValid(handle) || handle == _NO_CONSOLE_FILENO)
		handle = GetStdHandle(stdHandle);

	DWORD dwFlags = void;
	if (GetHandleInformation(handle, &dwFlags)) {
		if (!(dwFlags & HANDLE_FLAG_INHERIT)) {
			if (!SetHandleInformation(handle,
					HANDLE_FLAG_INHERIT,
					HANDLE_FLAG_INHERIT)) {
				throw ProcessException.newFromLastError(
					"Failed to make " ~ which ~ " stream inheritable by child process");
			}
		}
	}
	return handle;
}

auto startInfo(in File stdin, in File stdout, in File stderr) {
	STARTUPINFOW si;
	//si.cb = si.sizeof;
	si.hStdInput = prepareHandle(stdin, STD_INPUT_HANDLE, "stdin");
	si.hStdOutput = prepareHandle(stdout, STD_OUTPUT_HANDLE, "stdout");
	si.hStdError = prepareHandle(stderr, STD_ERROR_HANDLE, "stderr");
	si.dwFlags = isValid(si.hStdInput) || isValid(si.hStdOutput) || isValid(si.hStdError) ?
STARTF_USESTDHANDLES : 0;
	return si;
}

auto isValid(in HANDLE h) => h && h != INVALID_HANDLE_VALUE;
