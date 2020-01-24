module zua.compiler.compiler;
import zua.compiler.sourcemap;
import zua.compiler.utils;
import zua.compiler.ir;
import zua.vm.engine;
import std.uuid;
import std.range;

private struct Variable {
	bool heap;
	ulong index;
}

private class Environment {
	private ulong[UUID] vars;
	private bool[UUID] closureMap;
	private ulong[UUID] upvalues;
	private ulong varIndex = 0;
	bool hasReturn = false;

	this(FunctionExpr func) {
		ulong uvIndex = 0;
		foreach (id; func.upvalues) {
			upvalues[id] = uvIndex;
			uvIndex++;
		}
		foreach (id; func.closed) {
			closureMap[id] = true;
		}
	}

	bool isRef(UUID var) {
		return (var in closureMap) != null;
	}

	bool isUpvalue(UUID var) {
		return (var in upvalues) != null;
	}

	void set(Function func, UUID id) {
		func.code ~= new MonadInstruction(getSetOp(id), get(id));
	}

	void get(Function func, UUID id) {
		func.code ~= new MonadInstruction(getGetOp(id), get(id));
	}

	Opcode getSetOp(UUID var) {
		if (var in closureMap)
			return Opcode.SetRef;
		else if (var in upvalues)
			return Opcode.SetC;
		else
			return Opcode.Set;
	}

	Opcode getGetOp(UUID var) {
		if (var in closureMap)
			return Opcode.GetRef;
		else if (var in upvalues)
			return Opcode.GetC;
		else
			return Opcode.Get;
	}

	ulong get(UUID var) {
		if (var in vars) {
			return vars[var];
		}
		else if (var in upvalues) {
			return upvalues[var];
		}
		else {
			vars[var] = varIndex;
			varIndex++;
			return varIndex - 1;
		}
	}

}

private class Compiler {

	Function func;
	Function[] scopeStack;

	Environment env;
	Environment[] envStack;

	UUID[] breakStack;
	UUID[] continueStack;
	UUID[] variadicStack;

	Indices prevIndices;

	void pack(Expr[] tuple) {
		foreach (e; tuple) {
			if (auto call = cast(CallExpr) e) {
				compile(call.base);
				if (call.method.isNull) {
					maybePack(call.args);
					func.code ~= new AtomicInstruction(Opcode.Call);
				}
				else {
					func.code ~= new MonadInstruction(Opcode.NamecallPrep, getString(call.method.get));
					maybePack(call.args);
					func.code ~= new AtomicInstruction(Opcode.Namecall);
				}
			}
			else {
				compile(e);
			}
		}
		func.code ~= new MonadInstruction(Opcode.Pack, tuple.length);
	}

	void maybePack(Expr expr) {
		if (auto call = cast(CallExpr) expr) {
			compile(call.base);
			if (call.method.isNull) {
				maybePack(call.args);
				func.code ~= new AtomicInstruction(Opcode.Call);
			}
			else {
				func.code ~= new MonadInstruction(Opcode.NamecallPrep, getString(call.method.get));
				maybePack(call.args);
				func.code ~= new AtomicInstruction(Opcode.Namecall);
			}
		}
		else {
			compile(expr);
		}
	}

	void maybePack(Expr[] tuple) {
		if (tuple.length == 1) {
			maybePack(tuple[0]);
		}
		else {
			pack(tuple);
		}
	}

	void declare(UUID[] vars, Expr[] values) {
		maybePack(values);
		func.code ~= new MonadInstruction(Opcode.Unpack, vars.length);
		foreach (id; vars) {
			if (env.isRef(id))
				func.code ~= new MonadInstruction(Opcode.Mkhv, env.get(id));
			env.set(func, id);
		}
	}

	ulong getString(string str) {
		auto res = func.data.length;
		func.data ~= str;
		return res;
	}

	void pushString(string str) {
		func.code ~= new MonadInstruction(Opcode.LdStr, getString(str));
	}

