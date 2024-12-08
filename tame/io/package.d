module tame.io;

version (LDC) {
	pragma(LDC_no_moduleinfo);
}

public import tame.io.file,
tame.io.path,
tame.io.stdio;
