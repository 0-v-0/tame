module tame.unsafe.string;

nothrow @nogc:

template TempDup(alias s, string name = s.stringof ~ "d") {
	import core.stdc.stdlib;
	import core.stdc.string;
	import std.traits : Unqual;

	mixin("auto ", name,
		"= (cast(Unqual!(typeof(s[0]))*)memcpy(alloca(s.length), s.ptr, s.length))[0 .. s.length];");
}

unittest {
	auto s = "hello";
	mixin TempDup!s;
	assert(sd == "hello", sd);
}

template TempCStr(alias s, string name = s.stringof ~ "z") {
	import core.stdc.stdlib;
	import core.stdc.string;

	mixin("auto ", name, "= cast(char*)memcpy(alloca(s.length + 1), s.ptr, s.length);");
	int _ = mixin(name)[s.length] = 0;
}

unittest {
	import core.stdc.string;

	auto s = "hello";
	mixin TempCStr!s;
	assert(strcmp(sz, "hello") == 0);
}

version (Windows) {
	import core.sys.windows.core;

	template TempWCStr(alias s, string name = s.stringof ~ "w") {
		import core.stdc.stdlib;

		mixin TempCStr!(s, "strz");

		// Find out how many characters there is to convert to UTF-16
		int reqLen = MultiByteToWideChar(CP_UTF8, 0, strz, -1, null, 0);
		mixin("auto ", name, "= cast(wchar*)alloca(reqLen * wchar.sizeof);");
		// Convert to UTF-16
		int _ = MultiByteToWideChar(CP_UTF8, 0, strz, -1, mixin(name), reqLen);
	}

	unittest {
		auto s = "hello";
		mixin TempWCStr!s;
		assert(sw[0 .. 6] == "hello\0"w);
	}
}