	Indices indexNode(IRNode node) {
		// import std.stdio : writeln;

		// writeln(node.start.index);
		// writeln(node.end.index + node.end.rawValue.length);
		return new Indices(node.start.index, node.end.index + node.end.rawValue.length);
	}

	/** Compile an IR node */
	void compile(Stat stat) {
		auto save = prevIndices; // @suppress(dscanner.suspicious.unmodified)
		prevIndices = indexNode(stat);
		func.code ~= prevIndices;
		if (auto s = cast(AssignStat) stat)
			compilev(s);
		else if (auto s = cast(ExprStat) stat)
			compilev(s);
		else if (auto s = cast(Block) stat)
			compilev(s);
		else if (auto s = cast(DeclarationStat) stat)
			compilev(s);
		else if (auto s = cast(WhileStat) stat)
			compilev(s);
		else if (auto s = cast(RepeatStat) stat)
			compilev(s);
		else if (auto s = cast(IfStat) stat)
			compilev(s);
		else if (auto s = cast(NumericForStat) stat)
			compilev(s);
		else if (auto s = cast(ForeachStat) stat)
			compilev(s);
		else if (auto s = cast(ReturnStat) stat)
			compilev(s);
		else if (auto s = cast(AtomicStat) stat)
			compilev(s);
		else
			assert(0);
		prevIndices = save;
		func.code ~= prevIndices;
	}

	/// ditto
	void compile(Expr expr) {
		auto save = prevIndices; // @suppress(dscanner.suspicious.unmodified)
		prevIndices = indexNode(expr);
		func.code ~= prevIndices;
		if (auto e = cast(AtomicExpr) expr)
			compilev(e);
		else if (auto e = cast(NumberExpr) expr)
			compilev(e);
		else if (auto e = cast(StringExpr) expr)
			compilev(e);
		else if (auto e = cast(FunctionExpr) expr)
			compilev(e);
		else if (auto e = cast(BinaryExpr) expr)
			compilev(e);
		else if (auto e = cast(UnaryExpr) expr)
			compilev(e);
		else if (auto e = cast(TableExpr) expr)
			compilev(e);
		else if (auto e = cast(LvalueExpr) expr)
			compile(e);
		else if (auto e = cast(BracketExpr) expr)
			compilev(e);
		else if (auto e = cast(CallExpr) expr)
			compilev(e);
		else
			assert(0);
		prevIndices = save;
		func.code ~= prevIndices;
	}

	/// ditto
	void compile(LvalueExpr expr) {
		auto save = prevIndices; // @suppress(dscanner.suspicious.unmodified)
		prevIndices = indexNode(expr);
		func.code ~= prevIndices;
		if (auto e = cast(GlobalExpr) expr)
			compilev(e);
		else if (auto e = cast(LocalExpr) expr)
			compilev(e);
		else if (auto e = cast(UpvalueExpr) expr)
			compilev(e);
		else if (auto e = cast(IndexExpr) expr)
			compilev(e);
		else
			assert(0);
		prevIndices = save;
		func.code ~= prevIndices;
	}

	/// ditto
	void compilev(Expr[] tuple) {
		if (tuple.length == 0) {
			func.code ~= new AtomicInstruction(Opcode.LdNil);
		}
		else {
			compile(tuple[0]);
			foreach (e; tuple[1 .. $]) {
				compile(e);
				func.code ~= new AtomicInstruction(Opcode.Drop);
			}
		}
	}

