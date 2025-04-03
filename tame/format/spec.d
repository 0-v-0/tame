module tame.format.spec;

import std.algorithm : among;
import std.meta;
import tame.string : canFind, indexOf;

package:

enum FMT : ubyte {
	STR,
	CHR,
	DEC, // also for BOOL
	HEX,
	UHEX,
	PTR,
	FLT,
}

struct FmtParams {
	bool leftJustify; // Left justify the result in the field. It overrides any 0 flag.
	bool signed; // Prefix positive numbers in a signed conversion with a +. It overrides any space flag.
	bool prefixHex; // If non-zero, prefix result with 0x (0X).
	int width; // pad with characters, if -1, use previous argument as width
	char fill = ' '; // character to pad with
	int sep; // insert separator each X digits, if -1, use previous argument as X
	bool sepChar; // is separator char defined in additional arg?
	int prec; // precision, if -1, use previous argument as precision value
}

struct FmtSpec {
	int i;
	FMT type;
	string def;
}

// Nested array format specifier
struct ArrFmtSpec {
	int i;
	string fmt; // item format
	string del; // delimiter
	bool esc; // escape strings and characters
}

// Parses format specifier in CTFE
// See: https://dlang.org/phobos/std_format.html for details
// Note: Just a subset of the specification is supported ATM. Parser here parses the spec, but
// formatter doesn't use it all.
//
// FormatStringItem:
//     '%%'
//     '%' Position Flags Width Separator Precision FormatChar
//     '%(' FormatString '%)'
//     '%-(' FormatString '%)'
//
auto formatSpec(FMT f, string spec) {
	FmtParams res;
	int i;

	if (spec.length) {
		assert(!spec.canFind('$'), "Position specifier not supported");

		// Flags:
		//   empty
		//   '-' Flags
		//   '+' Flags
		//   '#' Flags
		//   '0' Flags
		//   ' ' Flags
		while (i < spec.length) {
			if (spec[i] == '-') {
				res.leftJustify = true;
				i++;
				continue;
			} else if (f.among(FMT.DEC, FMT.FLT) && spec[i] == '+') {
				res.signed = true;
				i++;
				continue;
			} else if (f == FMT.HEX && spec[i] == '#') {
				// TODO: 'o' - Add to precision as necessary so that the first digit of the octal formatting is a '0', even if both the argument and the Precision are zero.
				res.prefixHex = true;
				i++;
				continue;
			} else if (f == FMT.FLT && spec[i] == '#') {
				// TODO: Always insert the decimal point and print trailing zeros.
				i++;
				continue;
			} else if (f.among(FMT.DEC, FMT.FLT, FMT.HEX, FMT.UHEX, FMT.PTR) && spec[i].among('0', ' ')) {
				res.fill = spec[i++];
				continue;
			}
			break;
		}

		if (i == spec.length)
			goto done;

		// Width:
		//     empty
		//     Integer
		//     '*'
		if (spec[i] == '*') {
			res.width = -1;
			i++;
		} else {
			while (i < spec.length && spec[i].isDigit)
				res.width = res.width * 10 + (spec[i++] - '0');
		}

		if (i == spec.length)
			goto done;

		// Separator:
		//     empty
		//     ','
		//     ',' '?'
		//     ',' '*' '?'
		//     ',' Integer '?'
		//     ',' '*'
		//     ',' Integer
		if (spec[i] == ',') {
			// ie: writefln("'%,*?d'", 4, '$', 123456789);
			i++;
			if (i == spec.length) {
				res.sep = 3;
				goto done;
			}
			if (spec[i].isDigit) {
				while (i < spec.length && spec[i].isDigit)
					res.sep = res.sep * 10 + (spec[i++] - '0');
			} else if (spec[i] == '*') {
				i++;
				res.sep = -1;
			} else
				res.sep = 3;

			if (i == spec.length)
				goto done;
			if (spec[i] == '?') {
				res.sepChar = true;
				i++;
			}
		}
		if (i == spec.length)
			goto done;

		// Precision:
		//     empty
		//     '.'
		//     '.' Integer
		//     '.*'
		if (spec[i] == '.') {
			i++;
			if (i == spec.length) {
				res.prec = 6;
				goto done;
			}
			if (spec[i].isDigit) {
				while (i < spec.length && spec[i].isDigit)
					res.prec = res.prec * 10 + (spec[i++] - '0');
			} else if (spec[i] == '*') {
				i++;
				res.prec = -1;
			}
		}
	}

done:
	assert(i == spec.length, "Parser error");
	return res;
}

