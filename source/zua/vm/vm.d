module zua.vm.vm;
import zua.vm.engine;
import zua.compiler.utils;
import std.bitmanip;
import std.math;
import std.variant;
import std.conv;
import std.typecons;
import std.uuid;
import std.algorithm.mutation;

version(LDC) {
	private pragma(LDC_alloca) void* alloca(size_t);
}
else {
	import core.stdc.stdlib : alloca;
}

/** A Lua VM engine */
class VmEngine : Engine {

	/** The bytecode buffer for this engine */
	immutable(ubyte)[] buffer;

	/** Create a new VM engine */
	this(immutable(ubyte)[] buffer, UUID id) {
		this.buffer = buffer;
		this.id = id;
	}

	/** Read a single numeric value */
	pragma(inline) private T read(T)(size_t index) {
		ubyte[T.sizeof] data = buffer[index .. index + T.sizeof];
		return littleEndianToNative!(T, T.sizeof)(data);
	}

	/** Read a string */
	pragma(inline) private string readStr(size_t index) {
		const length = cast(size_t) read!ulong(index);
		string result = cast(string) buffer[index + 8 .. index + 8 + length];
		return result;
	}

	/** Read a single numeric value */
	pragma(inline) private T read(T)() {
		ubyte[T.sizeof] data = buffer[ip .. ip + T.sizeof];
		ip = ip + T.sizeof;
		return littleEndianToNative!(T, T.sizeof)(data);
	}

	/** Read a string */
	pragma(inline) private string readStr() {
		const length = cast(size_t) read!ulong();
		string result = cast(string) buffer[ip .. ip + length];
		ip = ip + length;
		return result;
	}

