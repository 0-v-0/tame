module tame.parse;

import std.datetime;
import std.conv : ConvException;
import std.format : formattedRead;

SysTime parseSysTime(S)(in S input) @trusted {
	import std.algorithm.searching;
	import std.regex;
	enum RE1 = `\d{4}-\D{3}-\d{2}`;
	enum RE2 = `.*[\+|\-]\d{1,2}:\d{1,2}|.*Z`;

	try {
		if (input.match(RE1))
			return SysTime.fromSimpleString(input);
		if (input.match(RE2))
			return input.canFind('-') ?
				SysTime.fromISOExtString(input) : SysTime.fromISOString(input);
		return SysTime(parseDateTime(input), UTC());
	} catch (ConvException e)
		throw new DateTimeException("Can not convert '" ~ input ~ "' to SysTime");
}

@safe unittest {
	// Accept valid (as per D language) systime formats
	parseSysTime("2019-May-04 13:34:10.500Z");
	parseSysTime("2019-Jan-02 13:34:10-03:00");
	parseSysTime("2019-05-04T13:34:10.500Z");
	parseSysTime("2019-06-14T13:34:10.500+01:00");
	parseSysTime("2019-02-07T13:34:10Z");
	parseSysTime("2019-08-12T13:34:10+01:00");
	parseSysTime("2019-09-03T13:34:10");

	// Accept valid (as per D language) date & datetime timestamps (will default timezone as UTC)
	parseSysTime("2010-Dec-30 00:00:00");
	parseSysTime("2019-05-04 13:34:10");
	// parseSysTime("2019-05-08");

	// Accept non-standard (as per D language) timestamp formats
	//parseSysTime("2019-05-07 13:32"); // todo: handle missing seconds
	//parseSysTime("2019/05/07 13:32"); // todo: handle slash instead of hyphen
	//parseSysTime("2010-12-30 12:10:04.1+00"); // postgresql
}

DateTime parseDateTime(S)(in S input) @trusted {
	import std.string;
	import std.regex;

	try {
		if (input.match(`\d{8}T\d{6}`)) // ISO String: 'YYYYMMDDTHHMMSS'
			return DateTime.fromISOString(input);
		if (input.match(`\d{4}-\D{3}-\d{2}`)) // Simple String 'YYYY-Mon-DD HH:MM:SS'
			return DateTime.fromSimpleString(input);
		if (input.match(`\d{4}-\d{2}-\d{2}`)) // ISO ext string 'YYYY-MM-DDTHH:MM:SS'
			return DateTime.fromISOExtString(input.replace(' ', 'T'));
		throw new ConvException(null);
	} catch (ConvException e)
		throw new DateTimeException("Can not convert '" ~ input ~ "' to DateTime");
}

@safe unittest {
	// Accept valid (as per D language) datetime formats
	parseDateTime("20101230T000000");
	parseDateTime("2019-May-04 13:34:10");
	parseDateTime("2019-Jan-02 13:34:10");
	parseDateTime("2019-05-04T13:34:10");

	// Accept non-standard (as per D language) timestamp formats
	parseDateTime("2019-06-14 13:34:10"); // accept a non-standard variation (space instead of T)
}

auto parseTime(S)(auto ref S input) {
	int hour, min, sec;
	input.formattedRead("%s:%s:%s", &hour, &min, &sec);
	return TimeOfDay(hour, min, sec);
}

Date parseDate(S)(S input) {
	int year, month, day;
	input.formattedRead("%s-%s-%s", &year, &month, &day);
	return Date(year, month, day);
}

import std.traits;
import tame.builtins;

@nogc nothrow:

/++
Decodes a single hexadecimal character.

Params:
c = The hexadecimal digit.

Returns:
`c` converted to an integer.
+/

uint hexDecode(char c) @safe pure => c + 9 * (c >> 6) & 15;

uint hexDecode4(ref const(char)* hex) pure {
	uint x = *cast(uint*)&hex;
	hex += 4;
	x = (x & 0x0F0F0F0F) + 9 * (x >> 6 & 0x01010101);
	version (LittleEndian) {
		return x >> 24 | x >> 12 & 0xF0 | x & 0xF00 | x << 12 & 0xF000;
	} else {
		x = (x | x >> 4) & 0x00FF00FF;
		return (x | x >> 8) & 0x0000FFFF;
	}
}

inout(char)* hexDecode4(ref inout(char)* hex, out uint result) pure nothrow @trusted {
	foreach (i; 0 .. 4) {
		result *= 16;
		int ch = hex[i] - '0';
		if (ch <= 9) {
			result += ch;
		} else {
			ch = (ch | 0x20) - 0x31;
			if (ch <= 5)
				result += ch + 10;
			else
				return hex + i;
		}
	}
	hex += 4;
	return null;
}

nothrow unittest {
	string x = "aF09";
	const(char)* p = x.ptr;
	uint result;
	assert(!hexDecode4(p, result));
	assert(result == 0xAF09);
}

package:

/+
	String Scanning and Comparison
+/

/++
Compares a string of unknown length against a statically known key.

