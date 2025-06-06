module tame.string;

import core.stdc.string : memchr;
import tame.text.ascii,
std.ascii : isWhite;

pure nothrow @nogc @safe:

version (D_BetterC) {
	import std.traits;

	inout(Char)[] fromStringz(Char)(return scope inout(Char)* cString) @system
	if (isSomeChar!Char) {
		import core.stdc.stddef : wchar_t;

		static if (is(immutable Char == immutable char))
			import core.stdc.string : cstrlen = strlen;
		else static if (is(immutable Char == immutable wchar_t))
			import core.stdc.wchar_ : cstrlen = wcslen;
		else
			static size_t cstrlen(scope const Char* s) {
				const(Char)* p = s;
				while (*p)
					++p;
				return p - s;
			}

		return cString ? cString[0 .. cstrlen(cString)] : null;
	}
} else
	public import std.string : fromStringz;

struct Splitter(bool keepSeparators = false, S:
	C[], C) if (C.sizeof == 1) {
	S s;
	private size_t frontLen;
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

bool canFind(in char[] s, char c) @trusted {
	if (__ctfe) {
		foreach (ch; s) {
			if (ch == c)
				return true;
		}
		return false;
	}
	return memchr(s.ptr, c, s.length) !is null;
}

unittest {
	assert(canFind("foo", 'o'));
	assert(!canFind("foo", 'z'));
	assert(!canFind("", 'z'));
	static assert(canFind("foo", 'o'));
	static assert(!canFind("foo", 'z'));
}

ptrdiff_t indexOf(in char[] s, char c) @trusted {
	if (__ctfe) {
		foreach (i, ch; s) {
			if (ch == c)
				return i;
		}
		return -1;
	}
	const p = memchr(s.ptr, c, s.length);
	return p ? p - cast(void*)s.ptr : -1;
}

/++
Params:
	s = string to search
	c = character to search for
	start = the index into s to start searching from
Returns:
	the index of the first occurrence of c in s, or -1 if not found
+/
ptrdiff_t indexOf(in char[] s, char c, size_t start) @trusted {
	if (__ctfe) {
		foreach (i, ch; s[start .. $]) {
			if (ch == c)
				return i + start;
		}
		return -1;
	}
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
	static assert(indexOf("hello", 'h') == 0);
	static assert(indexOf("hello", 'e') == 1);
	static assert(indexOf("hello", 'h', 1) == -1);
	static assert(indexOf("hello", 'e', 1) == 1);
}

ptrdiff_t lastIndexOf(in char[] s, char c) {
	foreach_reverse (i, ch; s) {
		if (ch == c)
			return i;
	}
	return -1;
}

/++
Params:
	s = string to search
	c = character to search for
	start = the index into s to start searching from
Returns:
	the index of the last occurrence of c in s, or -1 if not found
+/
ptrdiff_t lastIndexOf(in char[] s, char c, size_t start) {
	return start <= s.length ? lastIndexOf(s[0 .. start], c) : -1;
}

unittest {
	assert(lastIndexOf("hello", 'h') == 0);
	assert(lastIndexOf("hello", 'e') == 1);
	assert(lastIndexOf("hello", 'o') == 4);
	assert(lastIndexOf("hello", 'z') == -1);
	assert(lastIndexOf("hello", 'o', 5) == 4);
	assert(lastIndexOf("hello", 'o', 2) == -1);
	static assert(lastIndexOf("hello", 'h') == 0);
	static assert(lastIndexOf("hello", 'e') == 1);
	static assert(lastIndexOf("hello", 'o', 5) == 4);
	static assert(lastIndexOf("hello", 'o', 2) == -1);
}

auto stripLeft(S)(S input) {
	size_t i;
	for (; i < input.length; ++i) {
		if (!isWhite(input[i]))
			break;
	}
	return input[i .. $];
}

unittest {
	assert(stripLeft(" foo") == "foo");
	static assert(stripLeft(" foo") == "foo");
}

auto stripLeft(S)(S input, char c) {
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
	static assert(stripLeft(" foo") == "foo");
}

auto stripRight(S)(S input) {
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

auto stripRight(S)(S input, char c) {
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

auto strip(S)(S input) {
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

auto strip(S)(S input, char c) {
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