	override Value[] callf(FunctionValue func, Value[] args) {
		const size_t returnIp = ip;
		scope(exit) {
			ip = returnIp;
		}

		running = func;

		size_t numLocals = read!ulong(func.ip + 16);
		Value* locals = cast(Value*) alloca(Value.sizeof * numLocals);
		const size_t immediateStackSize = 16;
		Value[immediateStackSize] stack;
		size_t sp = -1;

		foreach (i; 0 .. numLocals) {
			emplace(&locals[i]);
		}

		ip = func.ip + 40;

		pragma(inline) void push(Value value) {
			sp++;
			stack[sp] = value;
		}

		/** Pop a value, as-is, off the stack */
		pragma(inline) Value pop() {
			Value res = stack[sp];
			stack[sp].heap = null;
			sp--;
			return res;
		}

		/** Pop a value */
		pragma(inline) Value popv() {
			return pop();
		}

		/** Pop a value as a tuple */
		pragma(inline) Value[] popt() {
			Value res = pop();
			if (res.type == ValueType.Tuple) {
				return res.tuple;
			}
			else {
				return [res];
			}
		}

		pragma(inline) Nullable!double coercev(Value v) {
			if (v.type == ValueType.Number) {
				return v.num.nullable;
			}
			else if (v.type == ValueType.String) {
				try {
					return v.str.to!double.nullable;
				}
				catch (ConvException) {
					return Nullable!double();
				}
			}
			else {
				return Nullable!double();
			}
		}

		pragma(inline) Nullable!string coerceToStr(Value v) {
			if (v.type == ValueType.Number) {
				return v.num.to!string.nullable;
			}
			else if (v.type == ValueType.String) {
				return v.str.nullable;
			}
			else {
				return Nullable!string();
			}
		}

		pragma(inline) bool isCoerceable(Value v) {
			if (v.type == ValueType.Number)
				return true;

			if (v.type == ValueType.String) {
				try {
					v.str.to!double;
					return true;
				}
				catch (ConvException) {
					return false;
				}
			}

			return false;
		}

		pragma(inline) void binaryOp(string ifNative, string meta,
				string varA = "a", string varB = "b")() {
			Value bVal = popv();
			Value aVal = popv();
			const Nullable!double aNum = coercev(aVal);
			const Nullable!double bNum = coercev(bVal);
			if (!aNum.isNull && !bNum.isNull) {
				mixin("const double ", varA, " = aNum.get;");
				mixin("const double ", varB, " = bNum.get;");
				push(Value(mixin(ifNative)));
				return;
			}

			Nullable!(Value[]) attempt = aVal.metacall(meta, [aVal, bVal]);
			if (attempt.isNull) {
				attempt = bVal.metacall(meta, [aVal, bVal]);
			}
			if (attempt.isNull) {
				string type = aVal.typeStr;
				if (isCoerceable(aVal)) {
					type = bVal.typeStr;
				}
				throw new LuaError(Value("attempt to perform arithmetic on a " ~ type ~ " value"));
			}
			Value[] res = attempt.get;
			if (res.length == 0) {
				push(Value());
			}
			else {
				push(res[0]);
			}
		}

		pragma(inline) void binaryOpStr(string ifNative, string meta,
				string varA = "a", string varB = "b")() {
			Value bVal = popv();
			Value aVal = popv();
			const Nullable!string aStr = coerceToStr(aVal);
			const Nullable!string bStr = coerceToStr(bVal);
			if (!aStr.isNull && !bStr.isNull) {
				mixin("const string ", varA, " = aStr.get;");
				mixin("const string ", varB, " = bStr.get;");
				push(Value(mixin(ifNative)));
				return;
			}

			Nullable!(Value[]) attempt = aVal.metacall(meta, [aVal, bVal]);
			if (attempt.isNull) {
				attempt = bVal.metacall(meta, [aVal, bVal]);
			}
			if (attempt.isNull) {
				string type = aVal.typeStr;
				if (aVal.type == ValueType.String || aVal.type == ValueType.Number) {
					type = bVal.typeStr;
				}
				throw new LuaError(Value("attempt to concatenate a " ~ type ~ " value"));
			}
			Value[] res = attempt.get;
			if (res.length == 0) {
				push(Value());
			}
			else {
				push(res[0]);
			}
		}

		pragma(inline) void unm(Value v) {
			const Nullable!double vals = coercev(v);
			if (!vals.isNull) {
				push(Value(-vals.get));
			}
			else {
				const Nullable!(Value[]) attempt = v.metacall("__unm", [v]);
				if (attempt.isNull) {
					string type = v.typeStr;
					throw new LuaError(Value("attempt to perform arithmetic on a " ~ type ~ " value"));
				}
				Value[] res = cast(Value[]) attempt.get;
				if (res.length == 0) {
					push(Value());
				}
				else {
					push(res[0]);
				}
			}
		}

		pragma(inline) string getString(size_t index) {
			ulong localIP = func.ip;
			const ulong dataLength = read!ulong(localIP);
			const ulong codeLength = read!ulong(localIP + 32);
			localIP += 40 + codeLength;
			const ulong datasegPtr = localIP + (dataLength + 1) * 8;
			string val = readStr(datasegPtr + read!ulong(localIP + 8 * index));
			return val;
		}

		struct ForState {
			double at;
			double high;
			double step;
			size_t var;
		}

		ForState[] forStack;

		while (true) {
			const op = cast(Opcode) read!OpcodeSize;
			switch (op) {
			case Opcode.Add:
				binaryOp!("a + b", "__add");
				break;
			case Opcode.Sub:
				binaryOp!("a - b", "__sub");
				break;
			case Opcode.Mul:
				binaryOp!("a * b", "__mul");
				break;
			case Opcode.Div:
				binaryOp!("a / b", "__div");
				break;
			case Opcode.Exp:
				binaryOp!("pow(a, b)", "__pow");
				break;
			case Opcode.Mod:
				binaryOp!("(a < 0 ? (a % b + b) % b : (a % b)) + (b < 0 && a > 0 ? b : 0)", "__mod");
				break;
			case Opcode.Unm:
				Value v = popv();
				unm(v);
				break;
			case Opcode.Not:
				Value v = popv();
				push(Value(!v.toBool));
				break;
			case Opcode.Len:
				Value v = popv();
				push(v.length);
				break;
			case Opcode.Concat:
				binaryOpStr!("a ~ b", "__concat");
				break;
			case Opcode.Eq:
				Value b = popv();
				Value a = popv();
				push(Value(a.equals(b)));
				break;
			case Opcode.Ne:
				Value b = popv();
				Value a = popv();
				push(Value(!a.equals(b)));
				break;
			case Opcode.Lt:
				Value b = popv();
				Value a = popv();
				push(Value(a.lessThan(b)));
				break;
			case Opcode.Le:
				Value b = popv();
				Value a = popv();
				push(Value(a.lessOrEqual(b)));
				break;
			case Opcode.Gt:
				Value b = popv();
				Value a = popv();
				push(Value(b.lessThan(a)));
				break;
			case Opcode.Ge:
				Value b = popv();
				Value a = popv();
				push(Value(b.lessOrEqual(a)));
				break;
			case Opcode.Ret:
				return popt();
			case Opcode.Getfenv:
				push(Value(func.env));
				break;
			case Opcode.Call:
				Value[] callArgs = popt();
				Value base = popv();
				push(Value.makeTuple(base.call(callArgs)));
				break;
			case Opcode.NamecallPrep:
				size_t index = cast(size_t) read!CommonOperand;
				Value base = popv();
				push(base);
				push(base.get(Value(getString(index))));
				break;
			case Opcode.Namecall:
				Value[] callArgs = popt();
				Value method = popv();
				Value base = popv();
				push(Value.makeTuple(method.call(base ~ callArgs)));
				break;
			case Opcode.Drop:
				pop();
				break;
			case Opcode.Dup:
				Value v = pop();
				push(v);
				push(v);
				break;
			case Opcode.DupN:
				size_t count = cast(size_t) read!StackOffset;
				Value v = pop();
				foreach (i; 0 .. count + 1) {
					push(v);
				}
				break;
			case Opcode.LdNil:
				push(Value());
				break;
			case Opcode.LdFalse:
				push(Value(false));
				break;
			case Opcode.LdTrue:
				push(Value(true));
				break;
			case Opcode.LdArgs:
				push(Value.makeTuple(args));
				break;
			case Opcode.NewTable:
				push(Value(new TableValue));
				break;
			case Opcode.GetTable:
				Value key = popv();
				Value base = popv();
				push(base.get(key));
				break;
			case Opcode.SetTable:
				Value value = popv();
				Value key = popv();
				Value base = popv();
				base.set(key, value);
				break;
			case Opcode.SetTableRev:
				Value base = popv();
				Value key = popv();
				Value value = popv();
				base.set(key, value);
				break;
			case Opcode.SetArray:
				const count = cast(size_t) read!StackOffset;
				Value[] tuple;

				foreach (i; 0 .. count) {
					tuple ~= pop();
				}

				tuple = Value.makeTuple(tuple.reverse).tuple;

				Value table = popv();

				foreach (i; 0 .. tuple.length) {
					table.set(Value(i + 1), tuple[i]);
				}

				break;
			case Opcode.DropLoop:
				forStack = forStack[0 .. $ - 1];
				break;
			case Opcode.LdStr:
				const index = cast(size_t) read!CommonOperand;
				push(Value(getString(index)));
				break;
			case Opcode.Jmp:
				size_t jumpTo = cast(size_t) read!FullWidth;
				ip = jumpTo;
				break;
			case Opcode.JmpT:
				size_t jumpTo = cast(size_t) read!FullWidth;
				const Value v = popv();
				if (v.toBool) {
					ip = jumpTo;
				}
				break;
			case Opcode.JmpF:
				size_t jumpTo = cast(size_t) read!FullWidth;
				const Value v = popv();
				if (!v.toBool) {
					ip = jumpTo;
				}
				break;
			case Opcode.JmpNil:
				size_t jumpTo = cast(size_t) read!FullWidth;
				if (popv().isNil) {
					ip = jumpTo;
				}
				break;
			case Opcode.Pack:
				const count = cast(size_t) read!StackOffset;
				Value[] tuple;

				foreach (i; 0 .. count) {
					tuple ~= pop();
				}

				push(Value.makeTuple(tuple.reverse));
				break;
			case Opcode.Unpack:
				const count = cast(size_t) read!StackOffset;
				const Value[] last = popt();

				if (count > last.length) {
					foreach (i; last.length .. count) {
						push(Value());
					}
					foreach_reverse (i; 0 .. last.length) {
						push(last[i]);
					}
				}
				else {
					foreach_reverse (i; 0 .. count) {
						push(last[i]);
					}
				}

				break;
			case Opcode.UnpackD:
				const count = cast(size_t) read!StackOffset;
				Value[] last = popt();

				if (count > last.length) {
					foreach (i; last.length .. count) {
						push(Value());
					}
					foreach_reverse (i; 0 .. last.length) {
						push(last[i]);
					}
				}
				else {
					foreach_reverse (i; 0 .. count) {
						push(last[i]);
					}
				}

				push(Value.rawTupleUnsafe(count >= last.length ? [] : last[count .. $]));

				break;
			case Opcode.UnpackRev:
				const count = cast(size_t) read!StackOffset;
				const Value[] last = popt();

				if (count > last.length) {
					foreach (i; 0 .. last.length) {
						push(last[i]);
					}
					foreach (i; last.length .. count) {
						push(Value());
					}
				}
				else {
					foreach (i; 0 .. count) {
						push(last[i]);
					}
				}

				break;
			case Opcode.Mkhv:
				const size_t var = cast(size_t) read!CommonOperand;
				locals[var] = Value(new Value);
				break;
			case Opcode.Get:
				push(locals[cast(size_t) read!CommonOperand]);
				break;
			case Opcode.Set:
				locals[cast(size_t) read!CommonOperand] = popv();
				break;
			case Opcode.GetC:
				push(*func.upvalues[cast(size_t) read!CommonOperand]);
				break;
			case Opcode.SetC:
				*func.upvalues[cast(size_t) read!CommonOperand] = popv();
				break;
			case Opcode.GetRef:
				Value refv = locals[cast(size_t) read!CommonOperand];
				assert(refv.type == ValueType.Heap);
				push(*refv.heap);
				break;
			case Opcode.SetRef:
				Value refv = locals[cast(size_t) read!CommonOperand];
				assert(refv.type == ValueType.Heap);
				*refv.heap = popv();
				break;
			case Opcode.ForPrep:
				size_t var = cast(size_t) read!CommonOperand;
				const Nullable!double step = coercev(popv());
				const Nullable!double high = coercev(popv());
				const Nullable!double low = coercev(popv());
				if (low.isNull)
					throw new LuaError(Value("'for' initial value must be a number"));
				if (high.isNull)
					throw new LuaError(Value("'for' limit must be a number"));
				if (step.isNull)
					throw new LuaError(Value("'for' step must be a number"));
				ForState state;
				state.var = var;
				state.high = high.get;
				state.step = step.get;
				state.at = low.get - state.step;
				forStack.assumeSafeAppend ~= state;
				locals[var] = Value(state.at);
				break;
			case Opcode.Loop:
				size_t jumpTo = cast(size_t) read!FullWidth;
				ForState* state = &forStack[$ - 1];
				state.at += state.step;
				locals[state.var] = Value(state.at);
				bool repeat = false;
				if (state.step < 0) {
					repeat = state.at >= state.high;
				}
				else if (state.step > 0) {
					repeat = state.at <= state.high;
				}
				if (!repeat) {
					ip = jumpTo;
				}
				break;
			case Opcode.Introspect:
				size_t offset = cast(size_t) read!StackOffset;
				push(stack[sp - offset]);
				break;
			case Opcode.DropTuple:
				size_t amount = cast(size_t) read!StackOffset;
				foreach (i; 0 .. amount)
					pop();
				break;
			case Opcode.LdNum:
				push(Value(read!double));
				break;
			case Opcode.LdFun:
				const ulong index = read!ulong;
				const ulong upvaluesCount = read!ulong;
				Value*[] upvalues;
				foreach (i; 0 .. upvaluesCount) {
					const long uv = read!long;
					if (uv < 0) {
						upvalues ~= func.upvalues[cast(size_t)~uv];
					}
					else {
						Value val = locals[cast(size_t) uv];
						assert(val.type == ValueType.Heap);
						upvalues ~= val.heap;
					}
				}
				const save = ip;
				ip = func.ip;
				const ulong dataLength = read!ulong;
				const ulong funcLength = read!ulong;
				read!ulong;
				read!ulong;
				const ulong codeLength = read!ulong;
				ip = ip + codeLength;
				ip = ip + 8 * dataLength;
				const ulong datasegSize = read!ulong;
				ip = ip + datasegSize;
				const ulong funcsegIndices = ip;
				const ulong funcsegPtr = ip + (funcLength + 1) * 8;
				ip = funcsegIndices + 8 * index;
				ip = funcsegPtr + read!ulong;
				FunctionValue val = new FunctionValue;
				val.env = func.env;
				val.ip = ip;
				val.engine = this;
				val.upvalues = upvalues;
				push(Value(val));
				ip = save;
				break;
			default:
				assert(0, "I don't know how to handle " ~ op.to!string);
			}
		}
	}

	/** Get the FunctionValue for the toplevel function */
	FunctionValue getToplevel(TableValue env) {
		auto res = new FunctionValue;
		res.engine = this;
		res.env = env;
		res.ip = 0;
		return res;
	}

}