This function also handles escapes and requires one or more terminator chars.

Params:
C = Character with.
key = The static key string.
terminators = A list of code units that terminate the string.
special = A list of code units that are handled by the user callback. Use
		this for escape string handling. Default is `null`.
p_str = Pointer to the string for the comparison. After the function call
		it will be behind the last matching character.
callback = User callback to handle special escape characters if `special`
			is non-empty.

Returns:
A code with following meanings: -1 = not equal, terminator character hit,
0 = not equal, but string not exhausted, 1 = string equals key.
+/
int fixedTermStrCmp(C, immutable C[] key, immutable C[] terminators, immutable C[] special = null)(
	ref const(C)* p_str, scope bool delegate(ref immutable(char)*, ref const(char)*) callback = null)
in (special.length == 0 || callback) {
	import std.algorithm, std.range;
	import std.array : staticArray;

	static immutable byte[256] classify =
		iota(256).map!(c => terminators.canFind(c) ? byte(-1) : special.canFind(c) ? 1 : 0)
			.staticArray;

	immutable(C)* p_key = key.ptr;
	immutable C* e_key = p_key + key.length;

	while (p_key !is e_key) {
		int clazz = *p_str <= 0xFF ? classify[*p_str] : 0;

		if (clazz < 0)
			return clazz;
		if (clazz == 0) {
			if (*p_str != *p_key)
				return clazz;

			p_str++;
			p_key++;
		} else if (clazz > 0) {
			if (!callback(p_key, p_str))
				return 0;
		}
	}

	return classify[*p_str & 0xFF] < 0;
}

@forceinline
void seekToAnyOf(string cs)(ref const(char)* p) {
	bool found = false;
	while (*p) {
		foreach (c; cs) {
			if (c == *p) {
				found = true;
				break;
			}
		}
		if (found)
			break;
		else
			p++;
	}
	//p.vpcmpistri!(char, sanitizeChars(cs), Operation.equalAnyElem);
}

@forceinline
void seekToRanges(string cs)(ref const(char)* p) {
	bool found = false;
	while (*p) {
		for (int i = 0; i < cs.length; i += 2) {
			if (cs[i] <= *p && cs[i + 1] >= *p) {
				found = true;
				break;
			}
		}
		if (found)
			break;
		else
			p++;
	}
	//p.vpcmpistri!(char, sanitizeRanges(cs), Operation.inRanges);
}

/++
Searches for a specific character known to appear in the stream and skips the
read pointer over it.

Params:
c = the character
p = the read pointer
+/
@forceinline
void seekPast(char c)(ref const(char)* p) {
	while (*p) {
		if (c == *p) {
			p++;
			break;
		}
		p++;
	}
	//p.vpcmpistri!(char, c.repeat(16).to!string, Operation.equalElem);
}

/++
Skips the read pointer over characters that fall into any of up to 8 ranges
of characters. The first character in `cs` is the start of the first range,
the second character is the end. This is repeated for any other character
pair. A character falls into a range from `a` to `b` if `a <= *p <= b`.

Params:
cs = the character ranges
p = the read pointer
+/
@forceinline
void skipCharRanges(string cs)(ref const(char)* p) if (cs.length % 2 == 0) {
	import std.range : chunks;

	while (*p) {
		bool found;
		for (size_t i; i < cs.length; i += 2) {
			if (cs[i] <= *p && cs[i + 1] >= *p) {
				found = true;
				break;
			}
		}
		if (!found)
			break;
		p++;
	}
	//p.vpcmpistri!(char, cs, Operation.inRanges, Polarity.negate);
}

/++
Skips the read pointer over all and any of the given characters.

Params:
cs = the characters to skip over
p = the read pointer
+/
@forceinline
void skipAllOf(string cs)(ref const(char)* p) {
	while (*p) {
		bool found;
		foreach (c; cs) {
			if (c == *p) {
				found = true;
				break;
			}
		}
		if (!found)
			break;
		p++;
	}

	//p.vpcmpistri!(char, cs, Operation.equalAnyElem, Polarity.negate);
}

/++
Skips the read pointer over ASCII white-space comprising '\t', '\r', '\n' and
' '.

Params:
p = the read pointer
+/
@forceinline
void skipAsciiWhitespace(ref const(char)* p) {
	if (*p == ' ')
		p++;
	if (*p <= ' ')
		p.skipAllOf!" \t\r\n";
}

/++
Sets the read pointer to the start of the next line.

Params:
p = the read pointer
+/
@forceinline
void skipToNextLine(ref const(char)* p) {
	// Stop at next \r, \n or \0.
	enum cmp_to = "\x09\x0B\x0C\x0E";
	while (*p && (*p != cmp_to[0] && *p != cmp_to[1] && *p != cmp_to[2] && *p != cmp_to[3]))
		p++;

	//p.vpcmpistri!(char, "\x01\x09\x0B\x0C\x0E\xFF", Operation.inRanges, Polarity.negate);
	if (p[0] == '\r')
		p++;
	if (p[0] == '\n')
		p++;
}
