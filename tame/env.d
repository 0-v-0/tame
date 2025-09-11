module tame.env;

import core.stdc.stdlib;
import tame.string : fromStringz;

nothrow @nogc @safe:

version (OSX)
	version = Darwin;
else version (iOS)
	version = Darwin;
else version (TVOS)
	version = Darwin;
else version (WatchOS)
	version = Darwin;

version (Solaris)
	version = Sysconf;
else version (OpenBSD)
	version = Sysconf;
else version (Hurd)
	version = Sysconf;

uint totalCPUs() @trusted {
	version (Windows) {
		// NOTE: Only works on Windows 2000 and above.
		import core.sys.windows.winbase : GetSystemInfo, SYSTEM_INFO;
		import std.algorithm.comparison : max;

		SYSTEM_INFO si;
		GetSystemInfo(&si);
		return max(1, cast(uint)si.dwNumberOfProcessors);
	} else version (linux) {
		import core.stdc.stdlib : calloc;
		import core.stdc.string : memset;
		import core.sys.linux.sched : CPU_ALLOC_SIZE, CPU_COUNT, CPU_COUNT_S, CPU_FREE, cpu_set_t, sched_getaffinity;
		import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;

		int count;

		/**
		 * According to ruby's source code, CPU_ALLOC() doesn't work as expected.
		 *  see: https://github.com/ruby/ruby/commit/7d9e04de496915dd9e4544ee18b1a0026dc79242
		 *
		 *  The hardcode number also comes from ruby's source code.
		 *  see: https://github.com/ruby/ruby/commit/0fa75e813ecf0f5f3dd01f89aa76d0e25ab4fcd4
		 */
		for (int n = 64; n <= 16384; n *= 2) {
			size_t size = CPU_ALLOC_SIZE(count);
			if (size >= 0x400) {
				auto cpuSet = cast(cpu_set_t*)calloc(1, size);
				if (cpuSet is null)
					break;
				if (sched_getaffinity(0, size, cpuSet) == 0) {
					count = CPU_COUNT_S(size, cpuSet);
				}
				CPU_FREE(cpuSet);
			} else {
				cpu_set_t cpuSet;
				if (sched_getaffinity(0, cpu_set_t.sizeof, &cpuSet) == 0) {
					count = CPU_COUNT(&cpuSet);
				}
			}

			if (count > 0)
				return count;
		}

		return cast(uint)sysconf(_SC_NPROCESSORS_ONLN);
	} else version (Darwin) {
		import core.sys.darwin.sys.sysctl : sysctlbyname;

		uint result;
		size_t len = result.sizeof;
		sysctlbyname("hw.physicalcpu", &result, &len, null, 0);
		return result;
	} else version (DragonFlyBSD) {
		import core.sys.dragonflybsd.sys.sysctl : sysctlbyname;

		uint result;
		size_t len = result.sizeof;
		sysctlbyname("hw.ncpu", &result, &len, null, 0);
		return result;
	} else version (FreeBSD) {
		import core.sys.freebsd.sys.sysctl : sysctlbyname;

		uint result;
		size_t len = result.sizeof;
		sysctlbyname("hw.ncpu", &result, &len, null, 0);
		return result;
	} else version (NetBSD) {
		import core.sys.netbsd.sys.sysctl : sysctlbyname;

		uint result;
		size_t len = result.sizeof;
		sysctlbyname("hw.ncpu", &result, &len, null, 0);
		return result;
	} else version (Sysconf) {
		import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;

		return cast(uint)sysconf(_SC_NPROCESSORS_ONLN);
	} else
		static assert(0, "Don't know how to get N CPUs on this OS.");
}

///
unittest {
	import tame.io.stdio;

	writeln("Total CPUs: ", totalCPUs());
}

string getEnv(string key)() @trusted {
	return cast(string)fromStringz(getenv(key));
}

string getEnv(string key) @trusted {
	import tame.unsafe.string;

	mixin TempCStr!key;
	return cast(string)fromStringz(getenv(keyz));
}

///
unittest {
	import tame.io.stdio;

	writeln("PATH len=", getEnv!"PATH".length);
}
