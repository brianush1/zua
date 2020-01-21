module zua.vm.engine;
import zua.vm.hashmap;
import zua.vm.std.coroutine;
import std.bitmanip;
import std.math;
import std.variant;
import std.conv;
import std.typecons;
import std.uuid;
import core.thread;

/** Represents a VM opcode */
enum Opcode {
	// 0 operands:
	Add,
	Sub,
	Mul,
	Div,
	Exp,
	Mod,
	Unm,
	Not,
	Len,
	Concat,

	Eq,
	Ne,
	Lt,
	Le,
	Gt,
	Ge,

	Ret,
	Getfenv,
	Call,
	NamecallPrep,
	Namecall,
	Drop,
	Dup,
	DupN,
	LdNil,
	LdFalse,
	LdTrue,
	LdArgs,

	NewTable,
	GetTable,
	SetTable,
	SetTableRev,
	SetArray,

	DropLoop,

	// 1 integer operand:
	LdStr,
	Jmp,
	JmpT,
	JmpF,
	JmpNil,
	Pack,
	Unpack,
	UnpackD,
	UnpackRev,
	Mkhv, /// make heap variable
	Get,
	Set,
	GetC,
	SetC,
	GetRef,
	SetRef,
	ForPrep,
	Loop,
	Introspect, // introspect 0 = dup
	DropTuple,

	// 1 double operand:
	LdNum,
	// AddK,
	// SubK,
	// MulK,
	// DivK,
	// ModK,
	// PowK,

	// misc:
	LdFun,
}

/** A Lua exception */
class LuaError : Exception {
	/** The data packaged with this exception */
	Value data;

	/** The call stack, as it was when this error occurred */
	Traceframe[] stack;

	/** The call stack, as it $(I actually) was when this error occurred */
	package Stackframe[] fullstack;

	/** Construct a new Lua exception */
	this(Value data) @safe nothrow {
		super("A Lua-side exception has occurred");
		this.data = data;

		Stackframe runningFrame;
		runningFrame.ip = running.engine.ip;
		runningFrame.id = running.engine.id;
		runningFrame.func = running;

		fullstack = callstack.dup ~ runningFrame;

		foreach (f; callstack) {
			Traceframe frame;
			frame.ip = f.ip;
			frame.id = f.id;
			stack ~= frame;
		}

		Traceframe frame;
		frame.ip = running.engine.ip;
		frame.id = running.engine.id;
		stack ~= frame;
	}
}

/** Represents a single frame in a stack trace */
struct Traceframe {
	/** The current instruction pointer of the function */
	size_t ip;

	/** The ID of the engine running this stack frame */
	UUID id;
}

/** Represents a single stack frame */
struct Stackframe {
	/** The function that is in charge of this stack frame */
	FunctionValue func;

	/** The current instruction pointer of the function */
	size_t ip;

	/** The ID of the engine running this stack frame */
	UUID id;
}

package Stackframe[] callstack;
package FunctionValue running;

package pragma(inline) void pushCallstack() {
	Stackframe frame = {
		func: running,
		ip: running.engine.ip,
		id: running.engine.id
	};
	callstack.assumeSafeAppend ~= frame;
}

package pragma(inline) void popCallstack() {
	callstack = callstack[0 .. $ - 1];
}

/** Table contents of a Value */
final class TableValue {
	package Value[] array;
	package ulong maxArrayIndex = ~0UL;
	package HashTable hash;

	/** Create a new TableValue */
	this() {
		hash = new HashTable;
	}

	/** Get a raw value */
	pragma(inline) Value* rawget(Value key) {
		if (key.type == ValueType.Number && key.num > 0) {
			ulong index = cast(ulong) key.num;
			if (cast(double) index == key.num) {
				index--;
				if (index >= array.length) {
					return hash.lookup(key);
				}
				else {
					return &array[index];
				}
			}
		}

		return hash.lookup(key);
	}

