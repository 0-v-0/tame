/++
@nogc formatting utilities

Inspired by: https://github.com/weka-io/mecca/blob/master/src/mecca/lib/string.d

Sink Types:
various functions in this module use "sinks" which are buffers or objects that get filled with
the formatting data while the format functions are running. The following sink types are
supported to be passed into these arguments:
- Arrays (`isArray!S && is(ForeachType!S : char))`)
- $(LREF NullSink)
- Object with `put(const(char)[])` and `put(char)` functions

Passing in arrays will make the sink `@nogc pure nothrow @safe` as everything will be written
into that memory. Passing in arrays that are too short to hold all the data will trigger a
`RangeError` or terminate the program in betterC.

Passing in a $(LREF NullSink) instance will not allocate any memory and just count the bytes that
will be allocated.

Otherwise any type that contains a `put` method that can be called both with `const(char)[]` and
with `char` arguments can be used.
+/
module tame.format;

import std.algorithm : max, min;
import std.datetime.date : TimeOfDay;
import std.meta,
std.range,
tame.buffer,
tame.builtins,
tame.format.spec,
tame.util;
import std.string : fromStringz;
import std.traits;
import std.typecons : Flag, Tuple, isTuple;
public import tame.format.util;

version (D_BetterC) {
} else {
	import core.time : Duration;
	import std.datetime.systime : SysTime;
	import std.utf : byUTF;
	import std.uuid : UUID;
}

@safe:

version (unittest) {
	void test(alias f, T)(T input, string expected) {
		char[64] buf;
		const len = f(buf, input);
		assert(buf[0 .. len] == expected);
	}
}

/++
Formats values to with fmt template into provided sink.
Note: it supports only a basic subset of format type specifiers, main usage is for nogc logging
and error messages formatting. But more cases can be added as needed.

WARN: %s accepts pointer to some char assuming it's a zero terminated string

Params:
	fmt  = The format string, much like in std.format
	sink = The sink where the full string should be written to, see section "Sink Types"
	args = The arguments to fill the format string with

