module zua;
public import zua.vm.engine : Traceframe, LuaError, ValueType, Value, TableValue, FunctionValue, ThreadValue;
public import zua.vm.std.stdlib : GlobalOptions;
import zua.compiler.sourcemap;
import zua.vm.std.stdlib;
import zua.diagnostic;
import std.typecons;
import std.uuid;

/*

Zua uses a client-server model to secure debug information while still keeping it accessible to developers.
The client sends the server the bytecode location where an error (or other diagnostic) occurred, and the server decodes this into source location.
How the client and server communicate is up to the library user to implement.
However, if they are running on the same machine, there is a class (Common) that combines the two.

*/

/** A bytecode unit; consists of an engine ID and the actual bytecode content */
final class BCUnit {
	/** Engine ID */
	UUID id;

	/** Raw content */
	immutable(ubyte)[] content;
}

/** Represents a single trace frame with resolved debugging symbols */
struct ResolvedTraceframe {
	/** The file in which this frame occurred, or null if it is a D function */
	Nullable!string filename;

	/** The start index of the AST node being executed at the time of this stack frame */
	size_t start;

	/** The end index of the AST node being executed at the time of this stack frame */
	size_t end;
}

/** The result of a compilation */
final class CompilationResult {
	/** Bytecode unit; MAY BE NULL if any errors occurred during compilation */
	BCUnit unit;

	/** A list of diagnostic messages */
	Diagnostic[] diagnostics;
}

/** A bytecode-producing server */
final class Server {
	private string[UUID] fileMap;
	private SourceMap[UUID] sourceMaps;

	/** Compile source code into a CompilationResult */
	CompilationResult compile(string filename, string source) {
		import zua.parser.lexer : Lexer;
		import zua.parser.parser : Parser;
		import zua.compiler.ir : compileAST;
		import zua.compiler.compiler : compile;

		auto id = randomUUID();
		auto res = new CompilationResult;
		fileMap[id] = filename;
		auto map = new SourceMap;
		sourceMaps[id] = map;
		Lexer lexer = new Lexer(source, res.diagnostics);
		Parser parser = new Parser(lexer, res.diagnostics);
		auto toplevel = parser.toplevel();
		foreach (d; res.diagnostics) {
			if (d.type == DiagnosticType.Error) {
				res.unit = null;
				return res;
			}
		}
		res.unit = new BCUnit;
		res.unit.id = id;
		auto func = compileAST(toplevel);
		res.unit.content = compile(map, func);
		return res;
	}

	/** Resolve the stack trace of a Lua error */
	ResolvedTraceframe[] resolve(Traceframe[] stack) {
		ResolvedTraceframe[] res;
		foreach (frame; stack) {
			ResolvedTraceframe resf;
			string* filename = frame.id in fileMap;
			if (filename == null) {
				resf.filename = Nullable!string();
			}
			else {
				const indices = sourceMaps[frame.id].resolve(frame.ip);
				resf.start = indices.start;
				resf.end = indices.end;
				resf.filename = (*filename).nullable;
			}
			res ~= resf;
		}
		return res;
	}
}

/** An executing client */
final class Client {
	/** The global environment of this client */
	TableValue globalEnv;

	/** Create a new Client */
	this(GlobalOptions context) {
		globalEnv = stdenv(context);
	}

	/** Run a bytecode unit */
	Value[] run(BCUnit unit, Value[] args = []) {
		import zua.vm.vm : VmEngine;

		VmEngine engine = new VmEngine(unit.content, unit.id);
		return engine.getToplevel(globalEnv).ccall(args);
	}
}

/** A class capable both of executing and producing bytecode */
final class Common {
	private Server server;
	private Client client;

	/** The global environment of this client */
	TableValue globalEnv;

	/** Create a new Common */
	this(GlobalOptions context) {
		server = new Server;
		client = new Client(context);
		globalEnv = client.globalEnv;
	}

	/** Run some source */
	Tuple!(Diagnostic[], Value[]) run(string filename, string source, Value[] args = []) {
		auto compiled = server.compile(filename, source);
		if (compiled.unit is null) {
			return tuple(compiled.diagnostics, cast(Value[])[]);
		}
		else {
			return tuple(compiled.diagnostics, client.run(compiled.unit, args));
		}
	}

	/** Resolve the stack trace of a Lua error */
	ResolvedTraceframe[] resolve(Traceframe[] stack) {
		return server.resolve(stack);
	}
}