module zua.vm.std.stdlib;
import zua.vm.std.math;
import zua.vm.std.table;
import zua.vm.std.string;
import zua.vm.std.coroutine;
import zua.vm.std.os;
import zua.vm.std.bit32;
import zua.vm.engine;
import zua.vm.reflection;
import std.typecons;
import std.variant;
import std.conv;
import std.string;

/** Flags that may be used for controlling which libraries are accessible by Lua code; can be ORed together */
enum GlobalOptions {
	FullAccess = 0,

	/** Do not provide IO access (this includes functions such as `print` and the entire `io` library) */
	NoIO = 1,

	/** Do not provide access to debug facilities */
	NoDebug = 2,

	/** Do not add backported features from Lua 5.2, such as the bit32 library */
	NoBackport = 4,

	/** Do not give users access to the `collectgarbage` function */
	NoGC = 8,
}

private void lua_assert(bool v, Nullable!string message) {
	if (!v)
		throw new Exception(message.isNull ? "assertion failed!" : message.get);
}

private Algebraic!(void, bool, double) lua_collectgarbage(Nullable!string optn, Nullable!double) {
	import core.memory : GC;

	string opt = optn.isNull ? "collect" : optn.get;
	if (opt == "collect") {
		GC.enable();
		GC.collect();
	}
	else if (opt == "stop") {
		GC.disable();
	}
	else if (opt == "restart") {
		GC.enable();
	}
	else if (opt == "count") {
		return Algebraic!(void, bool, double)(GC.stats().usedSize / 1024.0);
	}
	else if (opt == "step") {
		GC.collect();
		return Algebraic!(void, bool, double)(true);
	}
	else if (opt == "setpause" || opt == "setstepmul") {
		return Algebraic!(void, bool, double)(200.0);
	}
	else {
		throw new Exception("bad argument #1 to 'collectgarbage' (invalid option '" ~ opt ~ "')");
	}

	return Algebraic!(void, bool, double)();
}

// TODO: dofile

private void lua_error(Value message, Nullable!int) {
	if (message.type == ValueType.Number) {
		throw new LuaError(message.luaToString);
	}
	else {
		throw new LuaError(message);
	}
}

private TableValue lua_getfenv(Nullable!(Algebraic!(FunctionValue, long)) f) {
	FunctionValue caller = callstack[$ - 1].func;
	FunctionValue func;
	if (f.isNull) {
		func = caller;
	}
	else if (FunctionValue* mfunc = f.get.peek!FunctionValue) {
		func = *mfunc;
	}
	else {
		const long lvl = f.get.get!long;
		if (lvl < 0) {
			throw new Exception("bad argument #1 to 'getfenv' (level must be non-negative)");
		}
		else if (lvl == 0) {
			return *getGlobalEnvPtr;
		}
		else if (lvl > callstack.length) {
			throw new Exception("bad argument #1 to 'getfenv' (invalid level)");
		}
		else {
			func = callstack[$ - lvl].func;
		}
	}

	TableValue res = func.env;
	if (res is null) {
		return *getGlobalEnvPtr;
	}
	else {
		return res;
	}
}

private Value lua_getmetatable(Value val) {
	TableValue metatable = val.metatable;

	if (metatable is null)
		return Value();

	Value fake = metatable.get(Value("__metatable"));
	if (!fake.isNil)
		return fake;

	return Value(metatable);
}

private Value[] ipairsIterator(TableValue t, long key) {
	key++;
	Value* v = t.rawget(Value(key));
	if (v == null || v.isNil) {
		return [];
	}
	else {
		return [Value(key), *v];
	}
}

private Value ipairsIteratorValue = exposeFunction!(ipairsIterator, "?");

private Tuple!(Value, TableValue, double) lua_ipairs(TableValue input) {
	return tuple(ipairsIteratorValue, input, 0.0);
}

// TODO: load, loadfile, loadstring, module

private Value[] lua_next(TableValue table, Nullable!Value indexn) {
	Value[] res;

	if (indexn.isNull || indexn.get.isNil) {
		if (table.array.length > 0) {
			res = [Value(1), table.array[0]];
		}
		else if (table.hash.length > 0) {
			auto f = table.hash.iterator.front;
			res = [f[0], f[1]];
		}
	}
	else {
		Value key = indexn.get;
		if (key.type == ValueType.Number && key.num > 0) {
			ulong index = cast(ulong) key.num;
			if (cast(double) index == key.num) {
				index--;
				for (; index < table.array.length; ++index) {
					if (index == table.array.length - 1) { // if it's the last array element, return the first hash element
						if (table.hash.length > 0) {
							auto f = table.hash.iterator.front;
							res = [f[0], f[1]];
						}
						goto leave;
					}
					else { // if it's in the array, return the next element
						if (table.array[index + 1].isNil) continue;
						res = [Value(index + 2), table.array[index + 1]];
						goto leave;
					}
				}
			}
		}

		// if it's in the hash part:
		auto iter = table.hash.find(key);
		iter.popFront();
		if (!iter.empty) {
			auto f = iter.front;
			res = [f[0], f[1]];
		}
	}

leave:
	if (res.length == 0 || res[1].isNil) return [Value()];
	else return res;
}