Returns: the length of the formatted string.
+/
uint formatTo(string fmt = "%s", S, A...)(ref scope S sink, auto ref scope A args) {
	// TODO: not pure because of float formatter
	alias sfmt = splitFmt!fmt;
	static assert(sfmt.numFormatters == A.length, "Expected " ~ sfmt.numFormatters.stringof ~
			" arguments, got " ~ A.length.stringof);

	mixin SinkWriter!S;

	foreach (t; sfmt.tokens) {
		// pragma(msg, "t: ", t);
		static if (is(typeof(t) == string)) {
			static if (t.length)
				put(t);
		} else {
			enum j = t.i;
			alias T = Unqual!(A[j]);
			enum N = T.stringof;
			static if (is(typeof(t) == ArrFmtSpec)) {
				static assert(
					__traits(compiles, ForeachType!T), "Expected foreach type range instead of "
						~ N);
				static assert(!is(S == NullSink) || isArray!T || isForwardRange!T,
					"Don't determine format output length with range argument " ~ N ~ " it'd be consumed.");
				static if (!is(S == NullSink) && !isArray!T && !isForwardRange!T)
					pragma(msg, "WARN: Argument of type " ~ N ~ " would be consumed during format");

				static if (t.del.length)
					bool first = true;
				static if (!isArray!T && isForwardRange!T)
					enum r = "args[j].save()";
				else
					enum r = "args[j]";
				foreach (ref e; mixin(r)) {
					static if (t.del.length) {
						if (unlikely(first))
							first = false;
						else
							put(t.del);
					}
					advance(s.formatTo!(t.fmt)(e));
				}
			} else static if (is(typeof(t) == FmtSpec)) {
				enum f = t.type;
				alias v = args[j];

				static if (isStdNullable!T) {
					if (v.isNull)
						put("null");
					else
						advance(s.formatTo(v.get));
				} else static if (f == FMT.STR) {
					static if (is(typeof(v[]) : const(char)[]))
						put(v[]);
					else static if (isInputRange!T && isSomeChar!(ElementEncodingType!T)) {
						foreach (c; v.byUTF!char)
							put(c);
					} else static if (is(T == bool))
						put(v ? "true" : "false");
					else static if (is(T == enum)) {
						auto tmp = enumToStr(v);
						if (unlikely(tmp is null))
							advance(s.formatTo!(N ~ "(%d)")(v));
						else
							put(tmp);
					} else static if (is(UUID) && is(T == UUID))
						advance(s.formatValue(v));
					else static if (is(SysTime) && is(T == SysTime))
						advance(s.formatValue(v));
					else static if (is(T == TimeOfDay))
						advance(s.formatTo!"%02d:%02d:%02d"(v.hour, v.minute, v.second));
					else static if (is(Duration) && is(T == Duration))
						advance(s.formatValue(v));
					else static if (isArray!T || isInputRange!T) {
						if (v.empty)
							put("[]");
						else
							advance(s.formatTo!"[%(%s%|, %)]"(v));
					} else static if (is(T == U*, U)) {
						static if (isSomeChar!U) {
							// NOTE: not safe, we can only trust that the provided char pointer is really stringz
							() @trusted { advance(s.formatTo(fromStringz(v))); }();
						} else
							advance(s.formatValue(v));
					} else static if (is(T == char))
						put(v);
					else static if (isSomeChar!T) {
						foreach (c; (()@trusted => (&v)[0 .. 1])().byUTF!char)
							put(c);
					} else static if (is(T : ulong))
						advance(s.formatDecimal(v));
					else static if (isTuple!T) {
						put("Tuple(");
						foreach (i, _; T.Types) {
							static if (T.fieldNames[i] == "")
								put(i ? ", " : "");
							else
								put((i ? ", " : "") ~ T.fieldNames[i] ~ "=");
							advance(s.formatTo(v[i]));
						}
						put(')');
					} else static if (is(T : Throwable)) {
						// HACK: Error: more than one mutable reference of `__param_1`
						const c = v;
						advance(s.formatTo!"%s@%s(%d): %s"(
								T.stringof, c.file, c.line, c.msg));
					} else static if (is(typeof(v[])))
						advance(s.formatTo(v[])); // sliceable values
					else static if (is(T == struct)) {
						static if (__traits(compiles, (val)@nogc {
								auto sw = sinkWrap(s);
								val.toString(sw);
							}(v))) {
							// we can use custom defined toString
							auto sw = sinkWrap(s);
							v.toString(sw);
							advance(sw.totalLen);
						} else {
							static if (hasMember!(T, "toString"))
								pragma(msg, N ~ " has toString defined, but can't be used with nFormat");
							put(N ~ "(");
							alias Names = FieldNameTuple!T;
							foreach (i, field; v.tupleof) {
								put((i == 0 ? "" : ", ") ~ Names[i] ~ "=");
								advance(s.formatTo(field));
							}
							put(')');
						}
					} else static if (is(T : double))
						advance(s.formatTo!"%g"(v));
					else
						static assert(0, "Unsupported value type for string format: " ~ N);
				} else static if (f == FMT.CHR) {
					static assert(is(T : char), "Requested char format, but provided: " ~ N);
					write(v);
				} else static if (f == FMT.DEC) {
					static assert(is(T : ulong), "Requested decimal format, but provided: " ~ N);
					enum fs = formatSpec(f, t.def);
					advance(s.formatDecimal!(fs.width, fs.fill)(v));
				} else static if (f == FMT.HEX || f == FMT.UHEX) {
					static assert(is(T : ulong) || isPointer!T, "Requested hex format, but provided: " ~ N);
					enum u = f == FMT.HEX ? Upper.yes : Upper.no;
					enum fs = formatSpec(f, t.def);
					static if (isPointer!T)
						advance(s.formatHex!(fs.width, fs.fill, u)(cast(size_t)v));
					else
						advance(s.formatHex!(fs.width, fs.fill, u)(v));
				} else static if (f == FMT.PTR) {
					static assert(is(T : ulong) || isPointer!T, "Requested pointer format, but provided: " ~ N);
					() @trusted { advance(s.formatValue(cast(void*)v)); }();
				} else static if (f == FMT.FLT) {
					static assert(is(T : double), "Requested float format, but provided: " ~ N);
					advance(s.formatValue(v));
				}
			} else
				static assert(0);
		}
	}

	return totalLen;
}

