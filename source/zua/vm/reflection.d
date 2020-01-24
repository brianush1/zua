module zua.vm.reflection;
import zua.vm.engine;
import zua.vm.engine : ValueType;
import std.traits;
import std.typecons;
import std.variant;
import std.meta;
import std.conv;
import std.uuid;

private U fromLua(U, alias Default)(lazy string errorMsg, Nullable!Value nval) {
	alias T = Unqual!U;

	void error(const string expected) {
		if (expected == "") {
			throw new LuaError(Value(errorMsg ~ " (value expected)"));
		}
		else {
			const string got = nval.isNull ? "no value" : nval.get.typeStr;
			throw new LuaError(Value(errorMsg ~ " (" ~ expected ~ " expected, got " ~ got ~ ")"));
		}
	}

	static if (!is(Default == void)) {
		if (nval.isNull) {
			return cast(U) Default;
		}
	}

	static if (is(T == Nullable!K, K)) {
		if (nval.isNull)
			return cast(U) Nullable!K();

		const Value val = nval.get;

		if (val.type == ValueType.Nil)
			return cast(U) Nullable!K();

		return cast(U) fromLua!(K, Default)(errorMsg, nval).nullable;
	}
	else static if (is(T == VariantN!(n, K), size_t n, K...)) {
		static foreach (i; 0 .. K.length - 1) { // @suppress(dscanner.suspicious.length_subtraction)
			try {
				return cast(U)T(fromLua!(K[i], Default)(errorMsg, nval));
			}
			catch (LuaError e) {
			}
		}

		return cast(U) T(fromLua!(K[$ - 1], Default)(errorMsg, nval));
	}
	else static if (isNumeric!T) {
		if (nval.isNull)
			error("number");

		const Value val = nval.get;

		double num;
		if (val.type == ValueType.String) {
			try {
				num = val.str.to!double;
			}
			catch (ConvException) {
				error("number");
			}
		}
		else if (val.type == ValueType.Number) {
			num = val.num;
		}
		else
			error("number");

		return cast(U) num;
	}
	else static if (is(T == char)) {
		if (nval.isNull)
			error("string");

		const Value val = nval.get;

		string str;
		if (val.type == ValueType.String) {
			str = val.str;
		}
		else if (val.type == ValueType.Number) {
			str = val.num.to!string;
		}
		else
			error("string");

		if (str.length != 1) {
			throw new LuaError(Value(errorMsg ~ " (string of length 1 expected)"));
		}

		return cast(U) str[0];
	}
	else static if (is(T == string)) {
		if (nval.isNull)
			error("string");

		const Value val = nval.get;

		string str;
		if (val.type == ValueType.String) {
			str = val.str;
		}
		else if (val.type == ValueType.Number) {
			str = val.num.to!string;
		}
		else
			error("string");

		return cast(U) str;
	}
	else static if (is(T == bool)) {
		if (nval.isNull)
			return cast(U)false;

		return cast(U) nval.get.toBool;
	}
	else static if (is(T == TableValue)) {
		if (nval.isNull)
			error("table");

		Value val = nval.get;

		if (val.type == ValueType.Table) {
			return cast(U) val.table;
		}

		error("table");
	}
	else static if (is(T == FunctionValue)) {
		if (nval.isNull)
			error("function");

		Value val = nval.get;

		if (val.type == ValueType.Function) {
			return cast(U) val.func;
		}

		error("function");
	}
	else static if (is(T == ThreadValue)) {
		if (nval.isNull)
			error("thread");

		Value val = nval.get;

		if (val.type == ValueType.Thread) {
			return cast(U) val.thread;
		}

		error("thread");
	}
	else static if (is(T == Value)) {
		if (nval.isNull)
			error("");

		return cast(U) nval.get;
	}
	else
		static assert(0, "Unsupported type '" ~ fullyQualifiedName!T ~ "'");
	assert(0);
}

private T fromLua(T, string func, alias Default)(size_t arg, Nullable!Value val) {
	return fromLua!(T, Default)("bad argument #" ~ (arg + 1).to!string ~ " to '" ~ func ~ "'", val);
}

private Value toLua(U)(U val) {
	alias T = Unqual!U;

	static if (is(T == Nullable!K, K)) {
		if (val.isNull) {
			return Value();
		}
		else {
			return val.get.toLua;
		}
	}
	else static if (is(T == VariantN!(n, K), size_t n, K...)) {
		static foreach (i; 0 .. K.length) {
			if (auto ptr = val.peek!(K[i])) {
				static if (is(K[i] == void))
					return Value();
				else
					return toLua(*ptr);
			}
		}
		return Value();
	}
	else static if (isNumeric!T) {
		return Value(cast(double) val);
	}
	else static if (is(T == char)) {
		return Value([cast(T) val]);
	}
	else static if (is(T == string) || is(T == bool)) {
		return Value(cast(T) val);
	}
	else static if (is(T == TableValue) || is(T == FunctionValue)
		|| is(T == ThreadValue)) {
		if (val is null) return Value();
		return Value(cast(T) val);
	}
	else static if (is(T == Tuple!K, K...)) {
		Value[] res;
		static foreach (i; 0 .. T.fieldNames.length) {
			res ~= val[i].toLua;
		}
		return Value.makeTuple(res);
	}
	else static if (is(T == Value[])) {
		return Value.makeTuple(val);
	}
	else static if (is(T == K[], K)) {
		Value[] res;
		foreach (v; val) {
			res ~= v.toLua;
		}
		return Value.makeTuple(res);
	}
	else static if (is(T == Value)) {
		return cast(T) val;
	}
	else
		static assert(0, "Unsupported type '" ~ fullyQualifiedName!T ~ "'");
}

