module tame.text;

version (LDC) {
	pragma(LDC_no_moduleinfo);
}

public import tame.text.ascii,
tame.text.encoding,
tame.text.uni,
tame.text.uri;