///
@"combined"@nogc unittest {
	char[64] buf;
	ubyte[3] data = [1, 2, 3];
	assert(formatTo!"hello %s %s %% world %d %x %p"(buf, data, "moshe", -567, 7, 7) == 53);
	assert(buf[0 .. 53] == "hello [1, 2, 3] moshe % world -567 7 0000000000000007");
}

@system StringSink globalSink;

/++
	Same as `formatTo`, but it internally uses static malloc buffer to write formatted string to.
	So be careful that next call replaces internal buffer data and previous result isn't valid anymore.
+/
const(char)[] nFormat(string fmt = "%s", A...)(auto ref scope A args) @trusted {
	globalSink.clear();
	formatTo!fmt(globalSink, args);
	return cast(const(char)[])globalSink.data;
}

///
@"formatters"unittest {
	import std.algorithm : filter;
	import std.range : chunks;

	assert(nFormat!"abcd abcd" == "abcd abcd");
	assert(nFormat!"123456789a" == "123456789a");
	version (D_NoBoundsChecks) {
	} else version (D_Exceptions) {
		() @trusted {
			import core.exception : RangeError;
			import std.exception : assertThrown;

			char[5] buf = void;
			assertThrown!RangeError(buf.formatTo!"123412341234");
		}();
	}

	// literal escape
	assert(nFormat!"123 %%" == "123 %");
	assert(nFormat!"%%%%" == "%%");

	// %d
	assert(nFormat!"%d"(1234) == "1234");
	assert(nFormat!"%4d"(42) == "  42");
	assert(nFormat!"%04d"(42) == "0042");
	assert(nFormat!"%04d"(-42) == "-042");
	assert(nFormat!"ab%dcd"(1234) == "ab1234cd");
	assert(nFormat!"ab%d%d"(1234, 56) == "ab123456");

	// %x
	assert(nFormat!"0x%x"(0x1234) == "0x1234");

	// %p
	assert(nFormat!"%p"(0x1234) == "0000000000001234");

	// %s
	assert(nFormat!"12345%s"("12345") == "1234512345");
	assert(nFormat!"123%s"(123) == "123123");
	assert(nFormat!"12345%s"(FMT.HEX) == "12345HEX");
	char[4] str = "foo\0";
	assert((() => nFormat(str.ptr))() == "foo");

	static if (is(UUID))
		assert(nFormat(
				UUID([
				138, 179, 6, 14, 44, 186, 79, 35, 183, 76, 181, 45, 179, 189,
				251, 70
	])) == "8ab3060e-2cba-4f23-b74c-b52db3bdfb46");

	// array format
	int[10] arr = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

	assert(nFormat!"foo %(%d %)"(arr[1 .. 4]) == "foo 1 2 3");
	assert(nFormat!"foo %-(%d %)"(arr[1 .. 4]) == "foo 1 2 3");
	assert(nFormat!"foo %(-%d-%|, %)"(arr[1 .. 4]) == "foo -1-, -2-, -3-");
	assert(nFormat!"%(0x%02x %)"(arr[1 .. 4]) == "0x01 0x02 0x03");
	// BUG: cannot call Chunks.save() on const range
	assert(nFormat!"%(%(%d %)\n%)"(arr[1 .. $].chunks(3)) == "1 2 3\n4 5 6\n7 8 9");

	// range format
	auto r = arr[].filter!(a => a < 5);
	assert(nFormat!"%s"(r) == "[0, 1, 2, 3, 4]");

	// Arg num
	assert(!__traits(compiles, nFormat!"abc"(5)));
	assert(!__traits(compiles, nFormat!"%d"()));
	assert(!__traits(compiles, nFormat!"%d a %d"(5)));

	// Format error
	assert(!__traits(compiles, nFormat!"%"()));
	assert(!__traits(compiles, nFormat!"abcd%d %"(15)));
	assert(!__traits(compiles, nFormat!"%$"(1)));
	assert(!__traits(compiles, nFormat!"%d"("hello")));
	assert(!__traits(compiles, nFormat!"%x"("hello")));

	assert(nFormat!"Hello %s"(5) == "Hello 5");

	struct Foo {
		int x, y;
	}

	assert(nFormat!"Hello %s"(Foo(1, 2)) == "Hello Foo(x=1, y=2)");

	version (D_BetterC) {
		struct Nullable(T) { // can't be instanciated in betterC - fake just for the UT
			T get() => T.init;

			bool isNull() => true;

			void nullify() {
			}
		}
	} else
		import std.typecons : Nullable;

	struct Msg {
		Nullable!string foo;
	}

	assert(nFormat(Msg.init) == "Msg(foo=null)");

	StringSink s = "abcd";
	assert(nFormat(s) == "abcd");
}

