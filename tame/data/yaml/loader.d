/// Class used to load YAML documents
module tame.data.yaml.loader;

import tame.data.yaml.node;
import tame.data.yaml.util;
import std.datetime;
import tame.text.ascii;
import tame.string;
import std.ascii : isWhite;
import std.array : replace, replaceInto;

enum indent = 2;

@safe:

Node loadyml(string str) => loadyml(str, 0, 0);

Node loadyml(ref string str, int n, uint ln) {
	if (n > 63)
		throw new NodeException("Nesting too deep.", Mark(ln, 0));
	Node node;

	for (size_t lineLen; str.length;) {
		auto line = peekLine(str);
		ln++;
		uint p = indent;
		lineLen = line.length;
		if (lineLen && line[0] == '\n')
			goto nextLine;
		Mark mark() {
			return Mark(ln, p);
		}

		{
			const level = getTabLevel(line, ln, p);
			node.mark_ = mark;
			int d = level - n;
			if (d < 0)
				return node;
			if (d > 1)
				throw new NodeException("Bad indentation", mark);
			n = level;
		}
		{
			ptrdiff_t i;
			switch (line[p]) {
			case '#':
				goto nextLine;
			case ']',
				'|',
				'}',
				'>':
				throw new NodeException("Syntax error", mark);
			case '[',
				'{':
				throw new NodeException("Flow style is not supported", mark);
			case '-':
				i = p + 1;
				str = str[i .. $];
				if (i == line.length)
					break;
				if (!isWhite(line[i]))
					throw new NodeException("Syntax error", mark);
				uint col = cast(uint)i + 1;
				node.add(parseValue(str, ln, col, (indent + 1) * p));
				break;
			case '!':
				throw new NodeException("Tag token is not supported", mark);
			case '?':
				throw new NodeException("YAML Set is not supported", mark);
			case '"':
				uint old_ln = ln, col;
				str = str[p + 1 .. $];
				auto key = parseStr(str, ln, col);
				if (ln != old_ln)
					throw new NodeException("a multiline key may not be an implicit key", Mark(old_ln, p));
				break;
			case '\'':
				i = line.indexOf('\'', p) + 1;
				if (i <= 0)
					throw new NodeException("a multiline key may not be an implicit key", mark);
				if (i == line.length)
					throw new NodeException("Expected colon", mark);
				auto key = line[1 .. i++];
				uint col = cast(uint)i + 1;
				str = str[col .. $];
				node.add(key, parseValue(str, ln, col, (indent + 1) * p));
				break;
			default:
				if (line.length == p)
					goto nextLine;
				i = line.indexOf('#', p);
				if (i >= 0)
					line = line[0 .. i];
				i = line.indexOf(':', p) + 1;
				if (i <= 0)
					throw new NodeException("Expected colon", mark);
				if (i == line.length || line[i] == '\n') {
					str = str[lineLen .. $];
					node.add(line[0 .. i - 1].stripRight, loadyml(str, n, ln));
					continue;
				}
				if (!isWhite(line[i]))
					throw new NodeException("a multiline key may not be an implicit key", mark);
				str = str[++i .. $];
				auto key = line[p .. i - 2].stripRight;
				p = cast(uint)i;
				node.add(key, parseValue(str, ln, p, (indent + 1) * p));
			}
			continue;
		}
	nextLine:
		str = str[lineLen .. $];
	}
	return node;
}

unittest {
	Node n = loadyml("foo: bar # comment");
	assert(n["foo"].as!string == "bar");
	n = loadyml("r: \ntest:\n  foo: a\n  bar: b\n  baz: c\nx:");
	assert(n["test"]["bar"] == Node("b"));
	assert("r" in n);
	n = loadyml("arr:\n  - a\n  - b # 123\n  - c\ny:");
	assert(n["arr"] == Node(["a", "b", "c"]));
	assert("y" in n);
}

private:

int getTabLevel(in char[] line, uint ln, ref uint p) {
	int i;
	while (i < line.length && line[i] == ' ')
		++i;
	const level = i / p;
	if (i % p)
		throw new NodeException("Bad indentation", Mark(ln, i));
	p = i;
	return level;
}

