module tame.string;

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
			if (!p) {
				frontLen = s.length;
				return [];
			}
			frontLen = p - cast(void*)s.ptr + 1;
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
