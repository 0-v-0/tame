module tame.text.ascii;

version (Windows)
	import core.stdc.string : memicmp;
else version (Posix) {
package:
	import core.sys.posix.strings : memicmp = strncasecmp;
} else
	static assert(0, "Unsupported platform");

import core.stdc.string : memcmp, memcpy;
import std.ascii : isAlphaNum, isWhite;

nothrow @nogc:

/+
	Convert to lowercase in-place.
+/
T[] toLower(T)(T[] src) {
	foreach (ref c; src)
		if (c >= 'A' && c <= 'Z')
			c = T(c | 32);
	return src;
}

/+
	Convert to uppercase in-place.
+/
T[] toUpper(T)(T[] src) {
	foreach (ref c; src)
		if (c >= 'a' && c <= 'z')
			c = T(c & ~32);
	return src;
}

/+
	Compare two char[] ignoring case. Returns 0 if equal
+/
int icmp(in char[] s1, in char[] s2) @trusted {
	if (s1.ptr && s2.ptr) {
		const result = memicmp(s1.ptr, s2.ptr, s1.length > s2.length ? s2.length : s1.length);
		if (result)
			return result;
	}
	return (s1.length > s2.length) - (s1.length < s2.length);
}

/+
	Compare two char[] with case. Returns 0 if equal
+/
auto cmp(in char[] s1, in char[] s2) @trusted {
	if (s1.ptr && s2.ptr) {
		const result = memcmp(s1.ptr, s2.ptr, s1.length > s2.length ? s2.length : s1.length);
		if (result)
			return result;
	}
	return (s1.length > s2.length) - (s1.length < s2.length);
}

private immutable char[] _caseMap = [
	'\000', '\001', '\002', '\003', '\004', '\005', '\006', '\007',
	'\010', '\011', '\012', '\013', '\014', '\015', '\016', '\017',
	'\020', '\021', '\022', '\023', '\024', '\025', '\026', '\027',
	'\030', '\031', '\032', '\033', '\034', '\035', '\036', '\037',
	'\040', '\041', '\042', '\043', '\044', '\045', '\046', '\047',
	'\050', '\051', '\052', '\053', '\054', '\055', '\056', '\057',
	'\060', '\061', '\062', '\063', '\064', '\065', '\066', '\067',
	'\070', '\071', '\072', '\073', '\074', '\075', '\076', '\077',
	'\100', '\141', '\142', '\143', '\144', '\145', '\146', '\147',
	'\150', '\151', '\152', '\153', '\154', '\155', '\156', '\157',
	'\160', '\161', '\162', '\163', '\164', '\165', '\166', '\167',
	'\170', '\171', '\172', '\133', '\134', '\135', '\136', '\137',
	'\140', '\141', '\142', '\143', '\144', '\145', '\146', '\147',
	'\150', '\151', '\152', '\153', '\154', '\155', '\156', '\157',
	'\160', '\161', '\162', '\163', '\164', '\165', '\166', '\167',
	'\170', '\171', '\172', '\173', '\174', '\175', '\176', '\177',
	'\200', '\201', '\202', '\203', '\204', '\205', '\206', '\207',
	'\210', '\211', '\212', '\213', '\214', '\215', '\216', '\217',
	'\220', '\221', '\222', '\223', '\224', '\225', '\226', '\227',
	'\230', '\231', '\232', '\233', '\234', '\235', '\236', '\237',
	'\240', '\241', '\242', '\243', '\244', '\245', '\246', '\247',
	'\250', '\251', '\252', '\253', '\254', '\255', '\256', '\257',
	'\260', '\261', '\262', '\263', '\264', '\265', '\266', '\267',
	'\270', '\271', '\272', '\273', '\274', '\275', '\276', '\277',
	'\300', '\341', '\342', '\343', '\344', '\345', '\346', '\347',
	'\350', '\351', '\352', '\353', '\354', '\355', '\356', '\357',
	'\360', '\361', '\362', '\363', '\364', '\365', '\366', '\367',
	'\370', '\371', '\372', '\333', '\334', '\335', '\336', '\337',
	'\340', '\341', '\342', '\343', '\344', '\345', '\346', '\347',
	'\350', '\351', '\352', '\353', '\354', '\355', '\356', '\357',
	'\360', '\361', '\362', '\363', '\364', '\365', '\366', '\367',
	'\370', '\371', '\372', '\373', '\374', '\375', '\376', '\377',
];

