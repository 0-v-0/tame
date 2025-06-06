module tame.io.file;

import core.atomic,
core.stdc.stdio,
core.stdc.stdlib,
tame.unsafe.string;

version (Windows) {
	// fopen expects file names to be
	// encoded in CP_ACP on Windows instead of UTF-8.
	private extern (C) nothrow @nogc {
		FILE* _wfopen(scope const wchar* filename, scope const wchar* mode);
		FILE* _wfreopen(scope const wchar* filename, scope const wchar* mode, FILE* fp);
	}

	import core.sys.windows.core;
} else version (Posix) {
	import core.sys.posix.sys.stat;
} else
	static assert(0, "Unsupported platform");

struct File {
nothrow @nogc:
	this(in char[] name, in char[] mode = "rb") {
		handle = open(name, mode);
		atomicStore(refs, isOpen);
	}

	this(int fd, in char[] mode = "rb") {
		version (CRuntime_Microsoft) {
			alias fdopen = _fdopen;
		} else version (Posix) {
			import core.sys.posix.stdio : fdopen;
		}
		mixin TempCStr!mode;

		handle = fdopen(fd, modez);
		atomicStore(refs, isOpen);
	}

	version (Windows) {
		this(HANDLE h, in char[] mode = "rb") {
			// Create file descriptors from the handles
			const fd = _open_osfhandle(cast(INT_PTR)h, toFlags(mode));
			this(fd, mode);
		}

		private static int toFlags(in char[] mode) {
			int m;
			// dfmt off
			modeLoop: foreach (c; mode)
				switch (c) {
					case 'r': m |= _O_RDONLY; break;
					case '+': m &=~_O_RDONLY; break;
					case 'a': m |= _O_APPEND; break;
					case 'b': m |= _O_BINARY; break;
					case 't': m |= _O_TEXT;   break;
					case ',': break modeLoop;
					default:
				}
			// dfmt on
			return m;
		}
	}

	void reopen(in char[] name, in char[] mode = "rb") {
		handle = .reopen(name, mode, handle);
	}

	~this() {
		detach();
	}

	this(this) @safe pure {
		if (isOpen) {
			assert(atomicLoad(refs));
			atomicOp!"+="(refs, 1);
		}
	}

	void detach() {
		if (isOpen && atomicOp!"-="(refs, 1) == 0)
			close();
	}

	void close() {
		if (isOpen) {
			fclose(handle);
			handle = null;
		}
	}

	void[] read(void[] buffer) @trusted
	in (isOpen, "file is not open") {
		const n = fread(buffer.ptr, 1, buffer.length, handle);
		assert(n <= buffer.length);
		return buffer[0 .. n];
	}

	size_t write(in void[] buffer) @trusted
	in (isOpen, "file is not open") {
		return fwrite(buffer.ptr, 1, buffer.length, handle);
	}

	size_t writeln(in char[] buffer) @trusted
	in (isOpen, "file is not open") {
		return write(buffer) + write('\n');
	}

	size_t write(char c) @trusted
	in (isOpen, "file is not open") {
		return fputc(c, handle) != EOF;
	}

	alias put = write;

	bool flush() @trusted
	in (isOpen, "file is not open") {
		return fflush(handle) == 0;
	}

	void rewind() @trusted
	in (isOpen, "file is not open") {
		.rewind(handle);
	}

	bool sync() @trusted {
		version (Windows) {
			import core.sys.windows.winbase : FlushFileBuffers;

			return FlushFileBuffers(toHandle) != 0;
		} else version (Darwin) {
			import core.sys.darwin.fcntl : fcntl, F_FULLFSYNC;

			return fcntl(fileno, F_FULLFSYNC, 0) != -1;
		} else {
			import core.sys.posix.unistd : fsync;

			return fsync(fileno) == 0;
		}
	}

	bool seek(long offset, int origin = SEEK_SET) @trusted
	in (isOpen, "file is not open") {
		version (Windows) {
			version (CRuntime_Microsoft) {
				alias fseekF = _fseeki64;
				alias off_t = long;
			} else {
				alias fseekF = fseek;
				alias off_t = int;
			}
		} else version (Posix) {
			import core.sys.posix.stdio : fseekF = fseeko, off_t;
		}
		return fseekF(handle, cast(off_t)offset, origin) == 0;
	}

	void clearerr() @safe pure nothrow {
		isOpen && .clearerr(handle);
	}

	auto byLine(char terminator = '\n', bool keepTerminator = false)
		=> ByTerminator!1024(this, terminator, keepTerminator);

	@property @safe const {
		bool isOpen() pure
			=> handle !is null;

		bool eof() @trusted pure
		in (isOpen, "file is not open")
			=> feof(cast(FILE*)handle) != 0;

		bool error() @trusted pure
		in (isOpen, "file is not open")
			=> ferror(cast(FILE*)handle) != 0;

		long tell() @trusted
		in (isOpen, "file is not open") {
			version (Windows) {
				version (CRuntime_Microsoft)
					alias ftellF = _ftelli64;
				else
					alias ftellF = ftell;
			} else version (Posix) {
				import core.sys.posix.stdio : ftellF = ftello;
			}
			return ftellF(cast(FILE*)handle);
		}

		int fileno() @trusted
		in (isOpen, "file is not open") {
			return .fileno(cast(FILE*)handle);
		}

		version (Windows) auto toHandle() @trusted {
			import core.stdc.stdio : _get_osfhandle;

			return isOpen ? cast(HANDLE)_get_osfhandle(fileno) : null;
		}
	}