	/** Set a raw value */
	pragma(inline) void rawset(Value key, Value val) {
		if (key.type == ValueType.Number && key.num > 0) {
			ulong index = cast(ulong) key.num;
			if (cast(double) index == key.num) {
				index--;
				if (index < array.capacity + 64 && index < maxArrayIndex) {
					if (index >= array.length)
						array.length = index + 1;
					array[index] = val;
					return;
				}
				else if (index < maxArrayIndex) {
					maxArrayIndex = index;
				}
			}
		}

		hash.insert(key, val);
	}

	/** The metatable attached to this table */
	TableValue metatable;

	/** Get the length of this value */
	pragma(inline) Value length() {
		ulong low = 1;
		ulong high = 1;
		while (rawhas(Value(high))) {
			high *= 2;
		}

		if (!rawhas(Value(1))) {
			return Value(0);
		}

		while (true) {
			ulong mid = (low + high) / 2;
			const bool midThere = rawhas(Value(mid));
			const bool boundary = midThere && !rawhas(Value(mid + 1));
			if (boundary) {
				return mid.to!Value;
			}
			else if (midThere) {
				low = mid;
			}
			else {
				high = mid;
			}
		}
	}

	/** Check if the table has a key */
	pragma(inline) bool rawhas(Value key) {
		Value* ptr = rawget(key);
		return ptr && !ptr.isNil;
	}

	/** Get a key */
	pragma(inline) Value get(Value key) {
		Value* ptr = rawget(key);
		if (ptr && !ptr.isNil) {
			return *ptr;
		}
		else if (metatable !is null) {
			Value index = metatable.get(Value("__index"));
			if (index.type == ValueType.Function) {
				return Value.from(index.call([Value(this), key]));
			}
			else if (index.type != ValueType.Nil) {
				return index.get(key);
			}
		}

		if (key.type == ValueType.Nil) throw new LuaError(Value("table index is nil"));
		return Value();
	}

	/** Set a key */
	pragma(inline) void set(Value key, Value value) {
		if (key.type == ValueType.Nil) throw new LuaError(Value("table index is nil"));

		if (metatable !is null) {
			Value* ptr = rawget(key);
			if (ptr && !ptr.isNil) {
				*ptr = value;
				return;
			}
			else {
				Value index = metatable.get(Value("__newindex"));
				if (index.type != ValueType.Nil) {
					index.call([Value(this), key, value]);
					return;
				}
			}
		}

		rawset(key, value);
	}

	/** Call this value */
	pragma(inline) Value[] call(Value[] args) {
		if (metatable !is null) {
			auto callHandler = metatable.get(Value("__call"));
			if (!callHandler.isNil) {
				return callHandler.call(Value(this) ~ args);
			}
		}

		throw new LuaError(Value("attempt to call a table value"));
	}
}

/** Function contents of a Value */
final class FunctionValue {
	/** Denotes the implementation-defined position at which this function is found in the code */
	size_t ip;

	/** The engine to use when calling this function */
	Engine engine;

	/** A list of upvalues that partain to this function */
	Value*[] upvalues;

	/** The environment of this function */
	TableValue env;

	/**
	
	Call this function value with the given parameters, running it in a toplevel thread.
	
	Uses the function's environment for the new thread's environment.
	
	*/
	Value[] ccall(Value[] args) {
		return runToplevel(env, this, args);
	}

	/** Call this function value with the given parameters in the current context. */
	package pragma(inline) Value[] rawcall(Value[] args) {
		FunctionValue save = running;
		const bool toplevel = running is null;
		if (!toplevel) pushCallstack();
		scope(exit) {
			running = save;
			if (!toplevel) popCallstack();
		}
		running = this;
		return engine.callf(this, args);
	}
}

/** An enum representing the status of a given coroutine */
enum CoroutineStatus {
	Running,
	Suspended,
	Normal,
	Dead
}

/** Thread contents of a Value */
final class ThreadValue {
	/** The D fiber that corresponds to this Lua thread */
	Fiber fiber;

	/** The environment of this thread */
	TableValue env;

