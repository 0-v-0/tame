module tame.windows.charset;

version (Windows):
import core.sys.windows.windows;

version(D_Exceptions):
import std.windows.syserror : WindowsException;

@safe:

private void wenforce(int value, string msg = null,
	string file = __FILE__, size_t line = __LINE__) {
	if (!value)
		throw new WindowsException(GetLastError(), msg, file, line);
}

/++
Converts the UTF-8 string s to ANSI string
Params:
	utf8 = the UTF-8 string to convert
	wide = the buffer to store the wide string
	ansi = the buffer to store the ANSI string
Returns:
	The number of wide characters written to wide, or -1 if wide is too small.
+/
int toANSI(in char[] utf8, scope wchar[] wide, scope char[] ansi) @trusted
in (utf8.length <= int.max, "input string too long") {

	// Convert UTF-8 to wide char
	const wcharCount = MultiByteToWideChar(
		CP_UTF8,
		0,
		utf8.ptr, cast(int)utf8.length,
		null, 0
	);
	wenforce(wcharCount, "MultiByteToWideChar failed");
	if (wide.length < wcharCount)
		return -1;
	MultiByteToWideChar(
		CP_UTF8,
		0,
		utf8.ptr, cast(int)utf8.length,
		wide.ptr, wcharCount
	);

	// Convert wide char to ANSI
	int ansiCount = WideCharToMultiByte(
		CP_ACP,
		0,
		wide.ptr, wcharCount,
		null, 0,
		null, null
	);
	wenforce(ansiCount, "WideCharToMultiByte failed");
	if (ansi.length < ansiCount)
		return -1;
	WideCharToMultiByte(
		CP_ACP,
		0,
		wide.ptr, wcharCount,
		ansi.ptr, ansiCount,
		null, null
	);

	return ansiCount;
}

unittest {
	wchar[256] wide = void;
	char[256] ansi = void;
	assert("abc".toANSI(wide, ansi) == 3);
	assert(ansi[0 .. 3] == "abc");
	assert("中文".toANSI(wide, ansi) >= 4);
}

int toWide(in char[] utf8, scope wchar[] wide) @trusted
in (utf8.length <= int.max, "input string too long") {
	import core.sys.windows.windows;

	// Convert UTF-8 to wide char
	const wideCount = MultiByteToWideChar(
		CP_UTF8,
		0,
		utf8.ptr, cast(int)utf8.length,
		null, 0
	);
	wenforce(wideCount, "MultiByteToWideChar failed");
	if (wide.length < wideCount)
		return -wideCount;
	MultiByteToWideChar(
		CP_UTF8,
		0,
		utf8.ptr, cast(int)utf8.length,
		wide.ptr, wideCount
	);
	return wideCount;
}

/++
Converts the wide string wStr to a UTF-8 string and stores it in utf8.
Params:
	wStr = the wide string to convert
	utf8 = the buffer to store the UTF-8 string
Returns:
	The number of bytes written to utf8, or -1 if utf8 is too small.
+/
int toUTF8(in wchar[] wStr, scope char[] utf8) @trusted
in (wStr.length <= int.max, "input string too long") {
	import core.sys.windows.windows;

	// Convert wide char to UTF-8
	const utf8Count = WideCharToMultiByte(
		CP_UTF8,
		0,
		wStr.ptr, cast(int)wStr.length,
		null, 0,
		null, null
	);
	wenforce(utf8Count, "WideCharToMultiByte failed");
	if (utf8.length < utf8Count)
		return -utf8Count;
	WideCharToMultiByte(
		CP_UTF8,
		0,
		wStr.ptr, cast(int)wStr.length,
		utf8.ptr, utf8Count,
		null, null
	);
	return utf8Count;
}

unittest {
	char[256] utf8 = void;
	assert("abc".toUTF8(utf8) == 3);
	assert(utf8[0 .. 3] == "abc");
	assert("中文".toUTF8(utf8) == 6);
}
