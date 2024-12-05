module tame.uri;

import std.ascii;
import std.range;

/++
Generates an identifier suitable to use as within a URL.

The resulting string will contain only ASCII lower case alphabetic or
numeric characters, as well as dashes (-). Every sequence of
non-alphanumeric characters will be replaced by a single dash. No dashes
will be at either the front or the back of the result string.
+/
struct SlugRange(R) if (isInputRange!R && is(typeof(R.init.front) == dchar)) {
	this(R input) {
		r = input;
		skipNonAlphaNum();
	}

	@property {
		bool empty() const => !dash && r.empty;

		auto front() const => dash ? '-' : toLower(r.front);
	}

	void popFront() {
		if (dash) {
			dash = false;
			return;
		}

		r.popFront();
		if (skipNonAlphaNum() && !r.empty)
			dash = true;
	}

private:
	R r;
	bool dash;

	bool skipNonAlphaNum() {
		import std.ascii;

		bool skip;
		while (!r.empty) {
			auto c = r.front;
			if (isAlphaNum(c))
				return skip;
			r.popFront();
			skip = true;
		}
		return skip;
	}
}

auto asSlug(R)(R text) => SlugRange!R(text);

unittest {
	import std.algorithm : equal;

	assert("".asSlug.equal(""));
	assert(".,-".asSlug.equal(""));
	assert("abc".asSlug.equal("abc"));
	assert("aBc123".asSlug.equal("abc123"));
	assert("....aBc...123...".asSlug.equal("abc-123"));
}

/// extract parameters from URL string to string[string] map, update url to strip params
auto extractParams(S)(ref S url) {
	string[string] map;
	extractParams(url, map);
	return map;
}

/// ditto
auto extractParams(S)(S url) {
	string[string] map;
	extractParams(url, map);
	return map;
}

///
unittest {
	auto map = extractParams("http://example.com/?a=1&b=2");
	assert(map["a"] == "1");
	assert(map["b"] == "2");
	assert(map.length == 2);
}

/// ditto
void extractParams(S, M)(ref S url, ref M params) {
	import std.algorithm;
	import std.string;

	auto qmIndex = url.lastIndexOf('?');
	if (qmIndex < 0)
		return;
	string urlParams = url[qmIndex + 1 .. $];
	url = url[0 .. qmIndex];
	foreach (item; urlParams.splitter('&')) {
		auto i = item.indexOf('=');
		if (i >= 0)
			params[item[0 .. i]] = item[i + 1 .. $];
	}
}

void putQueryParams(R, M)(R res, M params, char delimiter = '&') {
	foreach (key, value; params) {
		res ~= key;
		res ~= '=';
		res ~= value;
		res ~= delimiter;
	}
}
