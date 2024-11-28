module tame.string;

import tame.text.ascii,
std.ascii : isWhite;
import core.stdc.string : memchr;

pure nothrow @nogc @safe:

struct Splitter(bool keepSeparators = false, S:
	C[], C) if (C.sizeof == 1) {
	S s;
	size_t frontLen;
	C sep;

	this(S input, C separator) {
		s = input;
		sep = separator;
	}

	@property bool empty() const => s.length == 0;

	@property S front() scope @trusted {
		if (!frontLen) {
			const p = memchr(s.ptr, sep, s.length);
			frontLen = p ? p - cast(void*)s.ptr + keepSeparators : s.length;
		}
		return s[0 .. frontLen];
	}

	void popFront() {
		static if (keepSeparators) {
			s = s[frontLen .. $];
		} else {
			s = s[frontLen + (frontLen < s.length) .. $];
		}
		frontLen = 0;
	}
}

auto splitter(bool keepSeparators = false, S, C)(S input, C separator = ' ')
	=> Splitter!(keepSeparators, S)(input, separator);

unittest {
	auto s = splitter("foo");
	assert(!s.empty);
	assert(s.front == "foo");
	s.popFront;
	assert(s.empty);
}

unittest {
	{
		auto s = splitter("foo bar baz");
		assert(s.front == "foo");
		s.popFront;
		assert(s.front == "bar");
		s.popFront;
		assert(s.front == "baz");
		s.popFront;
		assert(s.empty);
	}
	auto s = "foo,bar,baz".splitter(',');
	assert(s.front == "foo");
	s.popFront;
	assert(s.front == "bar");
	s.popFront;
	assert(s.front == "baz");
	s.popFront;
	assert(s.empty);
}

unittest {
	auto s = splitter!true("foo bar baz");
	assert(s.front == "foo ");
	s.popFront;
	assert(s.front == "bar ");
	s.popFront;
	assert(s.front == "baz");
	s.popFront;
	assert(s.empty);
}

bool canFind(in char[] s, char c) @trusted
	=> memchr(s.ptr, c, s.length) !is null;

unittest {
	assert(canFind("foo", 'o'));
	assert(!canFind("foo", 'z'));
}

ptrdiff_t indexOf(in char[] s, char c) @trusted {
	const p = memchr(s.ptr, c, s.length);
	return p ? p - cast(void*)s.ptr : -1;
}

ptrdiff_t indexOf(in char[] s, char c, size_t start) @trusted {
	const p = memchr(s.ptr + start, c, s.length - start);
	return p ? p - cast(void*)s.ptr : -1;
}

unittest {
	assert(indexOf("hello", 'h') == 0);
	assert(indexOf("hello", 'e') == 1);
	assert(indexOf("hello", 'o') == 4);
	assert(indexOf("hello", 'z') == -1);
	assert(indexOf("hello", 'h', 1) == -1);
	assert(indexOf("hello", 'e', 1) == 1);
}

S stripLeft(S)(S input) {
	size_t i;
	for (; i < input.length; ++i) {
		if (!isWhite(input[i]))
			break;
	}
	return input[i .. $];
}

unittest {
	assert(stripLeft(" foo") == "foo");
}

S stripLeft(S)(S input, char c) {
	size_t i;
	for (; i < input.length; ++i) {
		if (input[i] != c)
			break;
	}
	return input[i .. $];
}

unittest {
	assert(stripLeft(" foo") == "foo");
	assert(stripLeft("  foo", ' ') == "foo");
	assert(stripLeft("  foo", 'h') == "  foo");
}

S stripRight(S)(S input) {
	size_t i = input.length;
	for (; i; --i) {
		if (!isWhite(input[i - 1]))
			break;
	}
	return input[0 .. i];
}

unittest {
	assert(stripRight(" foo") == " foo");
	assert(stripRight("foo ") == "foo");
}

S stripRight(S)(S input, char c) {
	size_t i = input.length;
	for (; i; --i) {
		if (input[i - 1] != c)
			break;
	}
	return input[0 .. i];
}

unittest {
	assert(stripRight(" foo") == " foo");
	assert(stripRight("foo ") == "foo");
	assert(stripRight("foo ", ' ') == "foo");
	assert(stripRight("foo ", 'o') == "foo ");
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

unittest {
	assert(strip(" foo") == "foo");
	assert(strip(" foo", ' ') == "foo");
	assert(strip(" foo", 'f') == " foo");
}

bool startsWith(in char[] input, char ch)
	=> input.length && input[0] == ch;

bool startsWith(in char[] input, in char[] prefix)
	=> prefix.length <= input.length &&
	cmp(input[0 .. prefix.length], prefix) == 0;

unittest {
	assert(startsWith("hello", 'h'));
	assert(startsWith("hello", "he"));
	assert(!startsWith("hello", "hi"));
	assert(!startsWith("hello", "hello world"));
	assert(startsWith("hello", ""));
}

bool endsWith(in char[] input, char ch)
	=> input.length && input[$ - 1] == ch;

bool endsWith(in char[] input, in char[] suffix)
	=> suffix.length <= input.length &&
	cmp(input[input.length - suffix.length .. $], suffix) == 0;

unittest {
	assert(endsWith("hello", 'o'));
	assert(endsWith("hello", "lo"));
	assert(!endsWith("hello", "hi"));
	assert(!endsWith("hello", "hello world"));
	assert(endsWith("hello", ""));
}