///
@"tuple"unittest {
	{
		alias T = Tuple!(int, "foo", bool);
		T t = T(42, true);
		assert(nFormat(t) == "Tuple(foo=42, true)");
	}

	alias T = Tuple!(int, "foo", string, "bar", char, "baz");
	T t = T(42, "bar", 'z');
	assert(nFormat(t) == "Tuple(foo=42, bar=bar, baz=z)");
}

///
@"custom format"unittest {
	static struct Custom {
		int foo = 42;
		void toString(S)(ref S sink) const {
			sink.put("custom: ");
			sink.formatTo!"foo=%d"(foo);
		}
	}

	Custom c;
	enum result = "custom: foo=42";
	assert(nFormat(c) == result);
	assert(getFormatSize(c) == result.length);

	char[64] buf;
	auto l = buf.formatTo(c);
	assert(buf[0 .. l] == result);
}

string text(T...)(auto ref T args) @trusted
if (T.length) {
	if (__ctfe) {
		StringSink s;
		foreach (ref arg; args)
			formatTo(s, arg);
		return cast(string)s[];
	}
	globalSink.clear();
	foreach (ref arg; args)
		formatTo(globalSink, arg);
	return cast(string)globalSink[];
}

///
unittest {
	assert(text(42, ' ', 1.5, ": xyz") == "42 1.5: xyz");
	char[4] str = "foo\0";
	assert((() @trusted => text(str.ptr))() == "foo");
	static assert(text(42, ' ', 1.5, ": xyz") == "42 1.5: xyz");
}

unittest {
	char c = 'h';
	wchar w = '你';
	dchar d = 'እ';

	assert(text(c, "ello", ' ', w, "好 ", d, "ው ሰላም ነው") == "hello 你好 እው ሰላም ነው");

	string cs = "今日は";
	wstring ws = "여보세요";
	dstring ds = "Здравствуйте";

	assert(text(cs, ' ', ws, " ", ds) == "今日は 여보세요 Здравствуйте");
}

/// Gets size needed to hold formatted string result
uint getFormatSize(string fmt = "%s", A...)(auto ref A args) nothrow @nogc {
	NullSink ns;
	return ns.formatTo!fmt(args);
}

@"getFormatSize"unittest {
	assert(getFormatSize!"foo" == 3);
	assert(getFormatSize!"foo=%d"(42) == 6);
	assert(getFormatSize!"%04d-%02d-%02dT%02d:%02d:%02d.%03d"(2020, 4, 28, 19, 20, 32, 207) == 23);
	assert(getFormatSize!"%x"(0x2C38) == 4);
	assert(getFormatSize!"%s"(9896) == 4);
}

uint formatValue(S)(ref scope S sink, in void* p) @trusted {
	mixin SinkWriter!S;
	if (p)
		return sink.formatHex!((void*).sizeof * 2)(cast(size_t)p);

	put("null");
	return 4;
}

@"pointer"@nogc @trusted unittest {
	alias test = .test!(formatValue, void*);
	test(cast(void*)0x123, "0000000000000123");
	test(cast(void*)0, "null");
	test(null, "null");
}

alias Upper = Flag!"Upper";

