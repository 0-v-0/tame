module tame.net.error;

public import std.exception;

version (Windows) {
	import core.sys.windows.winsock2;
	import std.windows.syserror;

	package alias errno = WSAGetLastError;
} else version (Posix) {
	import core.sys.posix.netdb;

	package import core.stdc.errno : errno;
}

version (CRuntime_Glibc) version = GNU_STRERROR;
version (CRuntime_UClibc) version = GNU_STRERROR;

@safe:

/// Base exception thrown by `std.socket`.
class SocketException : Exception {
	mixin basicExceptionCtors;
}

/+
Needs to be public so that SocketOSException can be thrown outside of
tame.net (since it uses it as a default argument), but it probably doesn't
need to actually show up in the docs, since there's not really any public
need for it outside of being a default argument.
+/
string formatSocketError(int err) @trusted nothrow {
	import std.conv : to;

	version (Posix) {
		import core.stdc.string;

		char[80] buf;
		version (GNU_STRERROR) {
			const(char)* cs = strerror_r(err, buf.ptr, buf.length);
		} else {
			if (auto errs = strerror_r(err, buf.ptr, buf.length))
				return "Socket error " ~ to!string(err);
			const(char)* cs = buf.ptr;
		}

		auto len = strlen(cs);
		if (cs[len - 1] == '\n')
			len--;
		if (cs[len - 1] == '\r')
			len--;
		return cs[0 .. len].idup;
	} else //version (Windows) {
		//	return generateSysErrorMsg(err);
		//}
		//else
		// TODO: generateSysErrorMsg
		return "Socket error " ~ to!string(err);
}

/++
On POSIX, getaddrinfo uses its own error codes, and thus has its own
formatting function.
+/
string getGaiError(int err) @trusted nothrow {
	import std.string : fromStringz;

	version (Windows) {
		return formatSocketError(err);
	} else
		synchronized
		return cast(string)fromStringz(gai_strerror(err));
}

/// Returns the error message of the most recently encountered network error.
@property string lastSocketError() nothrow
	=> formatSocketError(errno());

pragma(inline, true) void checkError(int err, string msg) {
	import tame.net.socket;

	if (err == SOCKET_ERROR)
		throw new SocketOSException(msg);
}

/// Socket exception representing network errors reported by the operating system.
class SocketOSException : SocketException {
	int errorCode; /// Platform-specific error code.

	alias Formatter = string function(int) nothrow @trusted;

nothrow:
	///
	this(string msg,
		string file = __FILE__,
		size_t line = __LINE__,
		Throwable next = null,
		int err = errno(),
		Formatter errorFormatter = &formatSocketError) {
		errorCode = err;
		super(msg.length ? msg ~ ": " ~ errorFormatter(err) : errorFormatter(err),
			file, line, next);
	}

	///
	this(string msg,
		Throwable next,
		string file = __FILE__,
		size_t line = __LINE__,
		int err = errno(),
		Formatter errorFormatter = &formatSocketError) {
		this(msg, file, line, next, err, errorFormatter);
	}

	///
	this(string msg,
		int err,
		Formatter errorFormatter = &formatSocketError,
		string file = __FILE__,
		size_t line = __LINE__,
		Throwable next = null) {
		this(msg, file, line, next, err, errorFormatter);
	}
}

package template socketOSExceptionCtors() {
nothrow:
	///
	this(string msg, string file = __FILE__, size_t line = __LINE__,
		Throwable next = null, int err = errno()) {
		super(msg, file, line, next, err);
	}

	///
	this(string msg, Throwable next, string file = __FILE__,
		size_t line = __LINE__, int err = errno()) {
		super(msg, next, file, line, err);
	}

	///
	this(string msg, int err, string file = __FILE__, size_t line = __LINE__,
		Throwable next = null) {
		super(msg, next, file, line, err);
	}
}

/// Socket exception representing invalid parameters specified by user code.
class SocketParamException : SocketException {
	mixin basicExceptionCtors;
}

/++
Socket exception representing attempts to use network capabilities not
available on the current system.
+/
class SocketFeatureException : SocketException {
	mixin basicExceptionCtors;
}

version (unittest) package {
	// Print a message on exception instead of failing the unittest.
	void softUnittest(void function() @safe test, int line = __LINE__) @trusted {
		debug (std_socket)
			test();
		else {
			import std.stdio;

			try
				test();
			catch (Throwable e)
				writeln("Ignoring test failure at line ", line, " (likely caused by flaky environment): ", e);
		}
	}

	// Without debug=std_socket, still compile the slow tests, just don't run them.
	debug (std_socket)
		enum runSlowTests = true;
	else
		enum runSlowTests = false;
}
