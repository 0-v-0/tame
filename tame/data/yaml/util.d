module tame.data.yaml.util;

@safe nothrow pure:

// Position in a YAML stream, used for error messages.
struct Mark {
	import std.algorithm;

@safe nothrow pure:
	/// Construct a Mark with specified line and column in the file.
	this(uint ln, uint col) @nogc {
		line = cast(ushort)min(ushort.max, ln);
		// This *will* overflow on extremely wide files but saves CPU time
		// (mark ctor takes ~5% of time)
		column = cast(ushort)col;
	}

	/// Get a string representation of the mark.
	string toString() const {
		import std.array;

		auto a = appender!string();
		toString(a);
		return a[];
	}

	void toString(R)(ref R r) const {
		import tame.format;

		// Line/column numbers start at zero internally, make them start at 1.
		void clamped(ushort v) {
			formatTo(r, v + 1);
			if (v == ushort.max)
				r ~= " or higher";
		}

		r ~= "line ";
		clamped(line);
		r.put(",column ");
		clamped(column);
	}

package:
	/// Line number
	ushort line;
	/// Column number
	ushort column;
}

package:

@nogc:
// dfmt off

/// Convert a YAML escape to a dchar
dchar fromEscape(dchar escape) {
	switch(escape) {
	case '0':  return '\0';
	case 'a':  return '\x07';
	case 'b':  return '\x08';
	case 't':
	case '\t': return '\x09';
	case 'n':  return '\x0A';
	case 'v':  return '\x0B';
	case 'f':  return '\x0C';
	case 'r':  return '\x0D';
	case 'e':  return '\x1B';
	case ' ':
	case '"':
	case '\\': return escape;
	case 'N':  return '\x85';
	case '_':  return '\xA0';
	case 'L':  return '\u2028';
	case 'P':  return '\u2029';
	default:   return '\uFFFF';
	}
}

/// Get the length of a hexadecimal number determined by its hex code.
///
/// Need a function as associative arrays don't work with @nogc.
/// (And this may be even faster with a function.)
auto escapeHexLength(dchar hexCode) {
	switch(hexCode) {
	case 'x': return 2;
	case 'u': return 4;
	case 'U': return 8;
	default: return 0;
	}
}
