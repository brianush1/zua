module zua.vm.dump;
import zua.vm.engine;
import zua.compiler.utils;
import std.stdio;
import std.conv;
import std.bitmanip;
import std.uni;

version(assert) {
	private string formatLua(string s) {
		return "[[" ~ s ~ "]]"; // TODO: make this better
	}

	private class Dumper {

		private ubyte[] buffer;
		size_t ip;
		ulong tabs;

		this(immutable(ubyte)[] buffer) {
			this.buffer = buffer.dup;
		}

		/** Read a single numeric value */
		private T read(T)(size_t index) {
			ubyte[T.sizeof] data = buffer[index..index + T.sizeof];
			return littleEndianToNative!(T, T.sizeof)(data);
		}

		/** Read a string */
		private string readStr(size_t index) {
			const length = cast(size_t)read!ulong(index);
			string result = cast(string)buffer[index + 8..index + 8 + length];
			return result;
		}

		/** Read a single numeric value */
		private T read(T)() {
			ubyte[T.sizeof] data = buffer[ip..ip + T.sizeof];
			ip += T.sizeof;
			return littleEndianToNative!(T, T.sizeof)(data);
		}

		/** Read a string */
		private string readStr() {
			const length = cast(size_t)read!ulong();
			string result = cast(string)buffer[ip..ip + length];
			ip += length;
			return result;
		}

		string prefix() {
			string result;
			foreach (i; 0..tabs * 4) result ~= ' ';
			return result;
		}

		string dumpInst() {
			const Opcode op = cast(Opcode)read!OpcodeSize;
			string opName = op.to!string.toUpper;
			switch (op) {
			case Opcode.Add:
			case Opcode.Sub:
			case Opcode.Mul:
			case Opcode.Div:
			case Opcode.Exp:
			case Opcode.Mod:
			case Opcode.Unm:
			case Opcode.Not:
			case Opcode.Len:
			case Opcode.Concat:
			case Opcode.Eq:
			case Opcode.Ne:
			case Opcode.Lt:
			case Opcode.Le:
			case Opcode.Gt:
			case Opcode.Ge:
			case Opcode.Ret:
			case Opcode.Getfenv:
			case Opcode.Call:
			case Opcode.Drop:
			case Opcode.Dup:
			case Opcode.LdNil:
			case Opcode.LdFalse:
			case Opcode.LdTrue:
			case Opcode.LdArgs:
			case Opcode.NewTable:
			case Opcode.GetTable:
			case Opcode.SetTable:
			case Opcode.SetTableRev:
			case Opcode.DropLoop:
				return opName;
			case Opcode.LdNum:
				return opName ~ " " ~ read!double.to!string;
			case Opcode.LdFun: {
					const ulong index = read!ulong;
					const ulong upvalues = read!ulong;
					string res = opName ~ " " ~ index.to!string ~ ", [";
					foreach (i; 0..upvalues) {
						if (i > 0)
							res ~= ", ";
						const long uv = read!long;
						if (uv < 0) {
							res ~= "upvalue " ~ (~uv).to!string;
						}
						else {
							res ~= "local " ~ uv.to!string;
						}
					}
					return res ~ "]";
				}
			case Opcode.Introspect:
			case Opcode.DropTuple:
			case Opcode.UnpackRev:
			case Opcode.Unpack:
			case Opcode.Pack:
			case Opcode.UnpackD:
			case Opcode.DupN:
			case Opcode.SetArray:
				return opName ~ " " ~ read!StackOffset.to!string;
			case Opcode.Loop:
			case Opcode.Jmp:
			case Opcode.JmpT:
			case Opcode.JmpF:
			case Opcode.JmpNil:
				return opName ~ " " ~ read!FullWidth.to!string;
			default:
				return opName ~ " " ~ read!CommonOperand.to!string;
			}
		}

		string dumpFunc(ulong idx = 0) {
			const ulong dataLength = read!ulong;
			const ulong funcLength = read!ulong;
			const ulong locals = read!ulong;
			const ulong upvalues = read!ulong;
			const ulong codeLength = read!ulong;
			const startIp = ip;
			string result;
			result ~= prefix ~ "function " ~ idx.to!string ~ " (\n";
			tabs++;
			result ~= prefix ~ "locals: " ~ locals.to!string ~ "\n";
			result ~= prefix ~ "upvalues: " ~ upvalues.to!string ~ "\n";
			tabs--;
			result ~= prefix ~ ")\n";
			tabs++;
			// read data segment:
			ip += codeLength;
			const ulong datasegIndices = ip;
			const ulong datasegPtr = ip + (dataLength + 1) * 8;
			foreach (i; 0..dataLength) {
				ip = datasegIndices + 8 * i;
				ip = datasegPtr + read!ulong;
				result ~= prefix ~ "string " ~ i.to!string ~ " = " ~ readStr().formatLua ~ "\n";
			}
			// read function segment:
			ip = datasegIndices;
			ip += 8 * dataLength;
			const ulong datasegSize = read!ulong;
			ip += datasegSize;
			const ulong funcsegIndices = ip;
			const ulong funcsegPtr = ip + (funcLength + 1) * 8;
			foreach (i; 0..funcLength) {
				ip = funcsegIndices + 8 * i;
				ip = funcsegPtr + read!ulong;
				result ~= dumpFunc(i);
			}
			// read code:
			ip = startIp;
			while (ip < startIp + codeLength) {
				result ~= prefix ~ dumpInst() ~ "\n";
			}
			tabs--;
			result ~= prefix ~ "end\n";
			return result;
		}

	}

	/** Dump some bytecode */
	string dump(immutable(ubyte)[] data) {
		return new Dumper(data).dumpFunc();
	}

	unittest {
		import zua.compiler.utils : Indices, OperandValue, AtomicInstruction, MonadInstruction, Function, LdFun, serialize;
		import zua.compiler.sourcemap : SourceMap;

		Function f = new Function;
		f.locals = 5;
		auto a = new AtomicInstruction(Opcode.LdNil);
		f.code ~= a;
		auto c = new MonadInstruction(Opcode.LdNum, OperandValue(5.3));
		f.code ~= c;
		auto d = new LdFun(5, [0, 3]);
		f.code ~= d;

		Function e = new Function;
		e.upvalues = 2;
		f.functions ~= e;

		auto g = new MonadInstruction(Opcode.Pack, OperandValue(7));
		e.code ~= g;

		Function h = new Function;
		h.upvalues = 92;
		f.functions ~= h;

		Function i = new Function;
		i.locals = 54;
		i.upvalues = 4;
		e.functions ~= i;
		
		f.data ~= "hello";
		f.data ~= "world!";

		h.data ~= "Hello, WOrld!";

		auto map = new SourceMap;
		auto b = serialize(f, new Indices(0, 0), map);

		assert(dump(b) == `function 0 (
    locals: 5
    upvalues: 0
)
    string 0 = [[hello]]
    string 1 = [[world!]]
    function 0 (
        locals: 0
        upvalues: 2
    )
        function 0 (
            locals: 54
            upvalues: 4
        )
        end
        PACK 7
    end
    function 1 (
        locals: 0
        upvalues: 92
    )
        string 0 = [[Hello, WOrld!]]
    end
    LDNIL
    LDNUM 5.3
    LDFUN 5, [local 0, local 3]
end
`);
	}
}