private Value pairsIteratorValue = exposeFunction!(lua_next, "?");

private Value[] lua_pairs(TableValue input) {
	return [pairsIteratorValue, Value(input), Value()];
}

private Tuple!(bool, Value[]) lua_pcall(FunctionValue f, Value[] args...) {
	auto saveStack = callstack;
	auto save = running;
	callstack = [];
	scope(exit) {
		callstack = saveStack;
		running = save;
	}
	try {
		return tuple(true, f.ccall(args));
	}
	catch (LuaError e) {
		return tuple(false, [e.data]);
	}
}

private void lua_print(Value[] args...) {
	import std.stdio : writeln;

	string s;
	foreach (v; args) {
		Value strv = v.luaToString;
		if (strv.type != ValueType.String) {
			throw new Exception("'tostring' must return a string to 'print'");
		}
		s ~= "\t" ~ strv.str;
	}
	writeln(s == "" ? s : s[1 .. $]);
}

private bool lua_rawequal(Value a, Value b) {
	return a == b;
}

private Value lua_rawget(TableValue table, Value index) {
	Value* res = table.rawget(index);
	if (res == null)
		return Value();
	return *res;
}

private TableValue lua_rawset(TableValue table, Value index, Value value) {
	if (index.isNil)
		throw new Exception("table index is nil");
	table.rawset(index, value);
	return table;
}

// TODO: require

private Algebraic!(Value[], long) lua_select(Algebraic!(long, string) opt, Value[] args...) {
	if (opt.peek!string && opt.get!string == "#") {
		return args.length
			.to!long
			.Algebraic!(Value[], long);
	}
	else if (opt.peek!long) {
		const long index = opt.get!long;
		if (index > cast(long)args.length)
			return (cast(Value[])[]).Algebraic!(Value[], long);
		else if (index < 0) {
			if (-index > cast(long)args.length) {
				throw new Exception("bad argument #1 to 'select' (index out of range)");
			}
			return args[$ + index .. $].Algebraic!(Value[], long);
		}
		else if (index == 0)
			throw new Exception("bad argument #1 to 'select' (index out of range)");
		else
			return args[index - 1 .. $].Algebraic!(Value[], long);
	}
	else {
		throw new Exception("bad argument #1 to 'select' (number expected, got string)");
	}
}

private Algebraic!(FunctionValue, Tuple!()) lua_setfenv(Algebraic!(FunctionValue, long) f, TableValue env) {
	FunctionValue func;
	if (FunctionValue* mfunc = f.peek!FunctionValue) {
		func = *mfunc;
	}
	else {
		const long lvl = f.get!long;
		if (lvl < 0) {
			throw new Exception("bad argument #1 to 'setfenv' (level must be non-negative)");
		}
		else if (lvl == 0) {
			*getGlobalEnvPtr = env;
			return Algebraic!(FunctionValue, Tuple!())(tuple());
		}
		else if (lvl > callstack.length) {
			throw new Exception("'setfenv' cannot change environment of given object");
		}
		else {
			func = callstack[$ - lvl].func;
		}
	}

	if (func.env is null) {
		throw new Exception("'setfenv' cannot change environment of given object");
	}
	else {
		func.env = env;
		return Algebraic!(FunctionValue, Tuple!())(func);
	}
}

private TableValue lua_setmetatable(TableValue table, Nullable!Value meta) {
	TableValue newMetatable;
	immutable string errorMsg = "bad argument #2 to 'setmetatable' (nil or table expected)";
	if (meta.isNull)
		throw new Exception(errorMsg);
	else {
		if (meta.get.type == ValueType.Nil) {
			newMetatable = null;
		}
		else if (meta.get.type == ValueType.Table) {
			newMetatable = meta.get.table;
		}
		else {
			throw new Exception(errorMsg);
		}
	}

	TableValue metatable = table.metatable;

	if (metatable !is null && !metatable.get(Value("__metatable")).isNil) {
		throw new Exception("cannot change a protected metatable");
	}

	table.metatable = newMetatable;
	return table;
}