	/// ditto
	void compilev(AssignStat stat) {
		if (stat.keys.length == 1) {
			auto key = stat.keys[0];
			if (auto e = cast(IndexExpr) key) {
				compile(e.base);
				compile(e.key);
			}
			else if (auto e = cast(GlobalExpr) key) {
				func.code ~= new AtomicInstruction(Opcode.Getfenv);
				pushString(e.name);
			}
			compile(stat.values[0]);
			if (auto e = cast(LocalExpr) key) {
				env.set(func, e.id);
			}
			else if (auto e = cast(UpvalueExpr) key) {
				env.set(func, e.id);
			}
			else {
				func.code ~= new AtomicInstruction(Opcode.SetTable);
			}
			return;
		}

		ulong dropCount = 0;
		foreach (key; stat.keys) {
			if (auto e = cast(IndexExpr) key) {
				compile(e.base);
				compile(e.key);
				dropCount += 2;
			}
			else if (!cast(LocalExpr) key && !cast(UpvalueExpr) key && !cast(GlobalExpr) key)
				assert(0);
		}
		maybePack(stat.values);
		// a, b, c = d, e, f
		func.code ~= new MonadInstruction(Opcode.UnpackRev, stat.keys.length);
		// stack: f, e, d <top>
		ulong offset = stat.keys.length;
		foreach (key; stat.keys.retro) {
			if (auto e = cast(GlobalExpr) key) {
				pushString(e.name);
				func.code ~= new AtomicInstruction(Opcode.Getfenv);
				func.code ~= new AtomicInstruction(Opcode.SetTableRev);
			}
			else if (auto e = cast(LocalExpr) key) {
				env.set(func, e.id);
			}
			else if (auto e = cast(UpvalueExpr) key) {
				env.set(func, e.id);
			}
			else if (auto e = cast(IndexExpr) key) {
				func.code ~= new MonadInstruction(Opcode.Introspect, offset);
				offset++;
				func.code ~= new MonadInstruction(Opcode.Introspect, offset + 1);
				offset++;
				func.code ~= new AtomicInstruction(Opcode.SetTableRev);
				offset -= 3;
				offset += 2;
				offset++; // to make up for decrementing right after
			}
			else
				assert(0);

			offset--;
		}
		func.code ~= new MonadInstruction(Opcode.DropTuple, dropCount);
	}

	/// ditto
	void compilev(ExprStat stat) {
		compile(stat.expr);
		func.code ~= new AtomicInstruction(Opcode.Drop);
	}

	/// ditto
	void compilev(Block stat) {
		foreach (s; stat.body)
			compile(s);
	}

	/// ditto
	void compilev(DeclarationStat stat) {
		declare(stat.keys, stat.values);
	}

	/// ditto
	void compilev(WhileStat stat) {
		const UUID start = randomUUID();
		const UUID skip = randomUUID();
		func.code ~= new Label(start);
		compile(stat.cond);
		func.code ~= new MonadInstruction(Opcode.JmpF, skip);
		compile(stat.body);
		func.code ~= new MonadInstruction(Opcode.Jmp, start);
		func.code ~= new Label(skip);
	}

	/// ditto
	void compilev(RepeatStat stat) {
		const UUID start = randomUUID();
		func.code ~= new Label(start);
		compile(stat.body);
		compile(stat.endCond);
		func.code ~= new MonadInstruction(Opcode.JmpF, start);
	}

	/// ditto
	void compilev(IfStat stat) {
		const UUID finished = randomUUID();
		foreach (entry; stat.entries) {
			compile(entry.cond);
			const UUID skip = randomUUID();
			func.code ~= new MonadInstruction(Opcode.JmpF, skip);
			compile(entry.body);
			func.code ~= new MonadInstruction(Opcode.Jmp, finished);
			func.code ~= new Label(skip);
		}
		if (!stat.elseBody.isNull)
			compile(stat.elseBody.get);
		func.code ~= new Label(finished);
	}