pure nothrow @nogc
uint formatHex(uint W = 0, char fill = '0', Upper upper = Upper.no, S)(
	ref scope S sink, ulong val) {
	import core.bitop : bsr;

	static if (is(S == NullSink)) {
		// just formatted length calculation
		uint len = val ? bsr(val) / 4 + 1 : 1;
		return max(W, len);
	} else {
		mixin SinkWriter!S;

		uint len = val ? bsr(val) / 4 + 1 : 1;
		char[16] buf = void;

		static if (W) {
			if (len < W) {
				buf[0 .. W - len] = '0';
				len = W;
			}
		}

		auto i = len;
		do
			buf[--i] = toChar!(upper ? 'A' : 'a')(val & 0xF);
		while (val >>= 4);
		put(buf[0 .. len]);
		return len;
	}
}

@"hexadecimal"@nogc unittest {
	alias test = .test!(formatHex, ulong);
	test(0x123, "123");
	test(0x1234567890, "1234567890");
	test(0x1234567890abcdef, "1234567890abcdef");
	test(0, "0");
	alias test2 = .test!(formatHex!(10, '0', Upper.no, char[64]), ulong);
	test2(0x123, "0000000123");
	test2(0, "0000000000");
	test2(0xa23456789, "0a23456789");
	test2(0x1234567890, "1234567890");
	alias test3 = .test!(formatHex!(10, '0', Upper.yes, char[64]), ulong);
	test3(0x123, "0000000123");
	test3(0x1234567890a, "1234567890A");
}

uint formatDecimal(uint W = 0, char fillChar = ' ', S, T:
	ulong)(ref scope S sink, T val) {
	import std.ascii : isWhite;

	static if (is(isBoolean!T))
		uint len = 1;
	else
		uint len = numDigits(val);

	static if (is(S == NullSink)) {
		// just formatted length calculation
		return max(W, len);
	} else {
		mixin SinkWriter!S;

		char[20] buf = void; // max number of digits for 8bit numbers is 20
		uint i;
		ulong v = void;

		static if (isSigned!T) {
			if (unlikely(val < 0)) {
				if (unlikely(val == long.min)) {
					// special case for unconvertable value
					put("-9223372036854775808");
					return 20;
				}

				static if (!isWhite(fillChar))
					buf[i++] = '-'; // to write minus character after padding
				v = -long(val);
			} else
				v = val;
		} else
			v = val;

		static if (W) {
			if (len < W) {
				buf[i .. i + W - len] = fillChar;
				i += W - len;
				len = W;
			}
		}

		static if (isSigned!T && isWhite(fillChar))
			if (val < 0)
				buf[i++] = '-';

		i = len;
		do
			buf[--i] = cast(char)('0' ^ v % 10);
		while (v /= 10);
		put(buf[0 .. len]);
		return len;
	}
}

@"decimal"@nogc unittest {
	alias test = .test!(formatDecimal, int);
	test(1234, "1234");
	test(-1234, "-1234");
	test(0, "0");
	test(1, "1");
	char[32] buf;
	assert(buf.formatDecimal!10(-1234) && buf[0 .. 10] == "     -1234");
	assert(buf.formatDecimal!10(0) && buf[0 .. 10] == "         0");
	assert(buf.formatDecimal!3(1234) && buf[0 .. 4] == "1234");
	assert(buf.formatDecimal!3(-1234) && buf[0 .. 5] == "-1234");
	assert(buf.formatDecimal!3(0) && buf[0 .. 3] == "  0");
	assert(buf.formatDecimal!(3, '0')(0) && buf[0 .. 3] == "000");
	assert(buf.formatDecimal!(3, 'a')(0) && buf[0 .. 3] == "aa0");
	assert(buf.formatDecimal!(10, '0')(-1234) && buf[0 .. 10] == "-000001234");
	assert(buf.formatDecimal(true) == 1 && buf[0 .. 1] == "1");
}

