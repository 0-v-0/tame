module tame.unsafe.string;

nothrow @nogc:

template TempDup(alias s, string name = s.stringof ~ "d", size_t reserve = 0) if (is(typeof(s) : T[], T)) {
	import core.stdc.stdlib;
	import core.stdc.string;
	import std.traits : Unqual;

	static if (is(typeof(s) : T[], T))
		mixin("auto ", name, "= (cast(Unqual!T*)memcpy(alloca(",
			"(s.length + reserve) * T.sizeof), s.ptr, s.length * T.sizeof))[0 .. s.length + reserve];");
}

unittest {
	auto s = "hello";
	mixin TempDup!s;
	assert(sd == "hello", sd);
}

template TempCStr(alias s, string name = s.stringof ~ "z")
if (is(typeof(s) : const(char)[])) {
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

		static if (is(typeof(s) : const(char)[])) {
			mixin TempCStr!(s, "strz");
		} else {
			alias strz = s;
		}

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
