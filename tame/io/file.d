module tame.io.file;

import core.stdc.stdio;
import core.stdc.stdlib;
import tame.unsafe.string;

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
	}

	void reopen(in char[] name, in char[] mode = "rb") {
		handle = .reopen(name, mode, handle);
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

	void seek(long offset, int origin = SEEK_SET) @trusted
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
			import core.sys.posix.stdio : fseeko, off_t;

			alias fseekF = fseeko;
		}
		fseekF(handle, cast(off_t)offset, origin);
	}

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
					return _ftelli64(cast(FILE*)handle);
				else
					return ftell(cast(FILE*)handle);
			} else version (Posix) {
				import core.sys.posix.stdio : ftello;

				return ftello(cast(FILE*)handle);
			}
		}
	}

	@property long size() @trusted
	in (isOpen, "file is not open") {
		long pos = tell;
		seek(0, SEEK_END);
		long size = tell;
		seek(pos, SEEK_SET);
		return size;
	}

package:
	FILE* handle;
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