private Nullable!double lua_tonumber(Value arg, Nullable!int b) {
	const int base = b.isNull ? 10 : b.get;
	if (base == 10) {
		if (arg.type == ValueType.Number) {
			return arg.num.nullable;
		}
		else if (arg.type == ValueType.String) {
			string str = arg.str.strip;
			try {
				double res = parse!double(str);
				if (str != "")
					return Nullable!double();
				return res.nullable;
			}
			catch (ConvException e) {
				return Nullable!double();
			}
		}
		else {
			return Nullable!double();
		}
	}
	else {
		if (base < 2 || base > 36) {
			throw new Exception("bad argument #2 to 'tonumber' (base out of range)");
		}

		string str;
		if (arg.type == ValueType.String) {
			str = arg.str;
		}
		else if (arg.type == ValueType.Number) {
			str = arg.num.to!string;
		}
		else {
			throw new Exception(
					"bad argument #1 to 'tonumber' (string expected, got " ~ arg.typeStr ~ ")");
		}

		str = str.strip;

		try {
			double res = cast(double) parse!long(str, cast(uint) base);
			if (str != "")
				return Nullable!double();
			return res.nullable;
		}
		catch (ConvException e) {
			return Nullable!double();
		}
	}
}

private Value lua_tostring(Value arg) {
	return arg.luaToString;
}

private string lua_type(Value arg) {
	return arg.typeStr;
}

private Value[] lua_unpack(TableValue arg, Nullable!size_t ni, Nullable!size_t nj) {
	size_t i, j;

	if (ni.isNull)
		i = 1;
	else
		i = ni.get;

	if (nj.isNull)
		j = cast(size_t) arg.length.num;
	else
		j = nj.get;

	Value[] res;
	res.reserve(j - i + 1);
	foreach (idx; i .. j + 1) {
		Value* val = arg.rawget(Value(idx));
		if (val) {
			res ~= *val;
		}
		else {
			res ~= Value();
		}
	}
	return res;
}

private Tuple!(bool, Value[]) lua_xpcall(FunctionValue f, FunctionValue err) {
	auto saveStack = callstack;
	auto save = running;
	callstack = [];
	scope(exit) {
		callstack = saveStack;
		running = save;
	}
	try {
		return tuple(true, f.ccall([]));
	}
	catch (LuaError e) {
		try {
			callstack = e.fullstack[0 .. $ - 1];
			running = e.fullstack[$ - 1].func;
			return tuple(false, err.rawcall([e.data]));
		}
		catch (LuaError e2) {
			return tuple(false, [Value("error in error handling")]);
		}
	}
}

/** Create a new environment with standard functions */
TableValue stdenv(GlobalOptions context) {
	TableValue env = new TableValue;
	env.set(Value("_G"), Value(env));
	env.set(Value("_VERSION"), Value("Lua 5.1"));
	env.set(Value("_ZUAVERSION"), Value("Zua 1.0"));

	env.set(Value("assert"), exposeFunction!(lua_assert, "assert"));

	if ((context & GlobalOptions.NoGC) == 0) {
		env.set(Value("collectgarbage"), exposeFunction!(lua_collectgarbage, "collectgarbage"));
	}

	env.set(Value("error"), exposeFunction!(lua_error, "error"));
	env.set(Value("getfenv"), exposeFunction!(lua_getfenv, "getfenv"));
	env.set(Value("getmetatable"), exposeFunction!(lua_getmetatable, "getmetatable"));
	env.set(Value("ipairs"), exposeFunction!(lua_ipairs, "ipairs"));
	env.set(Value("next"), exposeFunction!(lua_next, "next"));
	env.set(Value("pairs"), exposeFunction!(lua_pairs, "pairs"));
	env.set(Value("pcall"), exposeFunction!(lua_pcall, "pcall"));

	if ((context & GlobalOptions.NoIO) == 0) {
		env.set(Value("print"), exposeFunction!(lua_print, "print"));
	}

	env.set(Value("rawequal"), exposeFunction!(lua_rawequal, "rawequal"));
	env.set(Value("rawset"), exposeFunction!(lua_rawset, "rawset"));
	env.set(Value("rawget"), exposeFunction!(lua_rawget, "rawget"));
	env.set(Value("select"), exposeFunction!(lua_select, "select"));
	env.set(Value("setfenv"), exposeFunction!(lua_setfenv, "setfenv"));
	env.set(Value("setmetatable"), exposeFunction!(lua_setmetatable, "setmetatable"));
	env.set(Value("tonumber"), exposeFunction!(lua_tonumber, "tonumber"));
	env.set(Value("tostring"), exposeFunction!(lua_tostring, "tostring"));
	env.set(Value("type"), exposeFunction!(lua_type, "type"));
	env.set(Value("unpack"), exposeFunction!(lua_unpack, "unpack"));
	env.set(Value("xpcall"), exposeFunction!(lua_xpcall, "xpcall"));

	env.set(Value("math"), mathlib);
	env.set(Value("table"), tablelib);
	env.set(Value("string"), stringlib);
	env.set(Value("coroutine"), coroutinelib);
	env.set(Value("os"), oslib);

	if ((context & GlobalOptions.NoBackport) == 0) {
		env.set(Value("bit32"), bit32lib);
	}

	return env;
}
