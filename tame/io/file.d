module tame.io.file;

import core.stdc.stdio;
import core.stdc.stdlib;

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
nothrow:
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

	size_t write(char c) @trusted
	in (isOpen, "file is not open") {
		return fputc(c, handle) != EOF;
	}

	@property @safe pure @nogc {
		bool isOpen() const
			=> handle !is null;

		bool eof() const @trusted
			=> feof(cast(FILE*)handle) != 0;

		bool error() const @trusted
			=> ferror(cast(FILE*)handle) != 0;
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
		return remove(namez) == 0;
	}
}

private:
template TempCStr(alias s, string name = s.stringof ~ "z") {
	import core.stdc.string;

	mixin("auto ", name, "= cast(char*)memcpy(alloca(s.length + 1), s.ptr, s.length);");
	int _ = mixin(name)[s.length] = 0;
}

template TempWCStr(alias s, string name = s.stringof ~ "w") {
	mixin TempCStr!(s, "strz");

	// Find out how many characters there is to convert to UTF-16
	int reqLen = MultiByteToWideChar(CP_UTF8, 0, strz, -1, null, 0);
	mixin("auto ", name, "= cast(wchar*)alloca(reqLen * wchar.sizeof);");
	// Convert to UTF-16
	int _ = MultiByteToWideChar(CP_UTF8, 0, strz, -1, mixin(name), reqLen);
}

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
		return freopen(namez, modez);
	}
}
