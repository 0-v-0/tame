module tame.text.encoding;

version (LDC) {
	pragma(LDC_no_moduleinfo);
}

/// Constant defining a fully decoded BOM
enum dchar utfBOM = 0xfeff;
