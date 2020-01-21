module zua.compiler.utils;
import zua.compiler.sourcemap;
import zua.vm.engine;
import std.uuid;
import std.bitmanip;
import std.variant;
import std.typecons;

alias FullWidth = ulong;
alias StackOffset = ulong;
alias CommonOperand = ulong;
alias OpcodeSize = uint;

/** An abstract VM statement */
abstract class VmStat {}

/** A tag to allow for the creation of a source map */
final class Indices : VmStat {
	/** Start index in source file */
	size_t start;

	/** End index in source file */
	size_t end;

	/** Create a new Indices object */
	this(size_t start, size_t end) {
		this.start = start;
		this.end = end;
	}
}

/** A label for a jump instruction */
final class Label : VmStat {
	/** The id of the label */
	UUID id;

	/** Create a new label */
	this(UUID id) {
		this.id = id;
	}
}

/** An abstract instruction */
abstract class Instruction : VmStat {
	/** The instruction opcode */
	Opcode op;
}

/** An instruction with no operands */
final class AtomicInstruction : Instruction {

	/** Construct a new atomic instruction */
	this(Opcode op) {
		this.op = op;
	}

}

/** The value of an operand */
union OperandValue {
	/** The value of an operand */
	ulong i;
	double d; /// ditto

	/** Create a new OperandValue using an integer */
	this(ulong i) {
		this.i = i;
	}

	/** Create a new OperandValue using a double */
	this(double d) {
		this.d = d;
	}
}

/** An instruction with one operand */
final class MonadInstruction : Instruction {
	/** The value of an operand */
	Algebraic!(OperandValue, UUID) value;

	/** Construct a new monad instruction */
	this(Opcode op, OperandValue value) {
		this.op = op;
		this.value = value;
	}

	/** Construct a new monad instruction */
	this(Opcode op, ulong value) {
		this.op = op;
		this.value = OperandValue(value);
	}

	/** Construct a new monad instruction */
	this(Opcode op, double value) {
		this.op = op;
		this.value = OperandValue(value);
	}

	/** Construct a new monad instruction */
	this(Opcode op, UUID value) {
		this.op = op;
		this.value = value;
	}
}

/** LDFUN instruction */
final class LdFun : Instruction {
	/** The index of the function to load */
	ulong index;

	/** List of locals to close. Must be heap values, otherwise UB ensues */
	ulong[] upvalues;

	/** Construct a new LDFUN instruction */
	this(ulong index, ulong[] upvalues) {
		op = Opcode.LdFun;
		this.index = index;
		this.upvalues = upvalues;
	}
}

/** A function */
final class Function {
	/** String data used in this function */
	string[] data;

	/** Functions used in this function */
	Function[] functions;

	/** The number of local variables to allocate in this function */
	ulong locals;

	/** The number of upvalues to allocate in this function */
	ulong upvalues;

	/** The actual body of this function */
	VmStat[] code;
}

private class BytecodeWriter {

	private Indices indices;

	private ubyte[] buffer;
	private Tuple!(size_t, UUID)[] labelRefs;
	private ulong[UUID] labels;

	private SourceMap map;

	private void write(ushort value) {
		map.write(indices.start, indices.end, 2);
		buffer ~= cast(ubyte)(value & 0xFF);
		buffer ~= cast(ubyte)(value >> 8);
	}

	private void write(uint value) {
		write(cast(ushort)(value & 0xFFFF));
		write(cast(ushort)(value >> 16));
	}

	private void write(ulong value) {
		write(cast(uint)(value & 0xFFFFFFFF));
		write(cast(uint)(value >> 32));
	}

	private void write(string value) {
		write(cast(ulong)value.length);
		map.write(indices.start, indices.end, value.length);
		buffer ~= cast(immutable(ubyte)[])value;
	}

	private void write(size_t len)(ubyte[len] value, size_t index) {
		foreach (b; value) {
			buffer[index] = b;
			index++;
		}
	}

	private void write(Instruction i) {
		write(cast(OpcodeSize)i.op);
		if (const MonadInstruction monad = cast(MonadInstruction)i) {
			if (monad.value.peek!UUID) {
				labelRefs ~= tuple(buffer.length, cast(UUID)monad.value.get!UUID);
				write(0UL);
			}
			else {
				OperandValue v = monad.value.get!OperandValue;
				switch (monad.op) {
				case Opcode.Introspect:
				case Opcode.DropTuple:
				case Opcode.UnpackRev:
				case Opcode.Unpack:
				case Opcode.Pack:
				case Opcode.UnpackD:
				case Opcode.DupN:
				case Opcode.SetArray:
					write(cast(StackOffset)v.i);
					break;
				case Opcode.Loop:
				case Opcode.Jmp:
				case Opcode.JmpT:
				case Opcode.JmpF:
				case Opcode.JmpNil:
					write(cast(FullWidth)v.i);
					break;
				case Opcode.LdNum:
					write(cast(ulong)v.i);
					break;
				default:
					write(cast(CommonOperand)v.i);
					break;
				}
			}
		}
		else if (const LdFun ld = cast(LdFun)i) {
			write(ld.index);
			write(cast(ulong)ld.upvalues.length);
			foreach (uv; ld.upvalues) {
				write(uv);
			}
		}
	}

	/** Write a Function */
	void write(Function func) {
		const saveIndices = indices;
		write(cast(ulong)func.data.length);
		write(cast(ulong)func.functions.length);
		write(cast(ulong)func.locals);
		write(cast(ulong)func.upvalues);
		const index = buffer.length;
		write(0UL); // code size in bytes
		foreach (stat; func.code) {
			if (auto i = cast(Instruction)stat) {
				write(i);
			}
			else if (auto l = cast(Label)stat) {
				labels[l.id] = cast(ulong)buffer.length;
			}
			else if (auto l = cast(Indices)stat) {
				indices = l;
			}
		}
		ulong codeSize = cast(ulong)(buffer.length - index - 8);
		write(nativeToLittleEndian(codeSize), index);

		ulong strIndex = 0;
		foreach (s; func.data) {
			write(strIndex); // string offset in bytes
			strIndex += 8 + s.length;
		}
		write(strIndex); // total string segment size
		foreach (s; func.data) {
			write(s);
		}

		ulong fnIndex = 0;
		size_t offsetIndex = buffer.length;
		foreach (f; func.functions) {
			write(0UL); // function offset in bytes
		}
		write(0UL); // total function segment size
		foreach (f; func.functions) {
			const size_t began = buffer.length;
			write(f);
			const size_t fnSize = buffer.length - began;
			write(nativeToLittleEndian(fnIndex), offsetIndex);
			fnIndex += fnSize;
			offsetIndex += 8;
		}
		write(nativeToLittleEndian(fnIndex), offsetIndex);
		indices = cast(Indices)saveIndices;
	}

	void resolveLabels() {
		foreach (l; labelRefs) {
			const value = labels[l[1]];
			const vBytes = nativeToLittleEndian(value);
			auto i = l[0];
			foreach (b; vBytes) {
				buffer[i] = b;
				i++;
			}
		}
	}

	/** Get the resulting code from this BytecodeWriter */
	const(ubyte)[] result() {
		return buffer;
	}

}

/** Convert a bytecode function into actual bytecode */
immutable(ubyte)[] serialize(Function func, Indices toplevel, SourceMap map) {
	BytecodeWriter writer = new BytecodeWriter;
	writer.map = map;
	writer.indices = toplevel;
	writer.write(func);
	writer.resolveLabels();
	return cast(immutable(ubyte)[])writer.result;
}