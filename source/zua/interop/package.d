module zua.interop;
import zua.interop.table;
import zua.interop.userdata;
import zua.interop.functions;
import zua.vm.engine;
import zua.vm.engine : ValueType;
import std.variant;
import std.traits;
import std.typecons;
import std.uni;
import std.conv;
import std.algorithm.iteration;
import std.range;

alias DConsumableFunction = DConsumable[] delegate(DConsumable[] args);

/** Returns true if the type is convertible to/from a DConsumable; false otherwise */
enum bool isConvertible(T) =
	is(Unqual!T == typeof(null))
	|| is(Unqual!T == void)
	|| isNumeric!T
	|| is(Unqual!T == string)
	|| is(Unqual!T == wstring)
	|| is(Unqual!T == dstring)
	|| is(Unqual!T == bool)
	|| is(Unqual!T == Table)
	|| is(Unqual!T == Userdata)
	|| is(Unqual!T == DConsumable)
	|| is(Unqual!T == Value)
	|| isSomeFunction!(Unqual!T);

/** Returns the ValueType that corresponds to the given D-side type, or null if the given D-side type is dynamic */
Nullable!ValueType getValueType(T)() if (isConvertible!T) {
	alias U = Unqual!T;
	static if (is(U == typeof(null))) {
		return Nullable!ValueType(ValueType.Nil);
	}
	else static if (is(U == void)) {
		return Nullable!ValueType(ValueType.Nil);
	}
	else static if (isNumeric!T) {
		return Nullable!ValueType(ValueType.Number);
	}
	else static if (is(U == string) || is(U == wstring) || is(U == dstring)) {
		return Nullable!ValueType(ValueType.String);
	}
	else static if (is(U == bool)) {
		return Nullable!ValueType(ValueType.Boolean);
	}
	else static if (is(U == Table)) {
		return Nullable!ValueType(ValueType.Table);
	}
	else static if (is(U == Userdata)) {
		return Nullable!ValueType(ValueType.Userdata);
	}
	else static if (is(U == DConsumable) || is(U == Value)) {
		return Nullable!ValueType();
	}
	else static assert(0);
}

/** Convert a ValueType to its canonical string form */
string valueTypeToString(ValueType type) {
	return type.to!string.toLower;
}

/** A type that is consumable by D code without much fuss */
struct DConsumable {

	private Value internalValue;

	/** The value of this DConsumable */
	Algebraic!(
		typeof(null),
		double,
		string,
		bool,
		Table,
		Userdata,
		DConsumableFunction,
	) value;

	alias value this;

	/** Create a new DConsumable from the given type */
	this(T, string preferredName = "?")(T rawValue) if (isConvertible!T) {
		alias U = Unqual!T;
		U v = cast(U)rawValue;

		static if (is(U == typeof(null))) {
			this(Value(), cast(typeof(value))null);
		}
		else static if (isNumeric!T) {
			double dvalue = v.to!double;
			this(Value(dvalue), cast(typeof(value))dvalue);
		}
		else static if (is(U == string) || is(U == wstring) || is(U == dstring)) {
			string svalue = v.to!string;
			this(Value(svalue), cast(typeof(value))svalue);
		}
		else static if (is(U == bool)) {
			this(Value(v), cast(typeof(value))v);
		}
		else static if (is(U == Table)) {
			this(v._internalTable, cast(typeof(value))v);
		}
		else static if (is(U == Userdata)) {
			this(v._internalUserdata, cast(typeof(value))v);
		}
		else static if (is(U == DConsumable)) {
			this(v.internalValue, cast(typeof(value))v.value);
		}
		else static if (is(U == Value)) {
			DConsumable dvalue;

			switch (v.type) {
			case ValueType.Nil: dvalue = DConsumable(v, cast(typeof(DConsumable.value))null); break;
			case ValueType.Number: dvalue = DConsumable(v, cast(typeof(DConsumable.value))v.num); break;
			case ValueType.String: dvalue = DConsumable(v, cast(typeof(DConsumable.value))v.str); break;
			case ValueType.Boolean: dvalue = DConsumable(v, cast(typeof(DConsumable.value))v.boolean); break;
			case ValueType.Table: dvalue = DConsumable(v, cast(typeof(DConsumable.value))Table(v)); break;
			case ValueType.Userdata: dvalue = DConsumable(v, cast(typeof(DConsumable.value))Userdata(v)); break;
			case ValueType.Function:
				dvalue = DConsumable(v, cast(typeof(DConsumable.value))delegate(DConsumable[] args) {
					Value[] luaArgs;
					luaArgs.reserve(luaArgs.length);
					foreach (i; 0..args.length) {
						luaArgs ~= makeInternalValue(args[i]);
					}
					Value[] luaRes = v.func.ccall(luaArgs);
					DConsumable[] res;
					res.reserve(luaRes.length);
					foreach (i; 0..luaRes.length) {
						res ~= DConsumable(luaRes[i]);
					}
					return res;
				});
				break;
			// case ValueType.Thread:
			// TODO: this
			default: assert(0);
			}

			this(dvalue);
		}
		else static if (isSomeFunction!U) {
			DConsumable[] luaFunction(DConsumable[] consumableArgs) {
				try {
					auto args = convertParameters!(U, preferredName)(consumableArgs);
					static if (is(ReturnType!U == void)) {
						v(args.expand);
						return [];
					}
					else {
						return v(args.expand).convertReturn!U;
					}
				}
				catch (Exception e) {
					if (is(e : LuaError)) {
						throw e;
					}
					else {
						throw new LuaError(Value(e.msg));
					}
				}
			}

			FunctionValue funcValue = new FunctionValue;
			funcValue.env = null;
			funcValue.engine = new class Engine {
				override Value[] callf(FunctionValue, Value[] args) {
					DConsumable[] consumableArgs;
					consumableArgs.reserve(args.length);
					foreach (v; args) {
						consumableArgs ~= DConsumable(v);
					}
					DConsumable[] consumableResult = luaFunction(consumableArgs);
					Value[] res;
					res.reserve(consumableResult.length);
					foreach (v; consumableResult) {
						res ~= v.internalValue;
					}
					return res;
				}
			};

			this(Value(funcValue), cast(typeof(DConsumable.value))&luaFunction);
		}
		else static assert(0);
	}

