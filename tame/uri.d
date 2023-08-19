module tame.uri;

/// extract parameters from URL string to string[string] map, update url to strip params
auto extractParams(S)(ref S url) {
	string[string] map;
	extractParams(url, map);
	return map;
}

/// ditto
void extractParams(S, M)(ref S url, ref M params) {
	import std.string : lastIndexOf, split;

	auto qmIndex = url.lastIndexOf('?');
	if (qmIndex < 0)
		return;
	string urlParams = url[qmIndex + 1 .. $];
	url = url[0 .. qmIndex];
	foreach (item; urlParams.splitter(',')) {
		auto i = item.split('=');
		if (i >= 0)
			params[item[0 .. i]] = item[i + 1 .. $];
	}
}

S makeQueryParams(M)(M params, char delimiter = '&') {
	auto res = appender!S;
	foreach (key, value; params) {
		res ~= key;
		res ~= '=';
		res ~= value;
		res ~= delimiter;
	}
	return res[];
}
