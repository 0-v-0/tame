module tame.logger.core;

version(D_Exceptions):
import std.algorithm;
import std.datetime;
import std.range;
import std.traits;

/// Defines the importance of a log message.
enum LogLevel {
	/// detailed tracing
	trace = 1,
	/// useful information
	info = 2,
	/// potential problem
	warning = 4,
	/// recoverable _error
	error = 8,
	/// _critical _error
	critical = 16,
	/// _fatal failure
	fatal = 32,

	all = trace | info | warning | error | critical | fatal,

	default_ = info | warning | error | critical | fatal,
}

/// Returns a bit set containing the level and all levels above.
@safe
LogLevel orAbove(LogLevel level) pure {
	return [EnumMembers!LogLevel].filter!(n => (n & n - 1) == 0 && n >= level)
		.reduce!"a | b";
}

///
unittest {
	with (LogLevel) {
		assert(trace.orAbove == all);
		assert(fatal.orAbove == fatal);
	}
}

@safe
bool disabled(LogLevel level) pure {
	uint levels;

	with (LogLevel) {
		version (DisableTrace)
			levels |= trace;
		version (DisableInfo)
			levels |= info;
		version (DisableWarn)
			levels |= warning;
		version (DisableError)
			levels |= error;
		version (DisableFatal)
			levels |= fatal;
	}
	return (level & levels) != 0;
}

/** LogEntry is a aggregation combining all information associated
with a log message.
*/
struct LogEntry {
	/// local _time of the event
	SysTime time;
	/// importance of the event
	LogLevel level;
	/// the filename the log function was called from
	string file;
	/// the line number the log function was called from
	ulong line;
	/// the name of the function the log function was called from
	string fnName;
	/// the message of the log message
	const(char)[] msg;
}

alias LogSink = void delegate(in LogEntry entry);

struct Logger {
	private LogSink put;
	LogLevel levels;

	this(LogSink s, LogLevel l = LogLevel.all) {
		put = s;
		levels = l;
	}

	alias trace = append!(LogLevel.trace);
	alias info = append!(LogLevel.info);
	alias warn = append!(LogLevel.warning);
	alias error = append!(LogLevel.error);
	alias fatal = append!(LogLevel.fatal);

	private template append(LogLevel ll) {
		pragma(inline, true)
		void append(string file = __FILE__, size_t line = __LINE__, string fnName = __FUNCTION__, A...)(
			lazy A args) {
			import tame.buffer;
			import tame.format;

			static if (!ll.disabled) {
				StringSink s;
				foreach (arg; args)
					formatTo(s, arg);
				log(ll, s[], file, line, fnName);
			}
		}
	}

	void log(LogLevel ll, in char[] msg,
		string file = __FILE__, size_t line = __LINE__, string fnName = __FUNCTION__) {
		if (ll & levels)
			put(LogEntry(Clock.currTime, ll, file, line, fnName, msg));
	}
}

__gshared Logger defaultLogger;

shared static this() {
	import tame.logger.filelogger;

	defaultLogger = stderrLogger();
}

void log(string file = __FILE__, size_t line = __LINE__, string fnName = __FUNCTION__)(
	LogLevel ll, in char[] msg)
	=> defaultLogger.log!(file, line, fnName)(ll, msg);

template logFunc(LogLevel ll) {
	void logFunc(string file = __FILE__, size_t line = __LINE__, string fnName = __FUNCTION__,
		A...)(lazy A args) {
		alias f = defaultLogger.append!ll;
		__traits(child, defaultLogger, f!(file, line, fnName, A))(args);
	}
}

/// Log a message with the trace level.
alias trace = logFunc!(LogLevel.trace);
/// Ditto
alias info = logFunc!(LogLevel.info);
/// Ditto
alias warning = logFunc!(LogLevel.warning);
/// Ditto
alias error = logFunc!(LogLevel.error);
/// Ditto
alias critical = logFunc!(LogLevel.critical);
/// Ditto
alias fatal = logFunc!(LogLevel.fatal);

///
unittest {
	import std.conv : text;
	import tame.string;

	string[] s;
	auto logger = Logger((in LogEntry entry) {
		s ~= text(entry.time, " [", entry.level, "] ", entry.file, ':', entry.line, ':', entry.fnName, ' ', entry
			.msg);
	}, LogLevel.all);

	logger.log(LogLevel.trace, "trace");
	logger.log(LogLevel.info, "info");
	logger.log(LogLevel.warning, "warning");
	logger.log(LogLevel.error, "error");
	logger.log(LogLevel.critical, "critical");
	logger.log(LogLevel.fatal, "fatal");

	assert(s.length == 6);

	trace("trace");
	info("info");
	warning("warning");
	error("error");
	critical("critical");
	fatal("fatal");
}
