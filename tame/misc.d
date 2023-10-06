module tame.misc;

import std.ascii;
import std.traits;

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
auto isAlphabet(in char[] s) {
	foreach (c; s) {
		if ((c < 'a' || c > 'z') && (c < 'A' || c > 'Z'))
			return false;
	}
	return true;
}
///
unittest {
	assert("aBcDEf".isAlphabet == true);
	assert("ABCd_".isAlphabet == false);
	assert("ABC12".isAlphabet == false);
}

/// Returns: true if the string starts with a white character
bool startsWithWhite(S)(S s) if (isArray!S)
	=> s.length && s[0].isWhite;

///
unittest {
	assert(startsWithWhite(" a"));
	assert(!startsWithWhite("a"));
}
