module tame.conv;

ulong convert(T)(const T[] digits, uint radix = 10, size_t* ate = null) {
	size_t eaten;
	ulong value;

	foreach (T c; digits) {
		if (c < '0' || c > '9') {
			if (c >= 'a' && c <= 'z')
				c -= 39;
			else if (c >= 'A' && c <= 'Z')
				c -= 7;
			else
				break;
		}

		if ((c -= '0') >= radix)
			break;
		value = value * radix + c;
		++eaten;
	}

	if (ate)
		*ate = eaten;

	return value;
}

size_t intToStr(char* buf, size_t value) pure @nogc nothrow @trusted {
	char* p = buf;
	for (;;) {
		*p++ = value % 10 ^ '0';
		if (value < 10)
			break;
		value /= 10;
	}
	for (char* i = buf, j = p - 1; i < j; i++, j--) {
		char t = *i;
		*i = *j;
		*j = t;
	}
	return p - buf;
}