	/// ditto
	void compilev(NumericForStat stat) {
		const UUID endLabel = randomUUID();
		const UUID breakLabel = randomUUID();
		const UUID continueLabel = randomUUID();
		compile(stat.low);
		compile(stat.high);
		if (stat.step.isNull) {
			func.code ~= new MonadInstruction(Opcode.LdNum, 1.0);
		}
		else {
			compile(stat.step.get);
			func.code ~= new AtomicInstruction(Opcode.Dup);
			func.code ~= new MonadInstruction(Opcode.LdNum, 0.0);
			func.code ~= new AtomicInstruction(Opcode.Eq);
			func.code ~= new MonadInstruction(Opcode.JmpT, endLabel);
		}
		const bool isRef = env.isRef(stat.var);
		const UUID iteratorVar = randomUUID();
		if (isRef) {
			func.code ~= new MonadInstruction(Opcode.ForPrep, env.get(iteratorVar));
		}
		else {
			func.code ~= new MonadInstruction(Opcode.ForPrep, env.get(stat.var));
		}
		const UUID jumpBack = randomUUID();
		func.code ~= new Label(jumpBack);
		func.code ~= new MonadInstruction(Opcode.Loop, breakLabel);
		const UUID start = randomUUID();
		func.code ~= new Label(start);
		if (isRef) {
			func.code ~= new MonadInstruction(Opcode.Mkhv, env.get(stat.var));
			func.code ~= new MonadInstruction(Opcode.Get, env.get(iteratorVar));
			func.code ~= new MonadInstruction(Opcode.SetRef, env.get(stat.var));
		}
		breakStack ~= breakLabel;
		continueStack ~= continueLabel;
		compile(stat.body);
		breakStack = breakStack[0 .. $ - 1];
		continueStack = continueStack[0 .. $ - 1];
		func.code ~= new Label(continueLabel);
		func.code ~= new MonadInstruction(Opcode.Jmp, jumpBack);
		func.code ~= new Label(breakLabel);
		func.code ~= new AtomicInstruction(Opcode.DropLoop);
		func.code ~= new Label(endLabel);
	}

	/// ditto
	void compilev(ForeachStat stat) {
		const UUID fvar = randomUUID();
		const UUID svar = randomUUID();
		const UUID var = randomUUID();
		maybePack(stat.iter);
		func.code ~= new MonadInstruction(Opcode.Unpack, 3);
		env.set(func, fvar);
		env.set(func, svar);
		env.set(func, var);

		const UUID breakLabel = randomUUID();
		const UUID continueLabel = randomUUID();
		
		func.code ~= new Label(continueLabel);
		env.get(func, fvar);
		env.get(func, svar);
		env.get(func, var);
		func.code ~= new MonadInstruction(Opcode.Pack, 2);
		func.code ~= new AtomicInstruction(Opcode.Call);
		func.code ~= new MonadInstruction(Opcode.Unpack, stat.vars.length);
		env.set(func, var);
		env.get(func, var);
		foreach (v; stat.vars) {
			if (env.isRef(v)) {
				func.code ~= new MonadInstruction(Opcode.Mkhv, env.get(v));
			}
			env.set(func, v);
		}
		env.get(func, var);
		func.code ~= new MonadInstruction(Opcode.JmpNil, breakLabel);
		breakStack ~= breakLabel;
		continueStack ~= continueLabel;
		compile(stat.body);
		breakStack = breakStack[0 .. $ - 1];
		continueStack = continueStack[0 .. $ - 1];
		func.code ~= new MonadInstruction(Opcode.Jmp, continueLabel);
		func.code ~= new Label(breakLabel);
	}

	/// ditto
	void compilev(ReturnStat stat) {
		env.hasReturn = true;
		maybePack(stat.values);
		func.code ~= new AtomicInstruction(Opcode.Ret);
	}

	/// ditto
	void compilev(AtomicStat stat) {
		switch (stat.type) {
		case AtomicStatType.Break:
			func.code ~= new MonadInstruction(Opcode.Jmp, breakStack[$ - 1]);
			break;
		default:
			assert(0);
		}
	}

	/// ditto
	void compilev(GlobalExpr expr) {
		func.code ~= new AtomicInstruction(Opcode.Getfenv);
		pushString(expr.name);
		func.code ~= new AtomicInstruction(Opcode.GetTable);
	}

	/// ditto
	void compilev(LocalExpr expr) {
		const ulong i = env.get(expr.id);
		func.code ~= new MonadInstruction(env.isRef(expr.id) ? Opcode.GetRef
				: Opcode.Get, OperandValue(i));
	}