	/** The status of this thread */
	CoroutineStatus status;
}

/** A enum containing the various types of Lua values */
enum ValueType {
	Nil,
	Boolean,

	Number,
	String,

	Table,
	Function,
	Thread,
	// Userdata,
	Heap,

	Tuple,
}

private TableValue stringMetatable;

/** Represents a Lua value */
struct Value {
	/** The type of this Value */
	ValueType type = ValueType.Nil;
	union {
		bool boolean; /// The boolean component of this Value
		double num; /// The number component of this Value
		string str; /// The string component of this Value
		TableValue table; /// The table component of this Value
		FunctionValue func; /// The function component of this Value
		ThreadValue thread; /// The thread component of this Value
		// UserdataValue userdata; /// The userdata component of this Value

		Value* heap; /// The reference component of this Value
		Value[] tuple; /// The tuple component of this Value
	}

	bool opEquals(const Value other) const {
		if (type != other.type) return false;
		switch (type) {
		case ValueType.Nil:
			return true;
		case ValueType.Boolean:
			return boolean == other.boolean;
		case ValueType.Number:
			return num == other.num;
		case ValueType.String:
			return str == other.str;
		case ValueType.Table:
			return table is other.table;
		case ValueType.Function:
			return func is other.func;
		case ValueType.Thread:
			return thread is other.thread;
		default: assert(0);
		}
	}

	size_t toHash() const nothrow @safe {
		return () @trusted {
			switch (type) {
			case ValueType.Nil:
				return null.hashOf;
			case ValueType.Boolean:
				return boolean.hashOf;
			case ValueType.Number:
				return num.hashOf;
			case ValueType.String:
				return str.hashOf;
			case ValueType.Table:
				return table.hashOf;
			case ValueType.Function:
				return func.hashOf;
			case ValueType.Thread:
				return thread.hashOf;
			default: assert(0);
			}
		}();
	}

	string toString() {
		switch (type) {
		case ValueType.Nil:
			return "nil";
		case ValueType.Boolean:
			return boolean ? "true" : "false";
		case ValueType.Number:
			return num.to!string;
		case ValueType.String:
			return str;
		case ValueType.Table:
			return "table: 0x" ~ table.toHash.toChars!16.to!string;
		case ValueType.Function:
			return "function: 0x" ~ func.toHash.toChars!16.to!string;
		case ValueType.Thread:
			return "thread: 0x" ~ thread.toHash.toChars!16.to!string;
		case ValueType.Tuple:
			return tuple.to!string;
		case ValueType.Heap:
			return "^" ~ heap.toString;
		default:
			return "??";
		}
	}

	/** Convert to a Lua "string" */
	Value luaToString() {
		Nullable!(Value[]) res = metacall("__tostring", [this]);
		if (!res.isNull) {
			if (res.get.length == 0) {
				return Value();
			}
			else {
				return res.get[0];
			}
		}
		return Value(toString);
	}

	/** Check if this Value is nil */
	pragma(inline) bool isNil() {
		return type == ValueType.Nil;
	}

	/** Construct a new Value */
	this(long v) {
		type = ValueType.Number;
		num = cast(double) v;
	}

	/** Construct a new Value */
	this(int v) {
		type = ValueType.Number;
		num = cast(double) v;
	}

	/** Construct a new Value */
	this(bool v) {
		type = ValueType.Boolean;
		boolean = v;
	}

	/** Construct a new Value */
	this(double v) {
		type = ValueType.Number;
		num = v;
	}

	/** Construct a new Value */
	this(string v) {
		type = ValueType.String;
		str = v;
	}

	/** Construct a new Value */
	this(TableValue v) {
		type = ValueType.Table;
		table = v;
	}

	/** Construct a new Value */
	this(FunctionValue v) {
		type = ValueType.Function;
		func = v;
	}

	/** Construct a new Value */
	this(ThreadValue v) {
		type = ValueType.Thread;
		thread = v;
	}