// Used to find end of the format specifier.
// See: https://dlang.org/phobos/std_format.html for grammar and valid characters for fmt spec
// Note: Nested array fmt spec is handled separately so no '(', ')' characters here
private size_t indexOfNonDigit(string fmt) {
	size_t i;
	foreach (c; fmt) {
		if (!"0123456789+-.,#*?$ ".canFind(c))
			return i;
		++i;
	}
	return i;
}

private long getNestedArrFmtLen(string fmt) {
	int lvl;
	for (long i; i < fmt.length; ++i) {
		// detect next level of nested array format spec
		if (fmt[i] == '(' // new nested array can be '%(' or '%-('
			&& (
				(i > 0 && fmt[i - 1] == '%')
				|| (i > 1 && fmt[i - 2] == '%' && fmt[i - 1] == '-')
			))
			lvl++;
		// detect end of nested array format spec
		if (fmt[i] == '%' && fmt.length > i + 1 && fmt[i + 1] == ')') {
			if (!lvl)
				return i + 2;
			else
				--lvl;
		}
	}
	return -1;
}

@"getNestedArrFmtLen"unittest {
	static assert(getNestedArrFmtLen("%d%)foo") == 4);
	static assert(getNestedArrFmtLen("%d%| %)foo") == 7);
	static assert(getNestedArrFmtLen("%(%d%)%)foo") == 8);
}

private template getNestedArrayFmt(string fmt) {
	import std.string : lastIndexOf;

	// make sure we're searching in top level only
	enum lastSubEnd = fmt.lastIndexOf("%)");
	static if (lastSubEnd > 0) {
		enum i = fmt[lastSubEnd + 2 .. $].lastIndexOf("%|"); // delimiter separator used
		static if (i >= 0)
			alias getNestedArrayFmt = AliasSeq!(fmt[0 .. lastSubEnd + 2 + i], fmt[lastSubEnd + i + 4 .. $]);
		else
			alias getNestedArrayFmt = AliasSeq!(fmt[0 .. lastSubEnd + 2], fmt[lastSubEnd + 2 .. $]);
	} else {
		enum i = fmt.lastIndexOf("%|"); // delimiter separator used
		static if (i >= 0)
			alias getNestedArrayFmt = AliasSeq!(fmt[0 .. i], fmt[i + 2 .. $]); // we can return delimiter directly
		else {
			// we need to find end of inner fmt spec first
			static assert(fmt.length >= 2, "Invalid nested array element format specifier: " ~ fmt);
			enum startIdx = fmt.indexOf('%');
			static assert(startIdx >= 0, "No nested array element format specified");
			enum endIdx = startIdx + 1 + indexOfNonDigit(fmt[startIdx + 1 .. $]);
			enum len = endIdx - startIdx + 1;

			static if ((len == 2 && fmt[startIdx + 1] == '(') || (len == 3 && fmt[startIdx + 1 .. startIdx + 3] == "-(")) {
				// further nested array fmt spec -> split by end of nested highest level
				enum nlen = fmt[1] == '(' ? (2 + getNestedArrFmtLen(fmt[2 .. $])) : (
						3 + getNestedArrFmtLen(fmt[3 .. $]));
				static assert(nlen > 0, "Invalid nested array format specifier: " ~ fmt);
				alias getNestedArrayFmt = AliasSeq!(fmt[0 .. nlen], fmt[nlen .. $]);
			} else // split at the end of element fmt spec
				alias getNestedArrayFmt = AliasSeq!(fmt[0 .. endIdx + 1], fmt[endIdx + 1 .. $]);
		}
	}
}

@"getNestedArrayFmt"unittest {
	static assert(getNestedArrayFmt!"%d " == AliasSeq!("%d", " "));
	static assert(getNestedArrayFmt!"%d %|, " == AliasSeq!("%d ", ", "));
	static assert(getNestedArrayFmt!"%(%d %|, %)" == AliasSeq!("%(%d %|, %)", ""));
	static assert(getNestedArrayFmt!"%(%d %|, %),-" == AliasSeq!("%(%d %|, %)", ",-"));
	static assert(getNestedArrayFmt!"foo%(%d %|, %)-%|;" == AliasSeq!("foo%(%d %|, %)-", ";"));
}

/++
	Splits format string based on the same rules as described here: https://dlang.org/phobos/std_format.html
	In addition it supports 'p' as a pointer format specifier to be more compatible with `printf`.
	It supports nested arrays format specifier too.
