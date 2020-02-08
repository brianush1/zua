module zua.interop.classwrapper;
import zua.interop.userdata;
import zua.interop.table;
import zua.interop;
import std.typecons;
import std.traits;
import std.meta;

/** Create a class wrapper for use in Lua */
DConsumable makeClassWrapper(T)() if (is(T == class)) {
	Userdata staticClass = Userdata.create(cast(void*)-1);

	Table staticMeta = Table.create();
	Table instanceMeta = Table.create();

	Userdata constructor(DConsumable[] args...) {
		T res = new T;
		return Userdata.create(cast(void*)res, instanceMeta.Nullable!Table);
	}

	enum bool NotSpecial(string T) =
		T != "toString" && T != "toHash" && T != "Monitor" && T != "factory"
		&& T != "opUnary" && T != "opIndexUnary" && T != "opSlice" && T != "opCast"
		&& T != "opBinary" && T != "opBinaryRight" && T != "opEquals" && T != "opCmp"
		&& T != "opCall" && T != "opAssign" && T != "opIndexAssign" && T != "opOpAssign"
		&& T != "opIndexOpAssign" && T != "opIndex" && T != "opDollar" && T != "opDispatch";
	alias Members = Filter!(NotSpecial, __traits(allMembers, T));

	DConsumable instanceIndex(Userdata, string key) {
		// TODO: this

		throw new Exception("attempt to index member '" ~ key ~ "'");
	}

	instanceMeta["__index"] = &instanceIndex;
	instanceMeta["__metatable"] = "The metatable is locked";

	DConsumable staticIndex(Userdata, string key) {
		if (key == "new") {
			DConsumable res;
			res.__ctor!(typeof(&constructor), "new")(&constructor);
			return res;
		}

		throw new Exception("attempt to index member '" ~ key ~ "'");
	}

	void staticNewIndex(Userdata, string key, string value) {
		throw new Exception("attempt to modify member '" ~ key ~ "'");
	}

	staticMeta["__index"] = &staticIndex;
	staticMeta["__newindex"] = &staticNewIndex;
	staticMeta["__metatable"] = "The metatable is locked";

	staticClass.metatable = staticMeta;

	return DConsumable(staticClass);
}

version(unittest) {
	class C {

		int x;

		int foo() {
			return 3;
		}

		static int goo() {
			return 7;
		}

		static int goo(int s) {
			return s * 2;
		}

	}
}

unittest {
	import zua;
	import std.stdio;

	Common c = new Common(GlobalOptions.FullAccess);

	c.env["C"] = makeClassWrapper!C;

	try {
		c.run("file.lua", q"{
			print(C)
			local ins = C.new(2, "asd")
			--[[ins.x = 23
			assert(ins.foo() == 3)
			assert(C.goo() == 7)
			assert(C.goo(4) == 8)
			assert(not ins.foo and not C.foo)]]
		}");
	}
	catch (LuaError e) {
		stderr.writeln("Error: " ~ e.data.toString);
		assert(0);
	}
}

private:

/** Checks if the given arguments match the overload; if exact, type coercion is not performed */
bool matchesOverload(alias Method, bool exact)(DConsumable[] args) {
	static if (variadicFunctionStyle!Method == Variadic.no) {
		alias params = Parameters!Method;
		static foreach (i; 0..params.length) {
			static assert(isConvertible!(params[i]));
		}

		static foreach (i; 0..params.length) {{
			alias K = params[i];
			Nullable!K res = args[i].convert!(K, exact);
			if (res.isNull) return false;
		}}

		return true;
	}
	else static assert(0, "This type of variadic function is not supported");
}

DConsumable wrapMethod(alias Overloads)() {
	DConsumable[] doverloads;
	static foreach (T; Overloads) {
		doverloads ~= DConsumable(&T);
	}
	return DConsumable(delegate(DConsumable[] args...) {
		DConsumable func;
		(){
			static foreach (i; 0..Overloads.length) {{
				alias T = Overloads[i];
				if (matchesOverload!(T, true)(args)) {
					func = doverloads[i];
					return;
				}
			}}
			static foreach (i; 0..Overloads.length) {{
				alias T = Overloads[i];
				if (matchesOverload!(T, false)(args)) {
					func = doverloads[i];
					return;
				}
			}}
			func = doverloads[0];
		}();
		return func.convert!DConsumableFunction()(args);
	});
}