	@property FILE* getFP() @safe pure
	in (isOpen, "file is not open") {
		return handle;
	}

	@property long size() @trusted {
		if (!isOpen)
			return -1;

		long pos = tell;
		seek(0, SEEK_END);
		long size = tell;
		seek(pos, SEEK_SET);
		return size;
	}

package:
	FILE* handle;
	shared size_t refs;
}

/++
    Checks whether a file exists at the specified path
+/
bool exists(in char[] name) @trusted nothrow @nogc {
	version (Windows) {
		return getAttributes(name) != INVALID_FILE_ATTRIBUTES;
	} else version (Posix) {
		return getAttributes(name) != 0;
	}
}

///
@safe unittest {
	assert(".".exists);
	assert(!"this file does not exist".exists);
}

/++
	Get size of file `name` in bytes.
Params:
	name = the file name
+/
ulong getSize(in char[] name) @trusted nothrow @nogc {
	version (Windows) {
		mixin TempWCStr!name;

		WIN32_FILE_ATTRIBUTE_DATA data = void;
		if (!GetFileAttributesExW(namew, GET_FILEEX_INFO_LEVELS.GetFileExInfoStandard, &data))
			return 0;
		return (cast(ulong)data.nFileSizeHigh << 32) | data.nFileSizeLow;
	} else version (Posix) {
		mixin TempCStr!name;
		stat_t statbuf = void;
		if (lstat(namez, &statbuf) != 0)
			return 0;
		return statbuf.st_size;
	}
}

/++
	Get the attributes of a file.
Params:
	name = the file name
+/
uint getAttributes(in char[] name) @trusted nothrow @nogc {
	version (Windows) {
		mixin TempWCStr!name;

		return GetFileAttributesW(namew);
	} else version (Posix) {
		mixin TempCStr!name;
		stat_t statbuf = void;
		if (lstat(namez, &statbuf))
			return 0;
		return statbuf.st_mode;
	}
}

bool remove(in char[] name) @trusted nothrow @nogc {
	version (Windows) {
		mixin TempWCStr!name;
		return DeleteFileW(namew) != 0;
	} else version (Posix) {
		mixin TempCStr!name;
		return core.stdc.stdio.remove(namez) == 0;
	}
}

struct ByTerminator(uint N = 1024) {
nothrow @nogc:
	private File f;
	char[N] buf = void;
	char[] data;
	private size_t frontLen;
	char terminator;
	bool keepTerminator;

	this(ref File file, char term, bool keepTerm = false) @safe {
		f = file;
		terminator = term;
		keepTerminator = keepTerm;
	}

	@disable this(this);

	void read() @trusted {
		import core.stdc.string : memchr;

		if (!frontLen && file.isOpen) {
			data = cast(char[])f.read(buf);
			if (data.length) {
				const p = memchr(data.ptr, terminator, data.length);
				frontLen = p ? p - cast(void*)data.ptr + keepTerminator : data.length;
			}
		}
	}

	@property auto file() pure => f;

	@property bool empty() @trusted {
		read();
		return data.length == 0;
	}

	@property auto front() @trusted
		=> data[0 .. frontLen];

	void popFront() {
		if (keepTerminator) {
			data = data[frontLen .. $];
		} else {
			data = data[frontLen + (frontLen < data.length) .. $];
		}
		frontLen = 0;
	}
}

private:

auto open(in char[] name, in char[] mode) @trusted {
	version (Windows) {
		mixin TempWCStr!name;
		mixin TempWCStr!mode;

		return _wfopen(namew, modew);
	} else version (Posix) {
		/*
		 * The new opengroup large file support API is transparently
		 * included in the normal C bindings. http://opengroup.org/platform/lfs.html#1.0
		 * if _FILE_OFFSET_BITS in druntime is 64, off_t is 64 bit and
		 * the normal functions work fine. If not, then large file support
		 * probably isn't available. Do not use the old transitional API
		 * (the native extern(C) fopen64, http://www.unix.org/version2/whatsnew/lfs20mar.html#3.0)
		 */
		import core.sys.posix.stdio : fopen;

		mixin TempCStr!name;
		mixin TempCStr!mode;
		return fopen(namez, modez);
	}
}

auto reopen(in char[] name, in char[] mode, FILE* fp) @trusted {
	version (Windows) {
		mixin TempWCStr!name;
		mixin TempWCStr!mode;

		return _wfreopen(namew, modew, fp);
	} else version (Posix) {
		import core.sys.posix.stdio : freopen;

		mixin TempCStr!name;
		mixin TempCStr!mode;
		return freopen(namez, modez, fp);
	}
}
