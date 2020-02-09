module zua.interop.classwrapper;
import zua.interop.functions;
import zua.interop.userdata;
import zua.interop.table;
import zua.interop;
import zua.vm.engine;
import std.typecons;
import std.traits;
import std.meta;

private DConsumable makeFunctionFromOverloads(bool isStatic, string member, T...)(T overloads) {
	pragma(inline) DConsumable[] func(DConsumable[] consumableArgs...) {
		// first we check for an exact match, then we try an approximate match
		static foreach (iterations; 0..2) {
			static foreach (i; 0..overloads.length) {{
				auto func = overloads[i];
				alias U = Unqual!(T[i]);
				try {
					// if this is the first time, exact match; else, non-exact match
					auto args = convertParameters!(U, member, iterations == 0)(consumableArgs);
					static if (is(ReturnType!U == void)) {
						func(args.expand);
						return [];
					}
					else {
						return func(args.expand).convertReturn!U;
					}
				}
				catch (ConversionException e) {
					// Do nothing
				}
				catch (Exception e) {
					if (cast(LuaError)e) {
						throw e;
					}
					else {
						throw new LuaError(Value(e.msg));
					}
				}
			}}
		}
		// if we didn't find a match, we throw an error:
		try {
			convertParameters!(Unqual!(typeof(overloads[0])), member)(consumableArgs);
		}
		catch (Exception e) {
			if (cast(LuaError)e) {
				throw e;
			}
			else {
				throw new LuaError(Value(e.msg));
			}
		}
		assert(0);
	}

	static if (isStatic) {
		return DConsumable(delegate DConsumable[](DConsumable[] args...) {
			return func(args);
		});
	}
	else {
		return DConsumable(delegate DConsumable[](Userdata _, DConsumable[] args...) {
			return func(args);
		});
	}
}

alias ClassConverter(T) = Userdata delegate(T instance);

private Tuple!(DConsumable, ClassConverter!Object)[TypeInfo] classWrapperMemo;

/** Create a class wrapper for use in Lua */
Tuple!(DConsumable, ClassConverter!T) makeClassWrapper(T)() if (is(T == class)) {
	TypeInfo info = typeid(T);
	if (info in classWrapperMemo) {
		auto res = classWrapperMemo[info];
		return tuple(res[0], cast(ClassConverter!T)res[1]);
	}
	else {
		auto res = makeClassWrapperUnmemoized!T;
		classWrapperMemo[info] = tuple(res[0], cast(ClassConverter!Object)res[1]);
		return res;
	}
}

private template AllFieldNamesTuple(alias T) {
	alias BaseTuple = TransitiveBaseTypeTuple!T;
	enum AllFieldNamesTuple = staticMap!(FieldNameTuple, AliasSeq!(T, BaseTuple));
}

private template AllFields(alias T) {
	alias BaseTuple = TransitiveBaseTypeTuple!T;
	alias AllFields = staticMap!(Fields, AliasSeq!(T, BaseTuple));
}

