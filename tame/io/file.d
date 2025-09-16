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

	/++
		Detaches the file handle, closing the file if this is the last reference.
		Returns: true if the file was closed, false otherwise.
	+/
	bool detach() {
		if (isOpen && atomicOp!"-="(refs, 1) == 0) {
			close();
			return true;
		}
		return false;
	}

	/++
		Closes the file handle if it is open.
		Returns: true if the file was successfully closed, false otherwise.
	+/
	bool close() {
		bool r = true;
		if (isOpen) {
			r = fclose(handle) == 0;
			handle = null;
		}
		return r;
	}

	/++
		Reads up to `buffer.length` bytes from the file into `buffer`.
		Returns: a slice of `buffer` containing the bytes that were read.
	+/
	void[] read(void[] buffer) @trusted
	in (isOpen, "file is not open") {
		const n = fread(buffer.ptr, 1, buffer.length, handle);
		assert(n <= buffer.length);
		return buffer[0 .. n];
	}

	/++
		Writes the contents of `buffer` to the file.
		Returns: the number of bytes that were written.
	+/
	size_t write(in void[] buffer) @trusted
	in (isOpen, "file is not open") {
		return fwrite(buffer.ptr, 1, buffer.length, handle);
	}

	/++
		Writes the contents of `buffer` to the file, followed by a newline character.
		Returns: the number of bytes that were written.
	+/
	size_t writeln(in char[] buffer) @trusted
	in (isOpen, "file is not open") {
		return write(buffer) + write('\n');
	}

	/++
		Writes a single character to the file.
		Returns: whether the write was successful.
	+/
	size_t write(char c) @trusted
	in (isOpen, "file is not open") {
		return fputc(c, handle) != EOF;
	}

	alias put = write;

	/++
		Flushes the file's output buffer.
		Returns: whether the flush was successful.
	+/
	bool flush() @trusted
	in (isOpen, "file is not open") {
		return fflush(handle) == 0;
	}

	/++
		Rewinds the file to the beginning.
	+/
	void rewind() @trusted
	in (isOpen, "file is not open") {
		.rewind(handle);
	}

	/++
		Synchronizes the file's in-core state with the storage device.
		Returns: whether the sync was successful.
	+/
	bool sync() @trusted {
		version (Windows) {
			import core.sys.windows.winbase : FlushFileBuffers;

			return FlushFileBuffers(toHandle) != 0;
		} else version (Darwin) {
			import core.sys.darwin.fcntl : F_FULLFSYNC, fcntl;

			return fcntl(fileno, F_FULLFSYNC, 0) != -1;
		} else {
			import core.sys.posix.unistd : fsync;

			return fsync(fileno) == 0;
		}
	}

	/++
		Seeks to a new position in the file.
		Params:
			offset = the offset to seek to, in bytes
			origin = the reference point for the offset (SEEK_SET, SEEK_CUR, or SEEK_END)
		Returns: whether the seek was successful.
	+/
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

	/++
		Clears the end-of-file and error indicators for the file.
	+/
	void clearerr() @safe pure nothrow {
		isOpen && .clearerr(handle);
	}

	/++
		Returns a range that reads the file line by line.
		Params:
			terminator = the line terminator character (default: '\n')
			keepTerminator = whether to include the terminator in the lines (default: false)
	+/
	auto byLine(char terminator = '\n', bool keepTerminator = false)
		=> ByTerminator!1024(this, terminator, keepTerminator);

	@property @safe const {
		/// Returns: whether the file is open.
		bool isOpen() pure
			=> handle !is null;

		/// Returns: whether the file is at end-of-file.
		bool eof() @trusted pure
		in (isOpen, "file is not open")
			=> feof(cast(FILE*)handle) != 0;

		/// Returns: whether the file has encountered an error.
		bool error() @trusted pure
		in (isOpen, "file is not open")
			=> ferror(cast(FILE*)handle) != 0;

		/// Get the current position in the file.
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

		/++
			Get the underlying file descriptor.
			Requires: the file is open.
		+/
		int fileno() @trusted
		in (isOpen, "file is not open") {
			return .fileno(cast(FILE*)handle);
		}

		/++
			Get the underlying OS file handle.
			If the file is not open, returns null.
		+/
		version (Windows) auto toHandle() @trusted {
			import core.stdc.stdio : _get_osfhandle;

			return isOpen ? cast(HANDLE)_get_osfhandle(fileno) : null;
		}
	}

	/++
		Get the underlying C FILE* pointer.
		Requires: the file is open.
	+/
	@property FILE* getFP() @safe pure
	in (isOpen, "file is not open") {
		return handle;
	}

	/// Returns the size of the file in bytes, or -1 if the file is not open.
	@property long size() @trusted {
		if (!isOpen)
			return -1;

		const pos = tell;
		seek(0, SEEK_END);
		const size = tell;
		seek(pos, SEEK_SET);
		return size;
	}

package:
	FILE* handle;
	shared size_t refs;
}

/++
    Returns: whether a file exists at the specified path
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
Returns:
	the size of the file in bytes, or 0 if the file does not exist
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

///
@safe unittest {
	// assert(".".getSize > 0);
	assert("this file does not exist".getSize == 0);
}

/++
	Get the attributes of a file.
Params:
	name = the file name
Returns:
	On Windows, the file attributes (see GetFileAttributesW).
	On Posix, the file mode (see stat).
	If the file does not exist, returns INVALID_FILE_ATTRIBUTES on Windows and 0 on Posix
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
