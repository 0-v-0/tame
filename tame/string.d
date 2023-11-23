module tame.string;

import tame.ascii,
std.ascii : isWhite;
import core.stdc.string : memchr;

pure nothrow @nogc @safe:

struct Splitter(S : C[], C) if (C.sizeof == 1) {
	S s;
	size_t frontLen;
	C sep;

	this(S input, C separator) {
		s = input;
		sep = separator;
	}

	@property bool empty() const => s.length == 0;

	S front() @trusted {
		if (!frontLen) {
			const p = memchr(s.ptr, ' ', s.length);
			frontLen = p ? p - cast(void*)s.ptr + 1 : s.length;
		}
		return s[0 .. frontLen];
	}

	void popFront() {
		s = s[frontLen .. $];
		frontLen = 0;
	}
}

auto splitter(S, C)(S input, C separator = ' ')
	=> Splitter!S(input, separator);

bool canFind(in char[] s, char c) @trusted
	=> memchr(s.ptr, c, s.length) !is null;

ptrdiff_t indexOf(in char[] s, char c) @trusted {
	const p = memchr(s.ptr, c, s.length);
	return p ? p - cast(void*)s.ptr : -1;
}

S stripLeft(S)(S input) {
	size_t i;
	for (; i < input.length; ++i) {
		if (!isWhite(input[i]))
			break;
	}
	return input[i .. $];
}

S stripLeft(S)(S input, char c) {
	size_t i;
	for (; i < input.length; ++i) {
		if (input[i] != c)
			break;
	}
	return input[i .. $];
}

S stripRight(S)(S input) {
	size_t i = input.length;
	for (; i; --i) {
		if (!isWhite(input[i - 1]))
			break;
	}
	return input[0 .. i];
}

S stripRight(S)(S input, char c) {
	size_t i = input.length;
	for (; i; --i) {
		if (input[i - 1] != c)
			break;
	}
	return input[0 .. i];
}

S strip(S)(S input) {
	size_t i = input.length;
	for (; i; --i) {
		if (!isWhite(input[i - 1]))
			break;
	}
	size_t j;
	for (; j < i; ++j) {
		if (!isWhite(input[j]))
			break;
	}
	return input[j .. i];
}

S strip(S)(S input, char c) {
	size_t i = input.length;
	for (; i; --i) {
		if (input[i - 1] != c)
			break;
	}
	size_t j;
	for (; j < i; ++j) {
		if (input[j] != c)
			break;
	}
	return input[j .. i];
}

bool startsWith(in char[] input, in char[] prefix)
	=> prefix.length <= input.length &&
	compare(input[0 .. prefix.length], prefix) == 0;

bool endsWith(in char[] input, in char[] suffix)
	=> suffix.length <= input.length &&
	compare(input[input.length - suffix.length .. $], suffix) == 0;