uint formatValue(S)(ref scope S sink, double val) @trusted {
	if (__ctfe) {
		mixin SinkWriter!S;
		if (val != val) {
			put("nan");
			return 3;
		}
		uint len;
		if (val < 0) {
			put('-');
			len++;
			val = -val;
		}
		if (val == double.infinity) {
			put("inf");
			return len + 3;
		}
		const intPart = cast(long)val;
		auto fracPart = val - intPart;
		len += sink.formatDecimal(intPart);
		if (fracPart > 0) {
			put('.');
			len++;
			do {
				fracPart *= 10;
				const digit = cast(long)fracPart;
				put(cast(char)('0' + digit));
				len++;
				fracPart -= digit;
			}
			while (fracPart > 0);
		}
		return len;
	}
	import core.stdc.stdio : snprintf;

	char[20] buf = void;
	auto len = min(snprintf(&buf[0], 20, "%g", val), 19);
	static if (!is(S == NullSink)) {
		mixin SinkWriter!S;
		put(buf[0 .. len]);
	}
	return len;
}

@"float"unittest {
	alias test = .test!(formatValue, double);
	test(1.2345, "1.2345");
	test(double.init, "nan");
	test(double.infinity, "inf");
}

version (D_BetterC) {
} else:

	uint formatValue(S)(ref scope S sink, UUID val) {
	static if (!is(S == NullSink)) {
		mixin SinkWriter!S;

		alias skipSeq = AliasSeq!(8, 13, 18, 23);
		alias byteSeq = AliasSeq!(0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34);

		char[36] buf = void;

		foreach (pos; skipSeq)
			buf[pos] = '-';

		foreach (i, pos; byteSeq) {
			buf[pos] = toChar(val.data[i] >> 4);
			buf[pos + 1] = toChar(val.data[i] & 0x0F);
		}

		put(buf[0 .. 36]);
	}
	return 36;
}

@"UUID"unittest {
	char[42] buf;
	assert(buf.formatValue(UUID([
		138, 179, 6, 14, 44, 186, 79, 35, 183, 76, 181, 45, 179, 189, 251,
		70
	])) == 36);
	assert(buf[0 .. 36] == "8ab3060e-2cba-4f23-b74c-b52db3bdfb46");
}

/++
	Formats SysTime as ISO extended string.
	Only UTC format supported.
+/
uint formatValue(S)(ref scope S sink, SysTime val) @trusted {
	mixin SinkWriter!S;

	// Note: we don't format based on the timezone set in SysTime, but just use UTC here
	enum hnsecsToUnixEpoch = 621_355_968_000_000_000L;
	enum hnsecsFrom1601 = 504_911_232_000_000_000L;

	enum invalidTimeBuf = "invalid";

	long time = __traits(getMember, val, "_stdTime"); // access private field
	long hnsecs = time % 10_000_000;

	// check for invalid time value
	version (Windows) {
		if (time < hnsecsFrom1601) {
			put(invalidTimeBuf);
			return invalidTimeBuf.length;
		}
	}

	static if (is(S == NullSink)) {
		// just count required number of characters needed for hnsecs
		int len = 20; // fixed part for date time with just seconds resolution (including 'Z')
		if (hnsecs == 0)
			return len; // no fract seconds part
		len += 2; // dot and at least one number
		foreach (i; [1_000_000, 100_000, 10_000, 1_000, 100, 10]) {
			hnsecs %= i;
			if (hnsecs == 0)
				break;
			len++;
		}
		return len;
	} else {
		char[28] buf; // maximal length for UTC extended ISO string

		version (Posix) {
			import core.sys.posix.sys.types : time_t;
			import core.sys.posix.time : gmtime_r, tm;

			time -= hnsecsToUnixEpoch; // convert to unix time but still with hnsecs

			// split to hnsecs and time in seconds
			time_t unixTime = time / 10_000_000;

			tm timeSplit;
			gmtime_r(&unixTime, &timeSplit);

			buf.formatTo!"%04d-%02d-%02dT%02d:%02d:%02d"(
				timeSplit.tm_year + 1900,
				timeSplit.tm_mon + 1,
				timeSplit.tm_mday,
				timeSplit.tm_hour,
				timeSplit.tm_min,
				timeSplit.tm_sec
			);
		} else version (Windows) {
			import core.sys.windows.winbase : FILETIME, FileTimeToSystemTime, SYSTEMTIME;
			import core.sys.windows.winnt : ULARGE_INTEGER;

			ULARGE_INTEGER ul;
			ul.QuadPart = cast(ulong)time - hnsecsFrom1601;

			FILETIME ft;
			ft.dwHighDateTime = ul.HighPart;
			ft.dwLowDateTime = ul.LowPart;

			SYSTEMTIME stime;
			FileTimeToSystemTime(&ft, &stime);

			buf.formatTo!"%04d-%02d-%02dT%02d:%02d:%02d"(
				stime.wYear,
				stime.wMonth,
				stime.wDay,
				stime.wHour,
				stime.wMinute,
				stime.wSecond
			);
		} else
			static assert(0, "SysTime format not supported for this platform yet");

		if (hnsecs == 0) {
			buf[19] = 'Z';
			put(buf[0 .. 20]);
			return 20;
		}

		buf[19] = '.';

		int len = 20;
		foreach (i; [1_000_000, 100_000, 10_000, 1_000, 100, 10, 1]) {
			buf[len++] = cast(char)(hnsecs / i + '0');
			hnsecs %= i;
			if (hnsecs == 0)
				break;
		}
		buf[len++] = 'Z';
		put(buf[0 .. len]);
		return len;
	}
}

