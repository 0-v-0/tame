/++
	This module is used to decode and encode base64 char[] arrays.
+/
module tame.data.base64;

@safe pure nothrow:

unittest {
	auto str = cast(const(ubyte)[])"Hello there, my name is Jeff.";
	scope encodebuf = new char[encodedSize(str)];
	char[] encoded = encode(str, encodebuf);

	scope decodebuf = new ubyte[encoded.length];
	assert(decode(encoded, decodebuf) == "Hello there, my name is Jeff.");
}

@nogc:

/++
	calculates and returns the size needed to encode the length of the
	array passed.

	Params:
	data = An array that will be encoded
+/
size_t encodedSize(in void[] data) => encodedSize(data.length);

/++
	calculates and returns the size needed to encode the length passed.

	Params:
	length = Number of bytes to be encoded
+/
size_t encodedSize(size_t length)
	=> (length + 2) / 3 * 4; // for every 3 bytes we need 4 bytes to encode, with any fraction needing an additional 4 bytes with padding

/++
	encodes data into buf and returns the number of bytes encoded.
	this will not terminate and pad any "leftover" bytes, and will instead
	only encode up to the highest number of bytes divisible by three.

	returns the number of bytes left to encode

	Params:
	data = what is to be encoded
	buf = buffer large enough to hold encoded data
	bytesEncoded = ref that returns how much of the buffer was filled
+/
size_t encodeChunk(const ubyte[] data, char[] buf, ref size_t bytesEncoded) @trusted {
	size_t tripletCount = data.length / 3;
	size_t rtn;
	char* rtnPtr = buf.ptr;
	const(ubyte)* dataPtr = data.ptr;

	if (data.length) {
		rtn = tripletCount * 3;
		bytesEncoded = tripletCount * 4;
		for (size_t i; i < tripletCount; i++) {
			*rtnPtr++ = _encodeTable[(dataPtr[0] & 0xFC) >> 2];
			*rtnPtr++ = _encodeTable[(dataPtr[0] & 0x03) << 4 | (dataPtr[1] & 0xF0) >> 4];
			*rtnPtr++ = _encodeTable[(dataPtr[1] & 0x0F) << 2 | (dataPtr[2] & 0xC0) >> 6];
			*rtnPtr++ = _encodeTable[dataPtr[2] & 0x3F];
			dataPtr += 3;
		}
	}

	return rtn;
}

/++
	encodes data and returns as an ASCII base64 string.

	Params:data = what is to be encoded
	buf = buffer large enough to hold encoded data

	Example:
	---
	char[512] encodebuf;
	char[] encodedString = encode(cast(ubyte[])"Hello, how are you today?", encodebuf);
	assert(encodedString == "SGVsbG8sIGhvdyBhcmUgeW91IHRvZGF5Pw==")
	---
+/
char[] encode(const ubyte[] data, char[] buf) @trusted
in (buf.length >= encodedSize(data)) {
	size_t bytesEncoded;
	size_t numBytes = encodeChunk(data, buf, bytesEncoded);
	char* rtnPtr = buf.ptr + bytesEncoded;
	const(ubyte)* dataPtr = data.ptr + numBytes;
	size_t tripletFraction = data.length - numBytes;

	switch (tripletFraction) {
	case 2:
		*rtnPtr++ = _encodeTable[(dataPtr[0] & 0xFC) >> 2];
		*rtnPtr++ = _encodeTable[(dataPtr[0] & 0x03) << 4 | (dataPtr[1] & 0xF0) >> 4];
		*rtnPtr++ = _encodeTable[(dataPtr[1] & 0x0F) << 2];
		*rtnPtr++ = '=';
		break;
	case 1:
		*rtnPtr++ = _encodeTable[(dataPtr[0] & 0xFC) >> 2];
		*rtnPtr++ = _encodeTable[(dataPtr[0] & 0x03) << 4];
		*rtnPtr++ = '=';
		*rtnPtr++ = '=';
		break;
	default:
	}
	return buf[0 .. rtnPtr - buf.ptr];
}

/++
	decodes an ASCCI base64 string and returns it as ubyte[] data.

	This decoder will ignore non-base64 characters. So:
	SGVsbG8sIGhvd
	yBhcmUgeW91IH
	RvZGF5Pw==

	Is valid.

	Params:
	data = what is to be decoded
	buf = a big enough array to hold the decoded data

	Example:
	---
	ubyte[512] decodebuf;
	auto decodedString = cast(char[])decode("SGVsbG8sIGhvdyBhcmUgeW91IHRvZGF5Pw==", decodebuf);
	Stdout(decodedString).newline; // Hello, how are you today?
	---
+/
ubyte[] decode(const char[] data, ubyte[] buf) @trusted {
	if (data.length) {
		ubyte[4] base64Quad;
		ubyte* quadPtr = base64Quad.ptr;
		ubyte* endPtr = base64Quad.ptr + 4;
		ubyte* rtnPt = buf.ptr;
		size_t encodedLength;

		ubyte padCount;
		ubyte endCount;
		ubyte paddedPos;
		foreach_reverse (piece; data) {
			paddedPos++;
			ubyte current = _decodeTable[piece];
			if (current || piece == 'A') {
				endCount++;
				if (current == BASE64_PAD)
					padCount++;
			}
			if (endCount == 4)
				break;
		}

		if (padCount > 2)
			return []; // Improperly terminated base64 string.
		if (padCount == 0)
			paddedPos = 0;

		auto nonPadded = data[0 .. ($ - paddedPos)];
		foreach (piece; nonPadded) {
			ubyte next = _decodeTable[piece];
			if (next || piece == 'A')
				*quadPtr++ = next;
			if (quadPtr is endPtr) {
				rtnPt[0] = cast(ubyte)((base64Quad[0] << 2) | (base64Quad[1] >> 4));
				rtnPt[1] = cast(ubyte)((base64Quad[1] << 4) | (base64Quad[2] >> 2));
				rtnPt[2] = cast(ubyte)((base64Quad[2] << 6) | base64Quad[3]);
				encodedLength += 3;
				quadPtr = base64Quad.ptr;
				rtnPt += 3;
			}
		}

		// this will try and decode whatever is left, even if it isn't terminated properly (ie: missing last one or two =)
		if (paddedPos) {
			const(char)[] padded = data[($ - paddedPos) .. $];
			foreach (char piece; padded) {
				ubyte next = _decodeTable[piece];
				if (next || piece == 'A')
					*quadPtr++ = next;
				if (quadPtr is endPtr) {
					*rtnPt++ = cast(ubyte)((base64Quad[0] << 2) | (base64Quad[1]) >> 4);
					if (base64Quad[2] != BASE64_PAD) {
						*rtnPt++ = cast(ubyte)((base64Quad[1] << 4) | (base64Quad[2] >> 2));
						encodedLength += 2;
						break;
					} else {
						encodedLength++;
						break;
					}
				}
			}
		}

		return buf[0 .. encodedLength];
	}

	return [];
}

private:

enum BASE64_PAD = 64;
immutable _encodeTable = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";

// dfmt off

immutable ubyte[256] _decodeTable = [
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,62,0,0,0,63,52,53,54,55,56,57,58,
	59,60,61,0,0,0,BASE64_PAD,0,0,0,0,1,2,3,
	4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,
	19,20,21,22,23,24,25,0,0,0,0,0,0,26,27,
	28,29,30,31,32,33,34,35,36,37,38,39,40,
	41,42,43,44,45,46,47,48,49,50,51,
];