/+
	Return the index position of a text pattern within src, or
	src.length upon failure.
	This is a case-insensitive search (with thanks to Nietsnie)
+/
size_t isearch(in char[] src, in char[] pattern) {
	if (src.length) {
		const d = src.length - pattern.length;
		for (size_t i1, i2 = void; i1 <= d; ++i1) {
			for (i2 = 0; i2 < pattern.length; ++i2)
				if (_caseMap[src[i1 + i2]] != _caseMap[pattern[i2]])
					break;

			if (i2 == pattern.length)
				return i1;
		}
	}
	return src.length;
}

unittest {
	import core.stdc.stdio;
	import core.stdc.string : strcpy;

	char[4] tmp;
	auto p = tmp.ptr;
	strcpy(p, "1bac".ptr);
	assert(toLower(tmp) == "1bac");
	strcpy(p, "1BAC".ptr);
	assert(toLower(tmp) == "1bac");
	strcpy(p, "1bac".ptr);
	assert(toUpper(tmp) == "1BAC");
	strcpy(p, "1BAC".ptr);
	assert(toUpper(tmp) == "1BAC");

	assert(icmp(null, null) == 0);
	assert(icmp(null, "a") < 0);
	assert(icmp("ABC", "abc") == 0);
	assert(icmp("abc", "abc") == 0);
	assert(icmp("abcd", "abc") > 0);
	assert(icmp("abc", "abcd") < 0);
	assert(icmp("ACC", "abc") > 0);

	assert(isearch(null, null) == 0);
	assert(isearch(null, "a") == 0);
	assert(isearch("ACC", "abc") == 3);
	assert(isearch("ACC", "acc") == 0);
	assert(isearch("aACC", "acc") == 1);
}

enum CharClass {
	Other,
	LowerCase,
	UpperCase,
	Underscore,
	Digit
}

CharClass classify(char ch) pure {
	import std.ascii;

	with (CharClass) {
		if (ch.isLower)
			return LowerCase;
		if (ch.isUpper)
			return UpperCase;
		if (ch.isDigit)
			return Digit;
		if (ch == '_')
			return Underscore;
		return Other;
	}
}

/// Returns: true if a string is a number
auto isNum(in char[] s, bool allowDecimalPoint = true) {
	if (!s.length)
		return false;
	bool hasDecimalPoint = !allowDecimalPoint;
	foreach (c; s[s[0] == '-' .. $]) {
		if (c == '.' && !hasDecimalPoint) {
			hasDecimalPoint = true;
		} else if (c < '0' || c > '9')
			return false;
	}
	return true;
}

///
unittest {
	assert("123".isNum);
	assert("123.456".isNum);
	assert(!"123.4a".isNum);
	assert(!"123.456".isNum(false));
}

/// Returns: true if all characters in a string are alphabets, uppercase, lowercase, or both
auto isAlpha(in char[] s) {
	foreach (c; s) {
		if ((c < 'a' || c > 'z') && (c < 'A' || c > 'Z'))
			return false;
	}
	return true;
}

///
unittest {
	assert("aBcDEf".isAlpha);
	assert(!"ABCd_".isAlpha);
	assert(!"ABC12".isAlpha);
}

/// Returns: true if the character is alphabets, digits or underscore
auto isAlphaNum_(dchar c) => isAlphaNum(c) || c == '_';

///
unittest {
	assert('a'.isAlphaNum_);
	assert('A'.isAlphaNum_);
	assert('0'.isAlphaNum_);
	assert('_'.isAlphaNum_);
	assert(!' '.isAlphaNum_);
}

/// Returns: true if the string starts with a white character
bool startsWithWhite(S)(S s) if (is(typeof(s[0]) : dchar) && is(typeof(s.length) : size_t))
	=> s.length && s[0].isWhite;

///
unittest {
	assert(startsWithWhite(" a"));
	assert(!startsWithWhite("a"));
}