private Tuple!(DConsumable, ClassConverter!T) makeClassWrapperUnmemoized(T)() if (is(T == class)) {
	Userdata staticClass = Userdata.create(cast(void*)-1);

	Table staticMeta = Table.create();
	Table instanceMeta = Table.create();

	Userdata constructor() {
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

	DConsumable instanceIndex(Userdata lself, string key) {
		T self = cast(T)lself.data; // @suppress(dscanner.suspicious.unused_variable)

		static foreach (member; Members) {{
			static if (!hasStaticMember!(T, member)) {
				if (member == key) {
					enum size_t index = staticIndexOf!(member, AllFieldNamesTuple!T);
					static if (index != -1) {{
						alias FieldType = AllFields!T[index];
						static if (isConvertible!FieldType) {
							return DConsumable(__traits(getMember, self, member));
						}
					}}
					else {
						alias Overloads = __traits(getOverloads, self, member);
						alias GetPointer(alias U) = typeof(&U);
						alias GetDelegate(alias U) = ReturnType!U delegate(Parameters!U);
						alias GetDelegateFromPointer(alias U) = GetDelegate!(GetPointer!U);
						alias OverloadsArray = staticMap!(GetDelegateFromPointer, Overloads);
						Tuple!OverloadsArray overloads;
						static foreach (i; 0..OverloadsArray.length) {
							overloads[i] = &Overloads[i];
						}
						DConsumable func = makeFunctionFromOverloads!(false, member, OverloadsArray)(overloads.expand);
						static if (hasFunctionAttributes!(__traits(getMember, self, member), "@property")) {
							return (cast(DConsumableFunction)func)([DConsumable(lself)])[0];
						}
						else {
							return func;
						}
					}
				}
			}
		}}

		throw new Exception("attempt to index member '" ~ key ~ "'");
	}

	void instanceNewIndex(Userdata lself, string key, DConsumable value) {
		T self = cast(T)lself.data; // @suppress(dscanner.suspicious.unused_variable)

		static foreach (member; Members) {{
			static if (!hasStaticMember!(T, member)) {
				if (member == key) {
					enum size_t index = staticIndexOf!(member, AllFieldNamesTuple!T);
					static if (index != -1) {{
						alias FieldType = AllFields!T[index];
						static if (isConvertible!FieldType) {
							__traits(getMember, self, member) = value.opCast!(FieldType, 3);
							return;
						}
					}}
					else {
						static if (hasFunctionAttributes!(__traits(getMember, self, member), "@property")) {
							alias Overloads = __traits(getOverloads, self, member);
							alias GetPointer(alias U) = typeof(&U);
							alias GetDelegate(alias U) = ReturnType!U delegate(Parameters!U);
							alias GetDelegateFromPointer(alias U) = GetDelegate!(GetPointer!U);
							alias OverloadsArray = staticMap!(GetDelegateFromPointer, Overloads);
							Tuple!OverloadsArray overloads;
							static foreach (i; 0..OverloadsArray.length) {
								overloads[i] = &Overloads[i];
							}
							DConsumable func = makeFunctionFromOverloads!(false, member, OverloadsArray)(overloads.expand);
							(cast(DConsumableFunction)func)([DConsumable(lself), value]);
							return;
						}
						else {
							throw new Exception("attempt to modify member '" ~ key ~ "'");
						}
					}
				}
			}
		}}

		throw new Exception("attempt to modify member '" ~ key ~ "'");
	}

	instanceMeta["__index"] = &instanceIndex;
	instanceMeta["__newindex"] = &instanceNewIndex;
	instanceMeta["__tostring"] = delegate(Userdata lself) {
		T self = cast(T)lself.data;
		return self.toString;
	};
	instanceMeta["__metatable"] = "The metatable is locked";

	DConsumable staticIndex(Userdata, string key) {
		if (key == "new") {
			DConsumable res;
			res.__ctor!(typeof(&constructor), "new")(&constructor);
			return res;
		}

		static foreach (member; Members) {{
			static if (hasStaticMember!(T, member)) {
				if (member == key) {
					static if (!__traits(isStaticFunction, __traits(getMember, T, member))) {{
						alias FieldType = typeof(__traits(getMember, T, member));
						static if (isConvertible!FieldType) {
							return DConsumable(__traits(getMember, T, member));
						}
					}}
					else {
						alias Overloads = __traits(getOverloads, T, member);
						alias GetPointer(alias U) = typeof(&U);
						alias OverloadsArray = staticMap!(GetPointer, Overloads);
						Tuple!OverloadsArray overloads;
						static foreach (i; 0..OverloadsArray.length) {
							overloads[i] = &Overloads[i];
						}
						DConsumable func = makeFunctionFromOverloads!(true, member, OverloadsArray)(overloads.expand);
						static if (hasFunctionAttributes!(__traits(getMember, T, member), "@property")) {
							return (cast(DConsumableFunction)func)([])[0];
						}
						else {
							return func;
						}
					}
				}
			}
		}}

		throw new Exception("attempt to index member '" ~ key ~ "'");
	}

	void staticNewIndex(Userdata, string key, DConsumable value) {
		static foreach (member; Members) {{
			static if (hasStaticMember!(T, member)) {
				if (member == key) {
					static if (!__traits(isStaticFunction, __traits(getMember, T, member))) {{
						alias FieldType = typeof(__traits(getMember, T, member));
						static if (isConvertible!FieldType) {
							__traits(getMember, T, member) = value.opCast!(FieldType, 3);
							return;
						}
					}}
					else {
						static if (hasFunctionAttributes!(__traits(getMember, T, member), "@property")) {
							alias Overloads = __traits(getOverloads, T, member);
							alias GetPointer(alias U) = typeof(&U);
							alias OverloadsArray = staticMap!(GetPointer, Overloads);
							Tuple!OverloadsArray overloads;
							static foreach (i; 0..OverloadsArray.length) {
								overloads[i] = &Overloads[i];
							}
							DConsumable func = makeFunctionFromOverloads!(true, member, OverloadsArray)(overloads.expand);
							(cast(DConsumableFunction)func)([value]);
							return;
						}
						else {
							throw new Exception("attempt to modify member '" ~ key ~ "'");
						}
					}
				}
			}
		}}

		throw new Exception("attempt to modify member '" ~ key ~ "'");
	}

	staticMeta["__index"] = &staticIndex;
	staticMeta["__newindex"] = &staticNewIndex;
	staticMeta["__tostring"] = delegate() {
		return fullyQualifiedName!T;
	};
	staticMeta["__metatable"] = "The metatable is locked";

	staticClass.metatable = staticMeta;

	return tuple(DConsumable(staticClass), delegate Userdata(T instance) {
		return Userdata.create(cast(void*)instance, instanceMeta.Nullable!Table);
	});
}

version(unittest) {
	class C {

		static int y = 5;
		int x;

		int rand() {
			return 4; // chosen randomly by a dice roll
		}

		int rand2() const @property {
			return 4; // see above
		}

		void xMangler(int x) @property {
			this.x = x * 8;
		}

		static int rand3() @property {
			return 6; // we decided to add another dice roll into the mix
		}

		static void yMangler(int y) @property {
			C.y = y * 9;
		}

		int foo(int x) {
			return x * 3;
		}

		string foo(string x) {
			return x ~ " is fun";
		}

		int foo(int x, int y) {
			return x + y * 100;
		}

		static int goo() {
			return 7;
		}

		static int goo(int s) {
			return s * 2;
		}

		override string toString() const {
			return "C is a class";
		}

	}

	class D : C {

		override int rand() {
			return 5; // turns out the last one wasn't so random
		}

		int fooey() {
			return 71;
		}

		int go() {
			return x * 3;
		}

	}
}

unittest {
	import zua;
	import std.stdio;

	Common c = new Common(GlobalOptions.FullAccess);

	c.env.expose!("C", C);
	c.env.expose!("D", D);
	c.env["ins2"] = new C;

	try {
		c.run("file.lua", q"{
			assert(tostring(C) == "zua.interop.classwrapper.C")
			assert(ins2.rand2 == 4)
			local ins3 = D.new()
			assert(tostring(ins3) == "C is a class")
			assert(not pcall(function() return ins3.toString end))
			assert(ins3:fooey() == 71)
			assert(ins3:rand() == 5)
			assert(ins3.x == 0)
			ins3.x = 7
			assert(ins3:go() == 21)
			local ins = C.new()
			assert(tostring(ins) == "C is a class")
			assert(ins.x == 0)
			assert(ins:foo(2) == 6)
			assert(ins:foo(2.9) == 6)
			assert(ins:foo("programming") == "programming is fun")
			assert(ins:foo(7, "8") == 807)
			ins.x = 23
			assert(ins.x == 23)
			assert(select(2, pcall(ins.foo, ins)) == "bad argument #1 to 'foo' (number expected, got nil)")
			assert(C.y == 5)
			C.y = 18
			assert(C.y == 18)
			assert(C.goo() == 7)
			assert(C.goo(4) == 8)
			assert(not pcall(function() return C.foo end))
			assert(ins:rand() == 4)
			assert(ins.rand2 == 4)
			ins.xMangler = 16
			assert(ins.x == 128)
			assert(C.rand3 == 6)
			C.yMangler = 8
			assert(C.y == 72)
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