	/// ditto
	void compilev(UpvalueExpr expr) {
		const ulong i = env.get(expr.id);
		func.code ~= new MonadInstruction(Opcode.GetC, OperandValue(i));
	}

	/// ditto
	void compilev(IndexExpr expr) {
		compile(expr.base);
		compile(expr.key);
		func.code ~= new AtomicInstruction(Opcode.GetTable);
	}

	/// ditto
	void compilev(BracketExpr expr) {
		compile(expr.expr);
	}

	/// ditto
	void compilev(CallExpr expr) {
		compile(expr.base);
		if (expr.method.isNull) {
			maybePack(expr.args);
			func.code ~= new AtomicInstruction(Opcode.Call);
		}
		else {
			func.code ~= new MonadInstruction(Opcode.NamecallPrep, getString(expr.method.get));
			maybePack(expr.args);
			func.code ~= new AtomicInstruction(Opcode.Namecall);
		}
		func.code ~= new MonadInstruction(Opcode.Unpack, 1);
	}

	/// ditto
	void compilev(AtomicExpr expr) {
		switch (expr.type) {
		case AtomicExprType.Nil:
			func.code ~= new AtomicInstruction(Opcode.LdNil);
			break;
		case AtomicExprType.False:
			func.code ~= new AtomicInstruction(Opcode.LdFalse);
			break;
		case AtomicExprType.True:
			func.code ~= new AtomicInstruction(Opcode.LdTrue);
			break;
		case AtomicExprType.VariadicTuple:
			env.get(func, variadicStack[$ - 1]);
			break;
		default:
			assert(0);
		}
	}

	/// ditto
	void compilev(NumberExpr expr) {
		func.code ~= new MonadInstruction(Opcode.LdNum, OperandValue(expr.value));
	}

	/// ditto
	void compilev(StringExpr expr) {
		pushString(expr.value);
	}

	/// ditto
	void compilev(FunctionExpr expr, bool toplevel = false) {
		ulong[] upvalues;

		foreach (id; expr.upvalues) {
			assert(env.isRef(id));
			if (env.isUpvalue(id)) {
				upvalues ~= ~env.get(id); // complements are a sort of "magic number"
			}
			else {
				upvalues ~= env.get(id);
			}
		}

		auto child = new Function;

		if (!toplevel) {
			func.code ~= new LdFun(func.functions.length, upvalues);
			func.functions ~= child;
		}

		scopeStack ~= func;
		envStack ~= env;

		func = child;
		child.upvalues = expr.upvalues.length;
		// child.locals = expr.localsCount;

		env = new Environment(expr);

		if (expr.variadic) {
			UUID variadic = randomUUID();
			variadicStack.assumeSafeAppend ~= variadic;
			func.code ~= new AtomicInstruction(Opcode.LdArgs);
			if (expr.args.length > 0)
				func.code ~= new MonadInstruction(Opcode.UnpackD, expr.args.length);
			env.set(func, variadic);
			foreach (arg; expr.args) {
				env.set(func, arg);
			}
		}
		else {
			variadicStack.assumeSafeAppend ~= UUID();
			if (expr.args.length > 0) {
				func.code ~= new AtomicInstruction(Opcode.LdArgs);
				func.code ~= new MonadInstruction(Opcode.Unpack, expr.args.length);
				foreach (arg; expr.args) {
					env.set(func, arg);
				}
			}
		}

		compile(expr.body);

		variadicStack = variadicStack[0 .. $ - 1];

		child.locals = env.vars.length;

		if (!env.hasReturn) {
			func.code ~= new MonadInstruction(Opcode.Pack, 0);
			func.code ~= new AtomicInstruction(Opcode.Ret);
		}

		if (!toplevel) {
			func = scopeStack[$ - 1];
		}
		scopeStack = scopeStack[0 .. $ - 1];

		env = envStack[$ - 1];
		envStack = envStack[0 .. $ - 1];
	}