	/** Construct a new heap Value */
	this(Value* v) {
		type = ValueType.Heap;
		heap = v;
	}

	/** Construct a new Value */
	this(Value[] v) {
		type = ValueType.Tuple;
		if (v.length == 0)
			return;
		foreach (val; v[0 .. $ - 1]) {
			if (val.type == ValueType.Tuple) {
				if (val.tuple.length == 0) {
					tuple.assumeSafeAppend ~= Value();
				}
				else {
					tuple.assumeSafeAppend ~= val.tuple[0];
				}
			}
			else {
				tuple.assumeSafeAppend ~= val;
			}
		}
		if (v[$ - 1].type == ValueType.Tuple) {
			tuple.assumeSafeAppend ~= v[$ - 1].tuple;
		}
		else {
			tuple.assumeSafeAppend ~= v[$ - 1];
		}
	}

	/** Convert a tuple to a single value */
	static Value from(Value[] arr) {
		if (arr.length == 0) {
			return Value();
		}
		else {
			return arr[0];
		}
	}

	/** Get the metatable of this value, or null if N/A */
	pragma(inline) TableValue metatable() {
		if (type == ValueType.Table) return table.metatable;
		if (type == ValueType.String) {
			if (!stringMetatable) {
				import zua.vm.std.string : stringlib;

				stringMetatable = new TableValue;
				stringMetatable.set(Value("__index"), stringlib);
				stringMetatable.set(Value("__metatable"), Value("The metatable is locked"));
			}

			return stringMetatable;
		}

		return null;
	}

	/** Call a metamethod on this value */
	pragma(inline) Nullable!(Value[]) metacall(string method, Value[] args) {
		TableValue meta = metatable;
		if (meta is null)
			return Nullable!(Value[]).init;
		Value metamethod = meta.get(Value(method));
		if (!metamethod.isNil) {
			return metamethod.call(args).nullable;
		}
		else {
			return Nullable!(Value[]).init;
		}
	}

	/** Convert this value to a bool */
	pragma(inline) bool toBool() const {
		if (type == ValueType.Boolean && boolean == false)
			return false;

		if (type == ValueType.Nil)
			return false;

		return true;
	}

	/** Get the length of this value */
	pragma(inline) Value length() {
		if (type == ValueType.Table) return table.length;
		if (type == ValueType.String) return Value(str.length);

		throw new LuaError(Value("attempt to get length of a " ~ typeStr ~ " value"));
	}

	/** Get a key */
	pragma(inline) Value get(Value key) {
		if (type == ValueType.Table) return table.get(key);

		TableValue meta = metatable;

		if (meta is null)
			throw new LuaError(Value("attempt to index a " ~ typeStr ~ " value"));

		Value index = meta.get(Value("__index"));
		if (index.type == ValueType.Function) {
			return Value.from(index.call([this, key]));
		}
		else if (index.type != ValueType.Nil) {
			return index.get(key);
		}

		throw new LuaError(Value("attempt to index a " ~ typeStr ~ " value"));
	}

	/** Set a key */
	pragma(inline) void set(Value key, Value value) {
		if (type == ValueType.Table) return table.set(key, value);

		throw new LuaError(Value("attempt to index a " ~ typeStr ~ " value"));
	}

	/** Call this value */
	pragma(inline) Value[] call(Value[] args) {
		if (type == ValueType.Table) return table.call(args);
		if (type == ValueType.Function) return func.rawcall(args);

		throw new LuaError(Value("attempt to call a " ~ typeStr ~ " value"));
	}

	/** Return a string describing both these objects' types */
	pragma(inline) string typeStr(Value o) {
		if (type == o.type) {
			return "two " ~ typeStr ~ " values";
		}
		else {
			return typeStr ~ " with " ~ o.typeStr;
		}
	}