private string getPrologue(params...)() {
	string res = "";
	static foreach (i; 0 .. params.length) {
		res ~= fullyQualifiedName!(params[i]) ~ " param_" ~ i.to!string ~ ";\n";
	}
	return res;
}

private string getArgs(bool trail, params...)() {
	string res = "";
	static foreach (i; 0 .. params.length) {
		res ~= "param_" ~ i.to!string ~ ", ";
	}
	if (res == "")
		return "";
	return trail ? res : res[0 .. $ - 2];
}

/** Make a Lua function from a D function */
Value exposeFunction(alias dfunc, string funcname)() {
	alias STC = ParameterStorageClass;
	alias pstc = ParameterStorageClassTuple!dfunc;
	static foreach (i; 0 .. pstc.length) {
		static if (pstc[i] & STC.lazy_)
			static assert(0, "Lazy parameters cannot be used from Lua");
		static if (pstc[i] & STC.ref_)
			static assert(0, "Reference parameters cannot be used from Lua");
		static if (pstc[i] & STC.out_)
			static assert(0, "Out parameters cannot be used from Lua");
	}

	FunctionValue func = new FunctionValue;
	func.env = null;
	func.engine = new class Engine {

		override Value[] callf(FunctionValue, Value[] args) {
			alias variadic = variadicFunctionStyle!dfunc;
			assert(variadicFunctionStyle!dfunc == Variadic.typesafe || variadicFunctionStyle!dfunc == Variadic.no,
					"Variadic functions should be made using `T[] args...` syntax");
			static if (variadic == Variadic.typesafe) {
				alias params = Parameters!dfunc[0 .. $ - 1];
			}
			else {
				alias params = Parameters!dfunc;
			}
			mixin(getPrologue!params);
			alias ParamDefaults = ParameterDefaults!dfunc;
			static foreach (i; 0 .. params.length) {
				if (i >= args.length) {
					mixin("param_", i.to!string,
							" = fromLua!(params[i], funcname, ParamDefaults[i])(i, Nullable!Value());");
				}
				else {
					mixin("param_", i.to!string,
							" = fromLua!(params[i], funcname, ParamDefaults[i])(i, args[i].nullable);");
				}
			}

			static if (is(ReturnType!dfunc == void)) {
				alias ResType = typeof(null);
			}
			else {
				alias ResType = ReturnType!dfunc;
			}

			ResType res;

			static if (variadic == Variadic.typesafe) {
				alias Last = Parameters!dfunc[$ - 1];
				Last tuple;
				if (args.length > params.length) {
					foreach (i; params.length .. args.length) {
						tuple ~= fromLua!(ForeachType!Last, funcname, void)(i, args[i].nullable);
					}
				}
				try {
					static if (is(ReturnType!dfunc == void))
						mixin("dfunc(", getArgs!(true, params), "tuple);");
					else
						res = mixin("dfunc(", getArgs!(true, params), "tuple)");
				}
				catch (LuaError e) {
					throw e;
				}
				catch (Exception e) {
					throw new LuaError(Value(e.msg));
				}
			}
			else {
				try {
					static if (is(ReturnType!dfunc == void))
						mixin("dfunc(", getArgs!(false, params), ");");
					else
						res = mixin("dfunc(", getArgs!(false, params), ")");
				}
				catch (LuaError e) {
					throw e;
				}
				catch (Exception e) {
					throw new LuaError(Value(e.msg));
				}
			}
			static if (is(ReturnType!dfunc == void)) {
				return [];
			}
			else {
				auto luaRes = res.toLua;
				if (luaRes.type == ValueType.Tuple) {
					return luaRes.tuple;
				}
				else {
					return [luaRes];
				}
			}
		}

	};
	return Value(func);
}

unittest {
	import std.stdio : writeln;

	int add2(Nullable!int i) {
		if (i.isNull)
			return -1;
		return i.get + 2;
	}

	string sumAll(string pre, int[] args...) {
		int res = 0;
		foreach (i; args) {
			res += i;
		}
		return pre ~ res.to!string;
	}

	alias Mystery = Algebraic!(int, string);

	Mystery mystery(int x) {
		if (x < 0)
			return Mystery("invalid");
		return Mystery(x + 3);
	}

	int mystery2(Algebraic!(int, bool) val) {
		if (val.peek!int) {
			return 0;
		}
		else {
			return 1;
		}
	}

	Value m = exposeFunction!(mystery, "mystery");
	assert(m.call([Value("-6e10")]) == [Value("invalid")]);
	assert(m.call([Value("7")]) == [Value(10)]);

	Value m2 = exposeFunction!(mystery2, "mystery");
	assert(m2.call([Value("-6e10")]) == [Value(0)]);
	assert(m2.call([Value(false)]) == [Value(1)]);

	Value v = exposeFunction!(sumAll, "sumAll");
	assert(v.call([Value("3 + 5 = "), Value("3"), Value("5")]) == [
			Value("3 + 5 = 8")
			]);

	Value a = exposeFunction!(add2, "add2");
	assert(a.call([Value(5)]) == [Value(7)]);
	assert(a.call([Value("8.674")]) == [Value(10)]);
	assert(a.call([Value()]) == [Value(-1)]);
	assert(a.call([]) == [Value(-1)]);
	try {
		a.call([Value("a")]);
		assert(0);
	}
	catch (LuaError e) {
		assert(e.data == Value("bad argument #1 to 'add2' (number expected, got string)"));
	}
}
