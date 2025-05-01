module tame.parse;

import std.traits;
import tame.builtins;

/++
Decodes a single hexadecimal character.

Params:
c = The hexadecimal digit.

Returns: `c` converted to an integer.
+/

uint hexDecode(char c) @safe @nogc pure nothrow => c + 9 * (c >> 6) & 15;

uint hexDecode4(ref const(char)* hex) pure nothrow {
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
			if (ch > 5)
				return hex + i;
			result += ch + 10;
		}
	}
	hex += 4;
	return null;
}

///
unittest {
	string x = "aF09";
	const(char)* p = x.ptr;
	uint result;
	assert(!hexDecode4(p, result));
	assert(result == 0xAF09);
}

version (D_BetterC) {
} else:

import std.conv : ConvException;
import std.datetime;
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

///
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
	import std.regex;
	import std.string;

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

///
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
