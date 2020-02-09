module zua.interop.functions;
import zua.interop;
import zua.vm.engine;
import std.typecons;
import std.traits;
import std.conv;

/** Thrown when a value cannot be converted from the Lua to D side */
final class ConversionException : Exception {

	/** Create a new ConversionException*/
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextChain = null) @nogc @safe pure nothrow {
		super(msg, file, line, nextChain);
	}

}

/**

Convert function parameters from a DConsumable[] to D-side arguments

Parameters:
preferredName = The name to use in ConversionExceptions
exact = When true, 

*/
auto convertParameters(QualifiedFunc, string preferredName = "?", bool exact = false)(DConsumable[] args) {
	alias Func = Unqual!QualifiedFunc;
	static assert(isSomeFunction!Func, "expected function, got " ~ Func.stringof);

	static if (variadicFunctionStyle!Func == Variadic.no) {
		alias Params = Parameters!Func;

		static foreach (i; 0..Params.length) {
			static assert(isConvertible!(Params[i]), "parameter #" ~ to!string(i + 1) ~ " (" ~ Params[i].stringof
				~ ") is not convertible from a Lua value");
		}

		static if (exact) {
			if (Params.length > args.length) {
				throw new ConversionException("not enough parameters");
			}
			else if (Params.length < args.length) {
				throw new ConversionException("too many parameters");
			}
		}

		Tuple!Params dsideArgs = void;
		static foreach (i; 0..Params.length) {{
			alias ParamType = Params[i];
			auto dv = i >= args.length ? DConsumable(null) : args[i];
			Nullable!ParamType res = dv.convert!ParamType;
			if (res.isNull) {
				// getValueType!ParamType isn't gonna be null, because convert will never fail with a dynamic type
				throw new ConversionException("bad argument #" ~ to!string(i + 1)
					~ " to '" ~ preferredName ~ "' (" ~ getValueType!ParamType.get.valueTypeToString
					~ " expected, got " ~ dv.makeInternalValue.type.valueTypeToString ~ ")");
			}
			else {
				dsideArgs[i] = res.get;
			}
		}}

		return dsideArgs;
	}
	else static if (variadicFunctionStyle!Func == Variadic.typesafe) {
		alias Params = Parameters!Func[0..$ - 1];

		static foreach (i; 0..Params.length) {
			static assert(isConvertible!(Params[i]), "parameter #" ~ to!string(i + 1) ~ " is not convertible from a Lua value");
		}

		alias VarargArray = Parameters!Func[$ - 1];
		static if (!is(VarargArray == VarargElement[], VarargElement)) {
			static assert(0, "vararg parameter should be an array");
			// this should never realistically run ^
		}
		static assert(isConvertible!VarargElement, "vararg parameter is not convertible from a Lua value");

		static if (exact) {
			if (Params.length > args.length) {
				throw new ConversionException("not enough parameters");
			}
		}

		Tuple!(Parameters!Func) dsideArgs = void;
		static foreach (i; 0..Params.length) {{
			alias ParamType = Params[i];
			auto dv = i >= args.length ? DConsumable(null) : args[i];
			Nullable!ParamType res = dv.convert!ParamType;
			if (res.isNull) {
				// getValueType!ParamType isn't gonna be null, because convert will never fail with a dynamic type
				throw new ConversionException("bad argument #" ~ to!string(i + 1)
					~ " to '" ~ preferredName ~ "' (" ~ getValueType!ParamType.get.valueTypeToString
					~ " expected, got " ~ dv.makeInternalValue.type.valueTypeToString ~ ")");
			}
			else {
				dsideArgs[i] = res.get;
			}
		}}

		VarargArray vararg;
		foreach (i; Params.length..args.length) {
			auto dv = args[i];
			Nullable!VarargElement res = dv.convert!VarargElement;
			if (res.isNull) {
				// getValueType!VarargElement isn't gonna be null, because convert will never fail with a dynamic type
				throw new ConversionException("bad argument #" ~ to!string(i + 1)
					~ " to '" ~ preferredName ~ "' (" ~ getValueType!VarargElement.get.valueTypeToString
					~ " expected, got " ~ dv.makeInternalValue.type.valueTypeToString ~ ")");
			}
			else {
				vararg ~= res.get;
			}
		}

		dsideArgs[$ - 1] = vararg;
		return dsideArgs;
	}
	else {
		static assert(0, "this type of variadic function is not supported; use typesafe variadics");
	}
}

/** Convert the D-side return value of a native function to a DConsumable[] */
DConsumable[] convertReturn(QualifiedFunc)(ReturnType!(Unqual!QualifiedFunc) value) {
	alias Func = Unqual!QualifiedFunc;
	static assert(isSomeFunction!Func, "expected function");

	alias Return = ReturnType!Func;

	static assert(!is(Return == void), "return type should not be void");

	static if (!isConvertible!Return && is(Return == ReturnElement[], ReturnElement)) {
		static assert(isConvertible!ReturnElement, "return type is not convertible to a Lua value");

		DConsumable[] res;
		res.reserve(value.length);

		foreach (element; value) {
			res ~= DConsumable(element);
		}

		return res;
	}
	else {
		static assert(isConvertible!Return, "return type is not convertible to a Lua value");

		return [DConsumable(value)];
	}
}