Node parseValue(ref string s, ref uint ln, ref uint col, uint level = 0) {
	import std.array;

	dchar state = '\0';
	uint lineBreaks, n;
	auto r = appender!string;
	for (; s.length; col++) {
		const c = s.front;
		if (state) {
			s.popFront();
			if (c != '\n') {
				if (state == '\'' && c == '\'')
					break;
				if (n) {
					if (!c.isWhite)
						throw new NodeException("Bad indentation", Mark(ln, col));
					--n;
				} else {
					lineBreaks &= 3;
					r ~= c;
				}
				continue;
			}
			col = 0;
			if (lineBreaks & 4) {
				lineBreaks &= 3;
				break;
			}
			lineBreaks |= 4;
			n = level;
			r ~= state == '|' ? '\n' : ' ';
			continue;
		}
		switch (c) {
		case '|':
		case '>':
			s.popFront();
			state = c;
			n = level;
			const line = peekLine(s);
			s = s[line.length .. $];
			if (line == "\n") {
				lineBreaks = 1;
				break;
			}
			if (line == "-\n") {
				lineBreaks = 0;
				break;
			}
			if (line == "+\n") {
				lineBreaks = 2;
				break;
			}
			throw new NodeException("Expected line break", Mark(ln, col + 1));
		case '\'':
			s.popFront();
			state = c;
			break;
		case '"':
			s.popFront();
			r ~= parseStr(s, ln, col);
			break;
		default:
			auto line = peekLine(s);
			s = s[line.length .. $];
			auto i = line.indexOf('#');
			if (i >= 0)
				line = line[0 .. i];
			return createNode(line.strip);
		}
	}
	while (lineBreaks--)
		r ~= '\n';
	return r[].length ? Node(r[]) : Node();
}

unittest {
	auto s = "|\n  x  \n  foo\n   bar";
	uint ln, col;
	Node n = parseValue(s, ln, col, 2);
	assert(n.as!string == "x  \nfoo\n bar\n");
	s = ">\n  x  \n  foo\n  bar";
	n = parseValue(s, ln, col, 2);
	assert(n.as!string == "x   foo bar\n");
}

public auto createNode(in char[] str) @trusted {
	{
		bool val;
		if (str.length > 3 && str.length < 6 && tryParse(str, val))
			return Node(val);
	}
	{
		long val;
		if (tryParse(str, val))
			return Node(val);
	}
	{
		double val;
		if (tryParse(str, val))
			return Node(val);
	}
	return Node(str);
}

auto peekLine(in char[] s) {
	const i = s.indexOf('\n');
	return i < 0 ? s : s[0 .. i + 1];
}

auto parseStr(ref string s, ref uint ln, ref uint col) {
	import tame.data.yaml.util;
	import std.array;
	import tame.format;

	bool inEscape, trim;
	auto r = appender!string;
	for (; s.length; col++) {
		const c = s[0];
		s = s[1 .. $];
		if (c == '\n') {
			col = 0;
			ln++;
			if (inEscape) {
				inEscape = false;
				continue;
			}
			trim = true;
			r ~= ' ';
			continue;
		}
		if (!c.isWhite)
			trim = false;

		if (!inEscape) {
			if (c == '"')
				return r[];
			// Escape sequence starts with a '\'
			if (c == '\\')
				inEscape = true;
			else if (!trim || !c.isWhite)
				r ~= c;
			continue;
		}
		// 'Normal' escape sequence
		auto ch = fromEscape(c);
		if (ch != '\uFFFF') {
			r ~= ch;
			inEscape = false;
			continue;
		}

		if (c != 'x' && c != 'u')
			throw new NodeException(text("Invalid escape '\\", c, "'"), Mark(ln, col));

		// Unicode char written in hexadecimal in an escape sequence
		const hexLen = escapeHexLength(c);
		auto hex = s[0 .. hexLen];
		foreach (hexDigit; hex) {
			import std.ascii : isHexDigit;

			if (!hexDigit.isHexDigit)
				throw new NodeException(text("Invalid escape '", hex, "'"), Mark(ln, col));
		}
		s = s[hexLen .. $];

		size_t ate;
		r ~= cast(dchar)convert(hex, 16, ate);
	}
	return r[];
}

unittest {
	auto s = "a\\Lb";
	uint ln, col;
	assert(parseStr(s, ln, col) == "a\u2028b");
	s = "a\\\nb";
	auto r = parseStr(s, ln, col);
	assert(r == "ab", r);
	s = " a\n  b";
	r = parseStr(s, ln, col);
	assert(r == " a b", r);
}

version (unittest) {
	bool eq(double a, double b, double epsilon = 1e-4)
		=> a >= b - epsilon && a <= b + epsilon;

	void test(T)(in char[] s, in T expected) {
		T result;
		assert(tryParse(s, result) && result == expected);
	}
}

