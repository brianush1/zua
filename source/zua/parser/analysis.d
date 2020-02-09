module zua.parser.analysis;
import zua.parser.ast;
import zua.diagnostic;
import std.variant;

private final class Environment {
	Environment parent;
	bool isVariadicContext;
	bool inLoop;
	bool laststatReached;

	this(Environment parent) {
		this.parent = parent;
		if (parent) {
			isVariadicContext = parent.isVariadicContext;
			inLoop = parent.inLoop;
		}
	}
}

private final class SemanticAnalysis {

	Diagnostic[]* diagnostics;
	Environment env;

	void walk(Stat stat) {
		if (env.laststatReached) {
			Diagnostic err;
			err.type = DiagnosticType.Error;
			err.message = "cannot have any statements after 'return' or 'break'";
			err.add(stat.start, stat.end);
			(*diagnostics) ~= err;
			env.laststatReached = false; // we don't need to spam the user with messages
		}
		if (auto s = cast(AssignStat)stat) return walk(s);
		if (auto s = cast(ExprStat)stat) return walk(s);
		if (auto s = cast(Block)stat) return walk(s);
		if (auto s = cast(DeclarationStat)stat) return walk(s);
		if (auto s = cast(FunctionDeclarationStat)stat) return walk(s);
		if (auto s = cast(WhileStat)stat) return walk(s);
		if (auto s = cast(RepeatStat)stat) return walk(s);
		if (auto s = cast(IfStat)stat) return walk(s);
		if (auto s = cast(NumericForStat)stat) return walk(s);
		if (auto s = cast(ForeachStat)stat) return walk(s);
		if (auto s = cast(ReturnStat)stat) return walk(s);
		if (auto s = cast(AtomicStat)stat) return walk(s);
		assert(0);
	}

	void walk(Expr expr) {
		if (auto e = cast(PrefixExpr)expr) return walk(e);
		if (auto e = cast(AtomicExpr)expr) return walk(e);
		if (auto e = cast(NumberExpr)expr) return walk(e);
		if (auto e = cast(StringExpr)expr) return walk(e);
		if (auto e = cast(FunctionExpr)expr) return walk(e);
		if (auto e = cast(BinaryExpr)expr) return walk(e);
		if (auto e = cast(UnaryExpr)expr) return walk(e);
		if (auto e = cast(TableExpr)expr) return walk(e);
		assert(0);
	}

	void walk(PrefixExpr expr) {
		if (auto e = cast(LvalueExpr)expr) return walk(e);
		if (auto e = cast(BracketExpr)expr) return walk(e);
		if (auto e = cast(CallExpr)expr) return walk(e);
		assert(0);
	}

	void walk(LvalueExpr expr) {
		if (auto e = cast(VariableExpr)expr) return walk(e);
		if (auto e = cast(IndexExpr)expr) return walk(e);
		assert(0);
	}

	void walk(AssignStat stat) {
		foreach (key; stat.keys) walk(key);
		foreach (value; stat.values) walk(value);
	}

	void walk(ExprStat stat) {
		walk(stat.expr);
	}

	void walk(Block stat) {
		env = new Environment(env);
		foreach (child; stat.body) walk(child);
		env = env.parent;
	}

	void walk(DeclarationStat stat) {
		foreach (value; stat.values) walk(value);
	}

	void walk(FunctionDeclarationStat stat) {
		walk(stat.value);
	}

	void walk(WhileStat stat) {
		env = new Environment(env);
		env.inLoop = true;
		walk(stat.cond);
		walk(stat.body);
		env = env.parent;
	}

	void walk(RepeatStat stat) {
		env = new Environment(env);
		env.inLoop = true;
		walk(stat.body);
		walk(stat.endCond);
		env = env.parent;
	}

	void walk(IfStat stat) {
		foreach (e; stat.entries) {
			walk(e.cond);
			walk(e.body);
		}
		if (!stat.elseBody.isNull) {
			walk(stat.elseBody.get);
		}
	}

	void walk(NumericForStat stat) {
		env = new Environment(env);
		env.inLoop = true;
		walk(stat.low);
		walk(stat.high);
		if (!stat.step.isNull) {
			walk(stat.step.get);
		}
		walk(stat.body);
		env = env.parent;
	}

	void walk(ForeachStat stat) {
		env = new Environment(env);
		env.inLoop = true;
		foreach (value; stat.iter) walk(value);
		walk(stat.body);
		env = env.parent;
	}

	void walk(ReturnStat stat) {
		foreach (value; stat.values) walk(value);
		env.laststatReached = true;
	}

	void walk(AtomicStat stat) {
		if (stat.type == AtomicStatType.Break) {
			if (!env.inLoop) {
				Diagnostic err;
				err.type = DiagnosticType.Error;
				err.message = "cannot 'break' outside of a loop";
				err.add(stat.start, stat.end);
				(*diagnostics) ~= err;
			}
			else {
				env.laststatReached = true;
			}
		}
	}

	void walk(VariableExpr expr) {

	}

	void walk(IndexExpr expr) {
		walk(expr.base);
		walk(expr.key);
	}

	void walk(BracketExpr expr) {
		walk(expr.expr);
	}

	void walk(CallExpr expr) {
		walk(expr.base);
		foreach (arg; expr.args) walk(arg);
	}

	void walk(AtomicExpr expr) {
		if (expr.type == AtomicExprType.VariadicTuple) {
			if (!env.isVariadicContext) {
				Diagnostic err;
				err.type = DiagnosticType.Error;
				err.message = "cannot close on variadic arguments";
				err.add(expr.start, expr.end);
				(*diagnostics) ~= err;
			}
		}
	}

	void walk(NumberExpr expr) {

	}

	void walk(StringExpr expr) {

	}

	void walk(FunctionExpr expr) {
		env = new Environment(env);
		env.isVariadicContext = expr.variadic;
		walk(expr.body);
		env = env.parent;
	}

	void walkToplevel(Block stat) {
		env = new Environment(env);
		env.isVariadicContext = true;
		walk(stat);
		env = env.parent;
	}

	void walk(BinaryExpr expr) {
		walk(expr.lhs);
		walk(expr.rhs);
	}

	void walk(UnaryExpr expr) {
		walk(expr.expr);
	}

	void walk(TableExpr expr) {
		foreach (e; expr.fields) {
			e.visit!(
				(TableField field) {
					walk(field.key);
					walk(field.value);
				},
				(Expr expr) {
					walk(expr);
				}
			);
		}
	}

}

/** Perform semantic analysis on a block */
void performAnalysis(ref Diagnostic[] diagnostics, Block block) {
	SemanticAnalysis analysis = new SemanticAnalysis;
	analysis.diagnostics = &diagnostics;
	analysis.walkToplevel(block);
}