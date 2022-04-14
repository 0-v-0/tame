module tame.misc;

import std.traits;

/// Returns: true if an aray has an element
bool hasElement(T)(T[] array, T element) {
	bool r;
	foreach (cur; array) {
		if (cur == element) {
			r = true;
			break;
		}
	}
	return r;
}
///
unittest {
	assert([0, 1, 2].hasElement(2));
	assert(![0, 1, 2].hasElement(4));
}

/// Returns: true if a string is a number
auto isNum(string s, bool allowDecimalPoint = true) {
	if (!s.length)
		return false;
	bool hasDecimalPoint = !allowDecimalPoint;
	if (s[0] == '-')
		s = s[1 .. $];
	foreach (c; s) {
		if (c == '.' && !hasDecimalPoint) {
			hasDecimalPoint = true;
		} else if (c < '0' || c > '9')
			return false;
	}
	return true;
}

/// Returns: true if all characters in a string are alphabets, uppercase, lowercase, or both
auto isAlphabet(string s) {
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
bool startsWithWhite(S)(S s) if (isArray!S) {
	import std.ascii;

	return s.length && s[0].isWhite;
}
