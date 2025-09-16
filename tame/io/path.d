module tame.io.path;

import std.traits;

@safe pure nothrow:

/++ Returns: whether the given character is a directory separator.

	On Windows, this includes both `\` and `/`.
	On POSIX, it's just `/`.
+/
bool isDirSeparator(dchar c) {
	if (c == '/')
		return true;
	version (Windows)
		if (c == '\\')
			return true;
	return false;
}

///
unittest {
	version (Windows) {
		assert('/'.isDirSeparator);
		assert('\\'.isDirSeparator);
	} else {
		assert('/'.isDirSeparator);
		assert(!'\\'.isDirSeparator);
	}
}

/++ Returns the parent directory of `path`. On Windows, this
	includes the drive letter if present. If `path` is a relative path and
	the parent directory is the current working directory, returns `"."`.

	Params:
		path = A path name.

	Returns:
		A slice of `path` or `"."`.

	Standards:
	This function complies with
	[the POSIX requirements for the 'dirname' shell utility](http://pubs.opengroup.org/onlinepubs/9699919799/utilities/dirname.html)
	(with suitable adaptations for Windows paths).
+/
auto dirName(return in char[] path) {
	if (path.length == 0)
		return ".";

	auto p = rtrimDirSeparators(path);
	if (p.length == 0)
		return path[0 .. 1];

	version (Windows) {
		if (isUNC(p) && uncRootLength(p) == p.length)
			return p;

		if (p.length == 2 && isDriveSeparator(p[1]) && path.length > 2)
			return path[0 .. 3];
	}

	const i = lastSeparator(p);
	if (i == -1)
		return ".";
	if (i == 0)
		return p[0 .. 1];

	version (Windows) {
		// If the directory part is either d: or d:\
		// do not chop off the last symbol.
		if (isDriveSeparator(p[i]) || isDriveSeparator(p[i - 1]))
			return p[0 .. i + 1];
	}
	// Remove any remaining trailing (back)slashes.
	return rtrimDirSeparators(p[0 .. i]);
}

///
@safe unittest {
	assert(dirName("") == ".");
	assert(dirName("dir///") == ".");
	assert(dirName("dir/subdir/") == "dir");
	assert(dirName("/") == "/");
	assert(dirName("///") == "/");

	version (Windows) {
		assert(dirName(`dir\`) == `.`);
		assert(dirName(`dir\\\`) == `.`);
		assert(dirName(`dir\file`) == `dir`);
		assert(dirName(`dir\\\file`) == `dir`);
		assert(dirName(`dir\subdir\`) == `dir`);
		assert(dirName(`\dir\file`) == `\dir`);
		assert(dirName(`\file`) == `\`);
		assert(dirName(`\`) == `\`);
		assert(dirName(`\\\`) == `\`);
		assert(dirName(`d:`) == `d:`);
		assert(dirName(`d:file`) == `d:`);
		assert(dirName(`d:\`) == `d:\`);
		assert(dirName(`d:\file`) == `d:\`);
		assert(dirName(`d:\dir\file`) == `d:\dir`);
		assert(dirName(`\\server\share\dir\file`) == `\\server\share\dir`);
		assert(dirName(`\\server\share\file`) == `\\server\share`);
		assert(dirName(`\\server\share\`) == `\\server\share`);
		assert(dirName(`\\server\share`) == `\\server\share`);
	}
}

/++
	Params:
		path = A path name. It can be a string, or any random-access range of
			characters.
	Returns: The name of the file in the path name, without any leading
		directory and with an optional suffix chopped off.

	If `suffix` is specified, it will be compared to `path`
	using `filenameCmp!cs`,
	where `cs` is an optional template parameter determining whether
	the comparison is case sensitive or not.  See the
	$(LREF filenameCmp) documentation for details.

	Note:
	This function *only* strips away the specified suffix, which
	doesn't necessarily have to represent an extension.
	To remove the extension from a path, regardless of what the extension
	is, use $(LREF stripExtension).
	To obtain the filename without leading directories and without
	an extension, combine the functions like this:
	---
	assert(baseName(stripExtension("dir/file.ext")) == "file");
	---

	Standards:
	This function complies with
	[the POSIX requirements for the 'basename' shell utility](http://pubs.opengroup.org/onlinepubs/9699919799/utilities/basename.html)
	(with suitable adaptations for Windows paths).
+/
auto baseName(return in char[] path) {
	auto p1 = stripDrive(path);
	if (p1.length == 0) {
		version (Windows)
			if (isUNC(path))
				return path[0 .. 1];
		return null;
	}

	auto p2 = rtrimDirSeparators(p1);
	if (p2.length == 0)
		return p1[0 .. 1];

	return p2[lastSeparator(p2) + 1 .. p2.length];
}

///
@safe unittest {
	assert(baseName("dir/file.ext") == "file.ext");
	//assert(baseName("dir/file.ext", ".ext") == "file");
	//assert(baseName("dir/file.ext", ".xyz") == "file.ext");
	//assert(baseName("dir/filename", "name") == "file");
	assert(baseName("dir/subdir/") == "subdir");

	version (Windows) {
		assert(baseName(`d:file.ext`) == "file.ext");
		assert(baseName(`d:\dir\file.ext`) == "file.ext");
	}
}

private:

auto stripDrive(return in char[] path) {
	version (Windows) {
		if (hasDrive(path))
			return path[2 .. path.length];
		if (isUNC(path))
			return path[uncRootLength(path) .. path.length];
	}
	return path;
}

bool hasDrive(in char[] path) {
	return path.length >= 2 && isDriveSeparator(path[1]);
}

auto rtrimDirSeparators(in char[] path) {
	auto i = cast(ptrdiff_t)path.length - 1;
	while (i >= 0 && isDirSeparator(path[i]))
		--i;
	return path[0 .. i + 1];
}

unittest {
	assert(rtrimDirSeparators("//abc//") == "//abc");
}

/*  Determines whether the given character is a drive separator.

	On Windows, this is true if c is the ':' character that separates
	the drive letter from the rest of the path.  On POSIX, this always
	returns false.
*/
bool isDriveSeparator(dchar c) {
	version (Windows)
		return c == ':';
	else
		return false;
}

/*  Combines the isDirSeparator and isDriveSeparator tests. */
version (Windows)
	bool isSeparator(dchar c)
		=> isDirSeparator(c) || isDriveSeparator(c);
else version (Posix)
	alias isSeparator = isDirSeparator;

/*  Helper function that determines the position of the last
	drive/directory separator in a string.  Returns -1 if none
	is found.
*/
ptrdiff_t lastSeparator(in char[] path) {
	auto i = cast(ptrdiff_t)path.length - 1;
	while (i >= 0 && !isSeparator(path[i]))
		--i;
	return i;
}

version (Windows) {
	bool isUNC(in char[] path) {
		return path.length >= 3 && isDirSeparator(path[0]) && isDirSeparator(path[1])
			&& !isDirSeparator(path[2]);
	}

	ptrdiff_t uncRootLength(in char[] path)
	in (isUNC(path)) {
		ptrdiff_t i = 3;
		while (i < path.length && !isDirSeparator(path[i]))
			++i;
		if (i < path.length) {
			auto j = i;
			do
				++j;
			while (j < path.length && isDirSeparator(path[j]));
			if (j < path.length) {
				do
					++j;
				while (j < path.length && !isDirSeparator(path[j]));
				i = j;
			}
		}
		return i;
	}
}
