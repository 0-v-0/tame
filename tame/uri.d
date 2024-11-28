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
		_input = input;
		skipNonAlphaNum();
	}

	@property {
		bool empty() const => !_dash && _input.empty;

		auto front() const => _dash ? '-' : toLower(_input.front);
	}

	void popFront() {
		if (_dash) {
			_dash = false;
			return;
		}

		_input.popFront();
		if (skipNonAlphaNum() && !_input.empty)
			_dash = true;
	}

private:
	R _input;
	bool _dash;

	bool skipNonAlphaNum() {
		import std.ascii;

		bool skip;
		while (!_input.empty) {
			auto c = _input.front;
			if (isAlphaNum(c))
				return skip;
			_input.popFront();
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
