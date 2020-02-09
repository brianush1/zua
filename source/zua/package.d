module zua;
public import zua.vm.engine : Traceframe, LuaError;
public import zua.vm.std.stdlib : GlobalOptions;
public import zua.interop : DConsumable;
public import zua.interop.table : Table;
import zua.vm.engine : Value, TableValue;
import zua.interop;
import zua.compiler.sourcemap;
import zua.vm.std.stdlib;
import zua.diagnostic;
import std.algorithm;
import std.array;
import std.typecons;
import std.uuid;
import std.traits;

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
		import zua.parser.analysis : performAnalysis;
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
		performAnalysis(res.diagnostics, toplevel);
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
	Table env;

	/** Create a new Client */
	this(GlobalOptions context) {
		env = DConsumable(Value(stdenv(context))).get!Table;
	}

	/** Run a bytecode unit */
	DConsumable[] run(BCUnit unit, DConsumable[] args) {
		import zua.vm.vm : VmEngine;

		VmEngine engine = new VmEngine(unit.content, unit.id);
		return engine.getToplevel(env._internalTable.table)
			.ccall(args.map!(x => x.makeInternalValue).array).makeConsumable;
	}

	/** Run a bytecode unit with the given parameters */
	DConsumable[] run(T...)(BCUnit unit, T args) {
		import zua.vm.vm : VmEngine;

		VmEngine engine = new VmEngine(unit.content, unit.id);
		Value[] luaArgs;
		luaArgs.reserve(T.length);
		static foreach (i; 0..T.length) {
			static assert(isConvertible!(T[i]));
			luaArgs ~= DConsumable(args[i]).makeInternalValue;
		}
		return engine.getToplevel(env._internalTable.table).ccall(luaArgs).makeConsumable;
	}
}

/** A class capable both of executing and producing bytecode */
final class Common {
	/** The server component of this Common */
	Server server;

	/** The client component of this Common */
	Client client;

	alias client this;

	/** Create a new Common */
	this(GlobalOptions context) {
		server = new Server;
		client = new Client(context);
	}

	/** Run some source */
	Tuple!(Diagnostic[], DConsumable[]) run(string filename, string source, DConsumable[] args) {
		auto compiled = server.compile(filename, source);
		if (compiled.unit is null) {
			return tuple(compiled.diagnostics, cast(DConsumable[])[]);
		}
		else {
			return tuple(compiled.diagnostics, client.run(compiled.unit, args));
		}
	}

	/** Run some source */
	Tuple!(Diagnostic[], DConsumable[]) run(T...)(string filename, string source, T args) {
		auto compiled = server.compile(filename, source);
		if (compiled.unit is null) {
			return tuple(compiled.diagnostics, cast(DConsumable[])[]);
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