@"SysTime"unittest {
	char[32] buf;
	alias parse = SysTime.fromISOExtString;

	assert(buf.formatValue(parse("2020-06-08T14:25:30.1234567Z")) == 28);
	assert(buf[0 .. 28] == "2020-06-08T14:25:30.1234567Z");
	assert(buf.formatValue(parse("2020-06-08T14:25:30.123456Z")) == 27);
	assert(buf[0 .. 27] == "2020-06-08T14:25:30.123456Z");
	assert(buf.formatValue(parse("2020-06-08T14:25:30.12345Z")) == 26);
	assert(buf[0 .. 26] == "2020-06-08T14:25:30.12345Z");
	assert(buf.formatValue(parse("2020-06-08T14:25:30.1234Z")) == 25);
	assert(buf[0 .. 25] == "2020-06-08T14:25:30.1234Z");
	assert(buf.formatValue(parse("2020-06-08T14:25:30.123Z")) == 24);
	assert(buf[0 .. 24] == "2020-06-08T14:25:30.123Z");
	assert(buf.formatValue(parse("2020-06-08T14:25:30.12Z")) == 23);
	assert(buf[0 .. 23] == "2020-06-08T14:25:30.12Z");
	assert(buf.formatValue(parse("2020-06-08T14:25:30.1Z")) == 22);
	assert(buf[0 .. 22] == "2020-06-08T14:25:30.1Z");
	assert(buf.formatValue(parse("2020-06-08T14:25:30Z")) == 20);
	assert(buf[0 .. 20] == "2020-06-08T14:25:30Z");
	version (Posix) {
		assert(buf.formatValue(SysTime.init) == 20);
		assert(buf[0 .. 20] == "0001-01-01T00:00:00Z");
	} else version (Windows) {
		assert(buf.formatValue(SysTime.init) == 7);
		assert(buf[0 .. 7] == "invalid");
	}

	assert(getFormatSize(parse("2020-06-08T14:25:30.1234567Z")) == 28);
	assert(getFormatSize(parse("2020-06-08T14:25:30.123456Z")) == 27);
	assert(getFormatSize(parse("2020-06-08T14:25:30.12345Z")) == 26);
	assert(getFormatSize(parse("2020-06-08T14:25:30.1234Z")) == 25);
	assert(getFormatSize(parse("2020-06-08T14:25:30.123Z")) == 24);
	assert(getFormatSize(parse("2020-06-08T14:25:30.12Z")) == 23);
	assert(getFormatSize(parse("2020-06-08T14:25:30.1Z")) == 22);
	assert(getFormatSize(parse("2020-06-08T14:25:30Z")) == 20);
}

/++
	Formats duration.
	It uses custom formatter that is inspired by std.format output, but a bit shorter.
	Note: ISO 8601 was considered, but it's not as human readable as used format.
