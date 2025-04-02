module tame.text.uni;

version (LDC) {
	pragma(LDC_no_moduleinfo);
}

/// The last valid Unicode $(CODEPOINT).
enum lastDchar = 0x10FFFF;

enum : dchar {
	lineSep = '\u2028', /// Constant $(CODEPOINT) (0x2028) - line separator.
	paraSep = '\u2029', /// Constant $(CODEPOINT) (0x2029) - paragraph separator.
	nelSep = '\u0085', /// Constant $(CODEPOINT) (0x0085) - next line.
}

@safe pure nothrow @nogc:

// code points for private use, surrogates are not likely to change in near feature
// if need be they can be generated from unicode data as well

/++
	Returns: whether `c` is a Unicode Private Use $(CODEPOINT)
	(general Unicode category: Co).
+/
bool isPrivateUse(dchar c)
	=> (0x00_E000 <= c && c <= 0x00_F8FF)
		|| (0x0F_0000 <= c && c <= 0x0F_FFFD)
		|| (0x10_0000 <= c && c <= 0x10_FFFD);

/++
	Returns: whether `c` is a Unicode surrogate $(CODEPOINT)
	(general Unicode category: Cs).
+/
bool isSurrogate(dchar c)
	=> 0xD800 <= c && c <= 0xDFFF;

/++
	Returns: whether `c` is a Unicode high surrogate (lead surrogate).
+/
bool isSurrogateHi(dchar c)
	=> 0xD800 <= c && c <= 0xDBFF;

/++
	Returns: whether `c` is a Unicode low surrogate (trail surrogate).
+/
bool isSurrogateLo(dchar c)
	=> 0xDC00 <= c && c <= 0xDFFF;
