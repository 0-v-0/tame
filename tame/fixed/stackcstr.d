module tame.fixed.stackcstr;

version (LDC) {
	pragma(LDC_no_moduleinfo);
}

@safe pure nothrow @nogc:

import core.stdc.string;

/++
A simple C string wrapper that uses a stack-allocated buffer.

The buffer is allocated on the stack, so it's not suitable for very large
strings. The default size is 256 bytes, but you can change that by
specifying a different size in the template parameter.

Params:
maxLen = The maximum length of the string, including the null terminator.

Example:
---
void main() {
	CStr!100 s;
	s ~= "Hello";
	s ~= " world!";
	writeln(s.str);
}
// Output: Hello world!
---
+/
struct CStr(uint maxLen = 256) {
	size_t length;
	private char[maxLen] buf = [0];

	this(char ch) {
		buf[0] = ch;
		length = 1;
	}

	this(in char[] s) @trusted {
		if (s.length) {
			strncpy(buf.ptr, s.ptr, buf.length);
			length = s.length;
		}
	}

	auto opOpAssign(string op : "~")(char ch) {
		buf[length++] = ch;
		return this;
	}

	auto opOpAssign(string op : "~")(in char[] s) @trusted {
		if (s.length) {
			const l = length + s.length + 1 > buf.length ? buf.length - length - 1 : s.length;
			memcpy(buf.ptr + length, s.ptr, l);
			length += l;
		}
		return this;
	}

	@property auto str() inout => buf[0 .. length];
	@property auto strz() {
		buf[length] = '\0';
		return buf[0 .. length + 1];
	}
}

unittest {
	alias S = CStr!100;
	S s = S("Hello");
	s ~= " world!";
	assert(s.str == "Hello world!");
	assert(s.length == 12);
	s.length = 5;
	assert(s.str == "Hello");
	s.length = 0;
	assert(s.str == "");
	s ~= "Hello";
	assert(s.str == "Hello");
	assert(s.strz == "Hello\0");
}
