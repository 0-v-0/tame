module tame.logger.filelogger;

import std.datetime;
import tame.format;
import tame.io.file;
import tame.io.stdio;
import tame.logger.core;

auto fileLogger(File f, LogLevel levels = LogLevel.default_) {
	return Logger((in LogEntry entry) {
		with (entry) {
			toISOString(f, time);
			f.writeln(text(" [", level, "] ",
				file, ':', line, ':', fnName, ' ', msg));
		}
		f.flush();
	}, levels);
}

auto stderrLogger(LogLevel levels = LogLevel.info.orAbove)
	=> fileLogger(stderr, levels);

auto stdoutLogger(LogLevel levels = LogLevel.info.orAbove)
	=> fileLogger(stdout, levels);

private:

void toISOString(R)(R o, in SysTime time) {
	const dt = cast(DateTime)time;
	const fsec = time.fracSecs.total!"msecs";

	o.formatTo!"%04d-%02d-%02dT%02d:%02d:%02d.%03d"(
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second,
		fsec);
}
