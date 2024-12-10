module tame.format.util;

import std.meta,
std.traits;

version (D_BetterC) {
	/// pseudosink used just for calculation of resulting string length
	struct NullSink {
	}
} else {
	public import std.range : NullSink;
}

@safe:

/// Returns string of enum member value
string enumToStr(E)(E value) if (is(E == enum)) {
	switch (value) {
		static foreach (i, e; NoDuplicates!(EnumMembers!E)) {
	case e:
			return __traits(allMembers, E)[i];
		}
	default:
	}
	return null;
}

package:

template isTyp(T, U) {
	version (D_BetterC)
		enum isTyp = false;
	else
		enum isTyp = is(T == U);
}

auto toChar(char base = 'a')(uint i)
	=> cast(char)(i <= 9 ? '0' ^ i : base + i - 10);

/// Output range wrapper for used sinks (so it can be used in toString functions)
struct SinkWrap(S) {
	private S s;

	static if (isArray!S && is(ForeachType!S : char))
		mixin SinkWriter!(S, false);
	else static if (isPointer!S)
		mixin SinkWriter!(PointerTarget!S, false);
	else
		static assert(0, "Unsupported sink type: " ~ S.stringof);

	this(S sink) pure nothrow @nogc {
		s = sink;
	}
}

// helper to create `SinkWrap` that handles various sink types
auto sinkWrap(S)(auto ref scope S sink) @trusted { // we're only using this internally and don't escape the pointer
	static if (isArray!S && is(ForeachType!S : char))
		return SinkWrap!(char[])(sink[]);
	else static if (is(S == struct))
		return SinkWrap!(S*)(&sink); // work with a pointer to an original sink (ie `MallocBuffer`)
	else
		static assert(0, "Unsupported sink type: " ~ S.stringof);
}

@"sink wrapper"@nogc unittest {
	char[32] buf;
	auto sink = sinkWrap(buf);
	sink.put("foo");
	assert(sink.totalLen == 3);
	assert(buf[0 .. 3] == "foo");
}

// helper functions used in formatters to write formatted string to sink
template SinkWriter(S, bool field = true) {
	uint totalLen;
	static if (isArray!S && is(ForeachType!S : char)) {
		static if (field)
			char[] s = sink[];

		@nogc pure nothrow @safe {
			void advance(uint len) {
				s = s[len .. $];
				totalLen += len;
			}

			void put(const(char)[] str) {
				s[0 .. str.length] = str;
				advance(cast(uint)str.length);
			}

			void put(char ch) {
				s[0] = ch;
				advance(1);
			}
		}
	} else {
		static if (field)
			alias s = sink;

		void advance(uint len) @nogc pure nothrow @safe {
			totalLen += len;
		}

		static if (is(S == NullSink)) {
		@nogc pure nothrow @safe:

			void put(in char[] str) {
				advance(cast(uint)str.length);
			}

			void put(char) {
				advance(1);
			}
		} else {
			import std.range : rput = put;

			void put(in char[] str) {
				rput(s, str);
				advance(cast(uint)str.length);
			}

			void put(char ch) {
				rput(s, ch);
				advance(1);
			}
		}
	}
}