+/
template splitFmt(string fmt) {
	enum spec(int j, FMT f, string def) = FmtSpec(j, f, def);

	enum arrSpec(int j, string fmt, string del, bool esc) = ArrFmtSpec(j, fmt, del, esc);

	template helper(int from, int j) {
		enum i = fmt[from .. $].indexOf('%');
		static if (i < 0) {
			enum helper = AliasSeq!(fmt[from .. $]);
		} else {
			enum i1 = i + from;
			static assert(i1 + 1 < fmt.length, "Expected formatter after %");
			enum i2 = i1 + indexOfNonDigit(fmt[i1 + 1 .. $]);
			// pragma(msg, "fmt: ", fmt[from .. idx2]);
			static if (fmt[i2 + 1] == 's')
				enum helper = AliasSeq!(fmt[from .. i1], spec!(j, FMT.STR, fmt[i1 + 1 .. i2 + 1]), helper!(
							i2 + 2, j + 1));
			else static if (fmt[i2 + 1] == 'c')
				enum helper = AliasSeq!(fmt[from .. i1], spec!(j, FMT.CHR, fmt[i1 + 1 .. i2 + 1]), helper!(
							i2 + 2, j + 1));
			else static if (fmt[i2 + 1] == 'b') // TODO: should be binary, but use hex for now
				enum helper = AliasSeq!(fmt[from .. i1], spec!(j, FMT.HEX, fmt[i1 + 1 .. i2 + 1]), helper!(
							i2 + 2, j + 1));
			else static if (fmt[i2 + 1].among('d', 'u'))
				enum helper = AliasSeq!(fmt[from .. i1], spec!(j, FMT.DEC, fmt[i1 + 1 .. i2 + 1]), helper!(
							i2 + 2, j + 1));
			else static if (fmt[i2 + 1] == 'o') // TODO: should be octal, but use hex for now
				enum helper = AliasSeq!(fmt[from .. i1], spec!(j, FMT.DEC, fmt[i1 + 1 .. i2 + 1]), helper!(
							i2 + 2, j + 1));
			else static if (fmt[i2 + 1] == 'x')
				enum helper = AliasSeq!(fmt[from .. i1], spec!(j, FMT.HEX, fmt[i1 + 1 .. i2 + 1]), helper!(
							i2 + 2, j + 1));
			else static if (fmt[i2 + 1] == 'X')
				enum helper = AliasSeq!(fmt[from .. i1], spec!(j, FMT.UHEX, fmt[i1 + 1 .. i2 + 1]), helper!(
							i2 + 2, j + 1));
			else static if (fmt[i2 + 1].among('e', 'E', 'f', 'F', 'g', 'G', 'a', 'A')) // TODO: float number formatters
				enum helper = AliasSeq!(fmt[from .. i1], spec!(j, FMT.FLT, fmt[i1 + 1 .. i2 + 1]), helper!(
							i2 + 2, j + 1));
			else static if (fmt[i2 + 1] == 'p')
				enum helper = AliasSeq!(fmt[from .. i1], spec!(j, FMT.PTR, fmt[i1 + 1 .. i2 + 1]), helper!(
							i2 + 2, j + 1));
			else static if (fmt[i2 + 1] == '%')
				enum helper = AliasSeq!(fmt[from .. i1 + 1], helper!(i2 + 2, j));
			else static if (fmt[i2 + 1] == '(' || fmt[i2 + 1 .. i2 + 3] == "-(") {
				// nested array format specifier
				enum l = fmt[i2 + 1] == '('
					? getNestedArrFmtLen(fmt[i2 + 2 .. $]) : getNestedArrFmtLen(
						fmt[i2 + 3 .. $]);
				alias naSpec = getNestedArrayFmt!(fmt[i2 + 2 .. i2 + 2 + l - 2]);
				// pragma(msg, fmt[from .. idx1], "|", naSpec[0], "|", naSpec[1], "|");
				enum helper = AliasSeq!(
						fmt[from .. i1],
						arrSpec!(j, naSpec[0], naSpec[1], fmt[i2 + 1] != '('),
						helper!(i2 + 2 + l, j + 1));
			} else
				static assert(0, "Invalid formatter '" ~ fmt[i2 + 1] ~ "' in fmt='" ~ fmt ~ "'");
		}
	}

	template countFormatter(T...) {
		static if (T.length == 0)
			enum countFormatter = 0;
		else static if (is(T[0] == FmtSpec) || is(T[0] == ArrFmtSpec))
			enum countFormatter = 1 + countFormatter!(T[1 .. $]);
		else
			enum countFormatter = countFormatter!(T[1 .. $]);
	}

	alias tokens = helper!(0, 0);
	alias numFormatters = countFormatter!(typeof(tokens));
}

private bool isDigit(char c)
	=> c >= '0' && c <= '9';