	/// ditto
	void compilev(BinaryExpr expr) {
		if (expr.op == BinaryOperation.And) {
			compile(expr.lhs);
			func.code ~= new AtomicInstruction(Opcode.Dup);
			const UUID jmp = randomUUID();
			func.code ~= new MonadInstruction(Opcode.JmpF, jmp);
			func.code ~= new AtomicInstruction(Opcode.Drop);
			compile(expr.rhs);
			func.code ~= new Label(jmp);
		}
		else if (expr.op == BinaryOperation.Or) {
			compile(expr.lhs);
			func.code ~= new AtomicInstruction(Opcode.Dup);
			const UUID jmp = randomUUID();
			func.code ~= new MonadInstruction(Opcode.JmpT, jmp);
			func.code ~= new AtomicInstruction(Opcode.Drop);
			compile(expr.rhs);
			func.code ~= new Label(jmp);
		}
		else {
			Opcode op;
			switch (expr.op) {
			case BinaryOperation.Add:
				op = Opcode.Add;
				break;
			case BinaryOperation.Sub:
				op = Opcode.Sub;
				break;
			case BinaryOperation.Mul:
				op = Opcode.Mul;
				break;
			case BinaryOperation.Div:
				op = Opcode.Div;
				break;
			case BinaryOperation.Exp:
				op = Opcode.Exp;
				break;
			case BinaryOperation.Mod:
				op = Opcode.Mod;
				break;
			case BinaryOperation.Concat:
				op = Opcode.Concat;
				break;
			case BinaryOperation.CmpLt:
				op = Opcode.Lt;
				break;
			case BinaryOperation.CmpLe:
				op = Opcode.Le;
				break;
			case BinaryOperation.CmpGt:
				op = Opcode.Gt;
				break;
			case BinaryOperation.CmpGe:
				op = Opcode.Ge;
				break;
			case BinaryOperation.CmpEq:
				op = Opcode.Eq;
				break;
			case BinaryOperation.CmpNe:
				op = Opcode.Ne;
				break;
			default:
				assert(0);
			}
			compile(expr.lhs);
			compile(expr.rhs);
			func.code ~= new AtomicInstruction(op);
		}
	}

	/// ditto
	void compilev(UnaryExpr expr) {
		Opcode op;
		switch (expr.op) {
		case UnaryOperation.Negate:
			op = Opcode.Unm;
			break;
		case UnaryOperation.Not:
			op = Opcode.Not;
			break;
		case UnaryOperation.Length:
			op = Opcode.Len;
			break;
		default:
			assert(0);
		}
		compile(expr.expr);
		func.code ~= new AtomicInstruction(op);
	}

	/// ditto
	void compilev(TableExpr expr) {
		func.code ~= new AtomicInstruction(Opcode.NewTable);
		// auto dupIns = new MonadInstruction(Opcode.DupN, 1);
		// func.code ~= dupIns;
		Expr[] array;
		foreach (field; expr.fields) {
			if (TableField* f = field.peek!TableField) {
				func.code ~= new AtomicInstruction(Opcode.Dup);
				// dupIns.value.peek!OperandValue.i++;
				compile(f.key);
				compile(f.value);
				func.code ~= new AtomicInstruction(Opcode.SetTable);
			}
			else {
				array ~= *field.peek!Expr;
			}
		}
		func.code ~= new AtomicInstruction(Opcode.Dup);
		foreach (field; array) {
			maybePack(field);
		}
		// if (array.length > 0) {
		func.code ~= new MonadInstruction(Opcode.SetArray, array.length);
		// }
		// else {
		// 	dupIns.value.peek!OperandValue.i--;
		// }
	}

	immutable(ubyte)[] buffer(Indices toplevelIndices, SourceMap map) {
		return func.serialize(toplevelIndices, map);
	}

}

/** Compile a top-level function */
immutable(ubyte)[] compile(SourceMap map, FunctionExpr func) {
	Compiler compiler = new Compiler;
	compiler.compilev(func, true);
	return compiler.buffer(new Indices(func.start.index, func.end.index + func.end.rawValue.length), map);
}