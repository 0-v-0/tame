module tame.unsafe;

version (LDC) {
	pragma(LDC_no_moduleinfo);
}

public import tame.unsafe.ptrop,
tame.unsafe.scoped;