long convert(T)(const(T[]) digits, uint radix = 10, out size_t ate) {
	size_t eaten;
	long value;

	foreach (char c; digits) {
		if (c < '0' || c > '9') {
			if (c >= 'a' && c <= 'z')
				c -= 39;
			else if (c >= 'A' && c <= 'Z')
				c -= 7;
			else {
				if (c == '_') {
					++eaten;
					continue;
				}
				break;
			}
		}

		if ((c -= '0') < radix) {
			value = value * radix + c;
			++eaten;
		} else
			break;
	}

	ate = eaten;

	return value;
}

auto tryParse(in char[] s, out bool result) {
	if (s == "true") {
		result = true;
		return true;
	}
	return s == "false";
}

auto tryParse(scope const(char)[] value, out long result) @trusted {
	if (!value.length) {
		result = 0;
		return false;
	}
	const c = value[0];
	result = c != '-' ? 1 : -1;
	if (c == '-' || c == '+')
		value = value[1 .. $];

	if (c == '_' || !value.length) {
		result = 0;
		return false;
	}

	size_t len, eaten = void;
	if (value.startsWith("0b")) { // Binary
		result *= convert(value[2 .. $], 2, eaten);
		len = eaten + 2;
	} else if (value.startsWith("0x")) { // Hexadecimal
		result *= convert(value[2 .. $], 16, eaten);
		len = eaten + 2;
	} else if (value[0] == '0') { // Octal or zero
		result *= convert(value, 8, eaten);
		len = eaten;
	} else if (value.canFind(':')) { // Sexagesimal
		long val;
		foreach (digit; value.splitter(':')) {
			val = val * 60 + convert(digit, 10, eaten);
			len += eaten + 1;
		}
		result *= val;
		--len;
	} else { //Decimal
		result *= convert(value, 10, eaten);
		len = eaten;
	}

	return len == value.length;
}

unittest {
	test("685230", 685230L); // canonical
	test("+685_230", 685230L); // decimal
	test("02472256", 685230L); // octal
	test("0x_0A_74_AE", 685230L); // hexadecimal
	test("0b1010_0111_0100_1010_1110", 685230L); // binary
	test("190:20:30", 685230L); // sexagesimal
	test("-1:3", -63L);
	test("-0b1", -1L);
}

auto tryParse(in char[] s, out double result) @trusted {
	import core.stdc.stdio : sscanf;
	import core.stdc.stdlib;
	import tame.unsafe.string;

	auto value = (cast(char*)alloca(s.length))[0 .. s.length];
	replaceInto(value, s, "_", "");
	if (value.length) {
		const c = value[0];
		result = c != '-' ? 1.0 : -1.0;
		if (c == '-' || c == '+')
			value = value[1 .. $];

		double n = void;
		if (value == ".inf" || value == ".Inf" || value == ".INF") // Infinity
			result *= double.infinity;
		else if (value == ".nan" || value == ".NaN" || value == ".NAN") // NaN
			result = double.nan;
		else if (value.indexOf(':') >= 0) { //Sexagesimal
			double val = 0.;
			foreach (digit; value.splitter(':')) {
				mixin TempCStr!digit;
				if (sscanf(digitz, "%lf", &n) != 1)
					goto err;
				val = val * 60 + n;
			}
			result *= val;
		} else { // Plain floating point
			mixin TempCStr!value;
			if (sscanf(valuez, "%lf", &n) != 1)
				goto err;
			result *= n;
		}

		return true;
	}
err:
	result = 0;
	return false;
}

unittest {
	static void test(in char[] s, double expected = 685230.15) {
		double result;
		assert(tryParse(s, result));
		assert(eq(result, expected));
	}

	test("6.8523015e+5"); // canonical
	test("685.230_15e+03"); // exponential
	test("685_230.15"); // fixed
	test("190:20:30.15"); // sexagesimal
	test("-.inf", -double.infinity); // negativeInf
	double result;
	assert(tryParse(".NaN", result) && result != result);
}

SysTime parseTimestamp(in char[] value) @trusted
	=> value.length < 11 ? SysTime(Date.fromISOExtString(value), UTC())
	: SysTime.fromISOExtString(
		value.replace(' ', 'T'));

unittest {
	static string parse(in char[] value)
		=> parseTimestamp(value).toISOString();

	enum {
		canonical = "2001-12-15T02:59:43.1Z",
		iso8601 = "2001-12-14T21:59:43.10-05:00",
		ymd = "2002-12-14",
	}

	assert(parse(canonical) == "20011215T025943.1Z");
	//avoiding float conversion errors
	assert(parse(iso8601) == "20011214T215943.0999999-05:00" ||
			parse(iso8601) == "20011214T215943.1-05:00");
	assert(parse(ymd) == "20021214T000000Z");
}
