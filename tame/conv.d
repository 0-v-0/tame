module tame.conv;

ulong convert(T)(const(T[]) digits, uint radix = 10, size_t* ate = null) {
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