	private this(Value internalValue, typeof(value) value) {
		this.internalValue = internalValue;
		this.value = value;
	}

	/** Convert the DConsumable to a native D type, possibly failing; if exact, type coercion is not performed */
	Nullable!T convert(T, bool exact = false)() const {
		alias U = Unqual!T;
		static if (is(U == typeof(null))) {
			if (internalValue.type == ValueType.Nil) return cast(Nullable!T)null;
			else return Nullable!T();
		}
		else static if (isNumeric!T) {
			if (internalValue.type == ValueType.Number) return cast(Nullable!T)(internalValue.num.to!U);
			else if (internalValue.type == ValueType.String && !exact) {
				try {
					return cast(Nullable!T)(internalValue.str.to!U);
				}
				catch (ConvException e) {
					return Nullable!T();
				}
			}
			else return Nullable!T();
		}
		else static if (is(U == string) || is(U == wstring) || is(U == dstring)) {
			if (internalValue.type == ValueType.String) return cast(Nullable!T)(internalValue.str.to!U);
			else if (internalValue.type == ValueType.Number && !exact) return cast(Nullable!T)(internalValue.num.to!U);
			else return Nullable!T();
		}
		else static if (is(U == bool)) {
			static if (exact) {
				if (internalValue.type == ValueType.Boolean) {
					return Nullable!T(internalValue.boolean);
				}
				else {
					return Nullable!T();
				}
			}
			else {
				if (internalValue.type == ValueType.Nil || (internalValue.type == ValueType.Boolean && !internalValue.boolean)) {
					return Nullable!T(false);
				}
				else {
					return Nullable!T(true);
				}
			}
		}
		else static if (is(U == Table)) {
			if (internalValue.type == ValueType.Table) return cast(Nullable!T)value.get!Table;
			else return Nullable!T();
		}
		else static if (is(U == Userdata)) {
			if (internalValue.type == ValueType.Userdata) return cast(Nullable!T)value.get!Userdata;
			else return Nullable!T();
		}
		else static if (is(U == DConsumable)) {
			return Nullable!T(this);
		}
		else static if (is(U == Value)) {
			return Nullable!T(internalValue);
		}
		else static if (is(U == DConsumableFunction)) {
			return Nullable!T(delegate(DConsumable[] args) {
				return internalValue.func.ccall(args.map!makeInternalValue).makeConsumable.array;
			});
		}
		else static assert(0, "Unable to convert to this type");
	}

	/** Cast operation */
	T opCast(T)() const {
		Nullable!T res = convert!T;
		if (res.isNull) {
			throw new LuaError(Value("bad argument #1 to '?' (" ~ getValueType!T.get.valueTypeToString ~ " expected, got "
				~ internalValue.type.valueTypeToString ~ ")"));
		}
		else {
			return res.get;
		}
	}

}

/** Convert the DConsumable type into an internal-representation Value */
pragma(inline) Value makeInternalValue(DConsumable value) {
	return value.internalValue;
}

/** Convert an internal-representation Value array into a DConsumable array */
pragma(inline) DConsumable[] makeConsumable(Value[] value) {
	DConsumable[] res;
	res.reserve(value.length);
	foreach (i; 0..value.length) {
		res ~= DConsumable(value[i]);
	}
	return res;
}

unittest {
	import zua;

	static assert(isConvertible!double);
	static assert(isConvertible!int);

	import std.stdio;

	Common c = new Common(GlobalOptions.FullAccess);

	c.env["callD1"] = delegate(int a, int b) {
		return (a + b) * 1000 + a * b;
	};

	c.env["callD2"] = delegate(string a, string b) {
		return a ~ b;
	};

	c.env.expose!"callD3"(delegate(string a, string b) {
		return a ~ b;
	});

	string cs;

	c.env.expose!"callD4"(delegate(string a, string b) {
		cs = a ~ b;
	});

	c.env.expose!"callD5"(delegate() {
		return cs;
	});

	try {
		c.run("file.lua", q"{
			assert(callD1("2", 3) == 5006)
			assert(callD2(2, 7) == "27")
			assert(select(2, pcall(callD2, 2, {})) == "bad argument #2 to '?' (string expected, got table)")
			assert(select(2, pcall(callD3, {}, 3)) == "bad argument #1 to 'callD3' (string expected, got table)")
			assert(callD5() == "")
			assert(not callD4("a", "b"))
			assert(callD5() == "ab")
		}");
	}
	catch (LuaError e) {
		stderr.writeln("Error: " ~ e.data.toString);
		assert(0);
	}
}