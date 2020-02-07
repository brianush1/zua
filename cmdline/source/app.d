import std.stdio;
import std.algorithm;
import std.typecons;
import std.conv;
import std.getopt;
import std.file;
import zua.diagnostic;
import zua;

private void execute(string filename, string source) {
	Common c = new Common(GlobalOptions.FullAccess);

	try {
		auto res = c.run(filename, source);
		Diagnostic[] diag = res[0];
		foreach (Diagnostic d; diag) {
			stderr.writeln(d.type.to!string ~ ": " ~ d.message);
			foreach (size_t[2] range; d.ranges) {
				auto t = decodeIndex(range[0], source);
				auto k = decodeIndex(range[1], source);
				t.line++;
				k.line++;
				if (t.line == k.line) {
					stderr.writeln("  Line " ~ t.line.to!string);
				}
				else {
					stderr.writeln("  Lines " ~ t.line.to!string ~ "-" ~ k.line.to!string);
				}
			}
		}
	}
	catch (LuaError e) {
		string str = e.data.toString;
		stderr.writeln("Error: " ~ str);
		ResolvedTraceframe[] stack = c.resolve(e.stack);
		stderr.writeln("  Trace begin");
		foreach_reverse (frame; stack) {
			if (!frame.filename.isNull) {
				auto t = decodeIndex(frame.start, source);
				auto k = decodeIndex(frame.end, source);
				t.line++;
				k.line++;
				if (t.line == k.line) {
					stderr.writeln("  Line " ~ t.line.to!string);
				}
				else {
					stderr.writeln("  Lines " ~ t.line.to!string ~ "-" ~ k.line.to!string);
				}
			}
		}
		stderr.writeln("  Trace end");
	}
}

void main(string[] args) {
	string file;
	bool runTests = false;

	GetoptResult helpInformation;
	
	try {
		helpInformation = getopt(
			args,
			"file|f", "A path to the file to execute", &file,
			"tests", "If provided, runs the Zua test suite", &runTests
		);
	}
	catch (Exception e) {
		stderr.writeln("Error: " ~ e.msg);
		return;
	}

	if (helpInformation.helpWanted) {
		defaultGetoptPrinter(q"(Zua command-line utility.

For bug reporting instructions, please see:
<https://github.com/brianush1/zua>.

Options:)", helpInformation.options);
		return;
	}

	if (runTests) {
		const tests = [
			import("cond.lua"),
			import("assign.lua"),
			import("tables.lua"),
			import("upvalues.lua"),
			import("execorder.lua"),
			import("op.lua"),
			import("basic.lua"),
			import("coroutine.lua"),
			import("globalenv.lua"),
			import("tablelib.lua"),
			import("stringlib.lua"),
			import("bit32lib.lua"),
			import("proxies.lua"),
		];

		foreach (s; tests) {
			execute("test.lua", s);
		}
	}
	
	if (file != "") {
		const data = readText(file);
		execute(file, data);
	}
}