+/
uint formatValue(S)(ref scope S sink, Duration val) {
	mixin SinkWriter!S;

	enum secsInDay = 86_400;
	enum secsInHour = 3_600;
	enum secsInMinute = 60;

	long totalHNS = __traits(getMember, val, "_hnsecs"); // access private member
	if (totalHNS < 0) {
		put('-');
		totalHNS = -totalHNS;
	}

	immutable fracSecs = totalHNS % 10_000_000;
	long totalSeconds = totalHNS / 10_000_000;

	if (totalSeconds) {
		immutable days = totalSeconds / secsInDay;
		long seconds = totalSeconds % secsInDay;
		if (days)
			advance(s.formatTo!"%d days"(days));
		if (seconds) {
			immutable hours = seconds / secsInHour;
			seconds %= secsInHour;
			if (hours)
				advance(days ? s.formatTo!", %d hrs"(hours) : s.formatTo!"%d hrs"(hours));

			if (seconds) {
				immutable minutes = seconds / secsInMinute;
				seconds %= secsInMinute;
				if (minutes)
					advance(days || hours ? s.formatTo!", %d mins"(
							minutes) : s.formatTo!"%d mins"(minutes));

				if (seconds)
					advance(days || hours || minutes ? s.formatTo!", %d secs"(
							seconds) : s.formatTo!"%d secs"(seconds));
			}
		}
	}

	if (fracSecs) {
		immutable msecs = fracSecs / 10_000;
		int usecs = fracSecs % 10_000;

		if (msecs | usecs) {
			advance(totalSeconds ? s.formatTo!", %d"(msecs) : s.formatTo!"%d"(msecs));

			if (usecs) {
				char[5] buf = void;
				buf[0] = '.';

				int ulen = 1;
				foreach (i; [1_000, 100, 10, 1]) {
					buf[ulen++] = cast(char)(usecs / i + '0');
					usecs %= i;
					if (usecs == 0)
						break;
				}
				put(buf[0 .. ulen]);
			}

			put(" ms");
		}
	}

	if (!totalLen)
		put("0 ms");

	return totalLen;
}

@"duration"unittest {
	import core.time;

	char[64] buf;

	assert(buf.formatValue(1.seconds) == 6);
	assert(buf[0 .. 6] == "1 secs");

	assert(buf.formatValue(1.seconds + 15.msecs + 5.hnsecs) == 18);
	assert(buf[0 .. 18] == "1 secs, 15.0005 ms");

	assert(buf.formatValue(1.seconds + 1215.msecs + 15.hnsecs) == 19);
	assert(buf[0 .. 19] == "2 secs, 215.0015 ms");

	assert(buf.formatValue(5.days) == 6);
	assert(buf[0 .. 6] == "5 days");

	assert(buf.formatValue(5.days + 25.hours) == 13);
	assert(buf[0 .. 13] == "6 days, 1 hrs");

	assert(buf.formatValue(5.days + 25.hours + 78.minutes) == 22);
	assert(buf[0 .. 22] == "6 days, 2 hrs, 18 mins");

	assert(buf.formatValue(5.days + 25.hours + 78.minutes + 102.seconds) == 31);
	assert(buf[0 .. 31] == "6 days, 2 hrs, 19 mins, 42 secs");

	assert(buf.formatValue(5.days + 25.hours + 78.minutes + 102.seconds + 2321.msecs) == 39);
	assert(buf[0 .. 39] == "6 days, 2 hrs, 19 mins, 44 secs, 321 ms");

	assert(buf.formatValue(
			5.days + 25.hours + 78.minutes + 102.seconds + 2321.msecs + 1987
			.usecs) == 43);
	assert(buf[0 .. 43] == "6 days, 2 hrs, 19 mins, 44 secs, 322.987 ms");

	assert(buf.formatValue(
			5.days + 25.hours + 78.minutes + 102.seconds + 2321.msecs + 1987.usecs + 15
			.hnsecs) == 44);
	assert(buf[0 .. 44] == "6 days, 2 hrs, 19 mins, 44 secs, 322.9885 ms");

	assert(buf.formatValue(-42.msecs) == 6);
	assert(buf[0 .. 6] == "-42 ms");

	assert(buf.formatValue(Duration.zero) == 4);
	assert(buf[0 .. 4] == "0 ms");
}
