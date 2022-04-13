module tame.conv;

nothrow @nogc:

ulong convert(T)(const(T[]) digits, uint radix = 10, size_t* ate = null) {
	size_t eaten;
	ulong value;

	foreach (ch; digits) {
		T c = ch;
		if (c < '0' || c > '9') {
			if (c >= 'a' && c <= 'z')
				c -= 39;
			else if (c >= 'A' && c <= 'Z')
				c -= 7;
			else
				break;
		}

		if ((c -= '0') < radix) {
			value = value * radix + c;
			++eaten;
		} else
			break;
	}

	if (ate)
		*ate = eaten;

	return value;
}