	/** Return a string describing this object's type */
	pragma(inline) string typeStr() {
		switch (type) {
		case ValueType.Nil:
			return "nil";
		case ValueType.Boolean:
			return "boolean";

		case ValueType.Number:
			return "number";
		case ValueType.String:
			return "string";

		case ValueType.Table:
			return "table";
		case ValueType.Function:
			return "function";
		case ValueType.Thread:
			return "thread";
		// case ValueType.Userdata:
		// 	return "userdata";

		default:
			assert(0, "got " ~ type.to!string);
		}
	}

	/** Check if this is less than that */
	pragma(inline) bool lessThan(Value b) {
		alias a = this;
		if (a.type == ValueType.String && b.type == a.type) {
			return a.str < b.str;
		}
		else if (a.type == ValueType.Number && b.type == a.type) {
			return a.num < b.num;
		}

		TableValue meta = a.metatable;
		if (meta is null)
			throw new LuaError(Value("attempt to compare " ~ a.typeStr(b)));
		TableValue metaOther = b.metatable;
		if (metaOther is null)
			throw new LuaError(Value("attempt to compare " ~ a.typeStr(b)));
		Value method = meta.get(Value("__lt"));
		if (method.isNil)
			throw new LuaError(Value("attempt to compare " ~ a.typeStr(b)));
		const Value methodOther = metaOther.get(Value("__lt"));
		if (method == methodOther) {
			auto res = method.call([a, b]);
			if (res.length == 0) {
				return false;
			}
			else {
				return res[0].toBool;
			}
		}
		else {
			throw new LuaError(Value("attempt to compare " ~ a.typeStr(b)));
		}
	}

	/** Check if this is less than or equal to that */
	pragma(inline) bool lessOrEqual(Value b) {
		alias a = this;
		if (a.type == ValueType.String && b.type == a.type) {
			return a.str <= b.str;
		}
		else if (a.type == ValueType.Number && b.type == a.type) {
			return a.num <= b.num;
		}

		TableValue meta = a.metatable;
		if (meta is null)
			throw new LuaError(Value("attempt to compare " ~ a.typeStr(b)));
		TableValue metaOther = b.metatable;
		if (metaOther is null)
			throw new LuaError(Value("attempt to compare " ~ a.typeStr(b)));
		Value method = meta.get(Value("__le"));
		if (method.isNil)
			throw new LuaError(Value("attempt to compare " ~ a.typeStr(b)));
		const Value methodOther = metaOther.get(Value("__le"));
		if (method == methodOther) {
			auto res = method.call([a, b]);
			if (res.length == 0) {
				return false;
			}
			else {
				return res[0].toBool;
			}
		}
		else {
			throw new LuaError(Value("attempt to compare " ~ a.typeStr(b)));
		}
	}

	/** Check if this equals that, invoking any necessary metamethods */
	pragma(inline) bool equals(Value b) {
		alias a = this;
		if (a == b)
			return true;

		TableValue meta = a.metatable;
		if (meta is null)
			return false;
		TableValue metaOther = b.metatable;
		if (metaOther is null)
			return false;
		Value method = meta.get(Value("__eq"));
		if (method.isNil)
			return false;
		const Value methodOther = metaOther.get(Value("__eq"));
		if (method == methodOther) {
			auto res = method.call([a, b]);
			if (res.length == 0) {
				return false;
			}
			else {
				return res[0].toBool;
			}
		}
		else {
			return false;
		}
	}
}

/** Denotes a virtualization engine */
class Engine {
	/** The current instruction pointer of this engine */
	size_t[Fiber] ipTable; // TODO: weak Fiber keys
	// size_t ipTable;

	/** Get the current IP */
	pragma(inline) size_t ip() @safe nothrow {
		size_t* res = Fiber.getThis in ipTable;
		if (res) {
			return *res;
		}
		else {
			return 0;
		}
		// return ipTable;
	}

	/** Set the current IP */
	pragma(inline) void ip(size_t value) @safe nothrow {
		ipTable[Fiber.getThis] = value;
		// ipTable = value;
	}

	/** A unique identifier for this engine */
	UUID id;

	/** Call a function value within this virtualization engine */
	abstract Value[] callf(FunctionValue func, Value[] args);
}