module zua.compiler.ir;
import zua.parser.lexer;
import ast = zua.parser.ast;
import std.typecons;
import std.variant;
import std.uuid;

/** Represents a single IR node */
abstract class IRNode {
	/** The range of tokens that represent this IR node */
	Token start;
	Token end; /// ditto
}

/** A statement */
abstract class Stat : IRNode {}

/** An assignment statement */
final class AssignStat : Stat {
	/** A list of lvalues to modify */
	LvalueExpr[] keys;

	/** The values to set each variable to */
	Expr[] values;
}

/** An expression statement */
final class ExprStat : Stat {
	/** The expression to evaluate in this statement */
	Expr expr;
}

/** A block statement */
final class Block : Stat {
	/** A list of statements to be executed by this block */
	Stat[] body;
}

/** A local variable declaration statement */
final class DeclarationStat : Stat {
	/** A list of variables to declare */
	UUID[] keys;

	/** The values to set each variable to */
	Expr[] values;
}

/** A while statement */
final class WhileStat : Stat {
	/** The condition for this while statement */
	Expr cond;

	/** The body of this while statement */
	Block body;
}

/** A repeat statement */
final class RepeatStat : Stat {
	/** The end condition for this repeat statement */
	Expr endCond;

	/** The body of this repeat statement */
	Block body;
}

alias IfEntry = Tuple!(Expr, "cond", Block, "body");

/** An if statement */
final class IfStat : Stat {
	/** The various condition-code pairs in this if statement */
	IfEntry[] entries;

	/** The 'else' body of this if statement */
	Nullable!Block elseBody;
}

/** A numeric for loop */
final class NumericForStat : Stat {
	/** The variable to use in this for loop */
	UUID var;

	/** Defines the range to loop over */
	Expr low;
	Expr high; /// ditto
	Nullable!Expr step; /// ditto

	/** The body of the for loop */
	Block body;
}

/** A foreach loop */
final class ForeachStat : Stat {
	/** The variables to use in this for loop */
	UUID[] vars;

	/** Defines the iterator to loop over */
	Expr[] iter;

	/** The body of the for loop */
	Block body;
}

/** A return statement */
final class ReturnStat : Stat {
	/** The values to return */
	Expr[] values;
}

/** A type of atomic statement */
enum AtomicStatType {
	Break
}

/** An atomic statement */
final class AtomicStat : Stat {
	/** The type of atomic statement this represents */
	AtomicStatType type;
}

/** An expression */
abstract class Expr : IRNode {
}

/** An expression whose value can be set */
abstract class LvalueExpr : Expr {}

/** A global variable expression */
final class GlobalExpr : LvalueExpr {
	/** The name of this global */
	string name;
}

/** A local variable expression */
final class LocalExpr : LvalueExpr {
	/** The unique ID of this local */
	UUID id;
}

/** An upvalue variable expression */
final class UpvalueExpr : LvalueExpr {
	/** The unique ID of this upvalue */
	UUID id;
}

/** An index expression */
final class IndexExpr : LvalueExpr {
	/** The object to index */
	Expr base;

	/** The key to use in indexing the given object */
	Expr key;
}

/** A bracket expression */
final class BracketExpr : Expr {
	/** The expression in the bracket expression */
	Expr expr;
}

/** A function call expression */
final class CallExpr : Expr {
	Expr base; /** The base of the call expression */
	Expr[] args; /** The arguments to use in the call */

	/**
	 * The method name to use in the call.
	 * If supplied, the call is a selfcall, i.e. 'base:method(args)' is called.
	 * Otherwise, 'base' is treated as a function, i.e. 'base(args)' is called.
	 */
	Nullable!string method;
}

/** A type of atomic expression */
enum AtomicExprType {
	Nil,
	False,
	True,
	VariadicTuple
}

/** An atomic expression */
final class AtomicExpr : Expr {
	/** The type of atomic expression this represents */
	AtomicExprType type;
}

/** A number expression */
final class NumberExpr : Expr {
	/** The value of this expression */
	double value;
}

/** A string expression */
final class StringExpr : Expr {
	/** The value of this expression */
	string value;
}

/** A function expression */
final class FunctionExpr : Expr {
	/** A list of argument IDs */
	UUID[] args;

	/** A list of upvalue IDs */
	UUID[] upvalues; // TODO: on dead code elimination, should be recalculated

	/** A list of closed IDs */
	UUID[] closed; // TODO: on dead code elimination, should be recalculated

	/** The number of variables local to this function */
	ulong localsCount;

	/** Determines if the function is variadic */
	bool variadic;

	/** The body of the function */
	Block body;
}

/** A binary operation */
enum BinaryOperation {
	Add,
	Sub,
	Mul,
	Div,
	Exp,
	Mod,
	Concat,
	CmpLt,
	CmpLe,
	CmpGt,
	CmpGe,
	CmpEq,
	CmpNe,
	And,
	Or
}

/** A binary operation expression */
final class BinaryExpr : Expr {
	/** The token representing this operation */
	Token opToken;

	/** The operation performed on the two sides */
	BinaryOperation op;

	Expr lhs; /** The left-hand side of the expression */
	Expr rhs; /** The right-hand side of the expression */
}

/** A unary operation */
enum UnaryOperation {
	Negate,
	Not,
	Length
}

/** A unary operation expression */
final class UnaryExpr : Expr {
	/** The operation performed on the given expression */
	UnaryOperation op;

	/** The expression to manipulate using the given unary operation */
	Expr expr;
}

/** A single field in a table */
struct TableField {
	/** The key component of this field */
	Expr key;

	/** The value component of this field */
	Expr value;
}

alias FieldEntry = Algebraic!(TableField, Expr);

/** A table constructor expression */
final class TableExpr : Expr {
	/** A list of fields in the table */
	FieldEntry[] fields;
}

private final class Environment {
	Environment parent;
	UUID[string] vars;
	UUID[string] upvalues;
	bool[UUID] closed;
	bool isFunction;

	this(bool isFunction, Environment parent) {
		this.isFunction = isFunction;
		this.parent = parent;
	}

	bool has(string var) {
		return var in vars || (parent && parent.has(var));
	}

	bool isUpvalue(string var) {
		if (var in vars) return false;
		if (!parent) return false;

		if (isFunction) {
			return parent.has(var);
		}
		else {
			return parent.isUpvalue(var);
		}
	}

	UUID get(string var) {
		if (var in vars) {
			return vars[var];
		}
		else if (var in upvalues) {
			return upvalues[var];
		}
		else if (parent) {
			UUID res = parent.get(var);
			if (isFunction) {
				Environment at = parent;
				while (!at.isFunction) at = at.parent;
				at.closed[res] = true;
				upvalues[var] = res;
			}
			return res;
		}
		else assert(0);
	}

	UUID make(string var) {
		UUID res = randomUUID();
		vars[var] = res;
		return res;
	}
}

private final class ASTCompiler {

	Environment env;

	Stat compile(ast.Stat stat) {
		if (auto s = cast(ast.AssignStat)stat) return compile(s);
		if (auto s = cast(ast.ExprStat)stat) return compile(s);
		if (auto s = cast(ast.Block)stat) return compile(s);
		if (auto s = cast(ast.DeclarationStat)stat) return compile(s);
		if (auto s = cast(ast.FunctionDeclarationStat)stat) return compile(s);
		if (auto s = cast(ast.WhileStat)stat) return compile(s);
		if (auto s = cast(ast.RepeatStat)stat) return compile(s);
		if (auto s = cast(ast.IfStat)stat) return compile(s);
		if (auto s = cast(ast.NumericForStat)stat) return compile(s);
		if (auto s = cast(ast.ForeachStat)stat) return compile(s);
		if (auto s = cast(ast.ReturnStat)stat) return compile(s);
		if (auto s = cast(ast.AtomicStat)stat) return compile(s);
		assert(0);
	}

	AssignStat compile(ast.AssignStat stat) {
		auto res = new AssignStat;
		res.start = stat.start;
		res.end = stat.end;
		foreach (k; stat.keys) res.keys ~= compile(k);
		foreach (v; stat.values) res.values ~= compile(v);
		return res;
	}

	ExprStat compile(ast.ExprStat stat) {
		auto res = new ExprStat;
		res.start = stat.start;
		res.end = stat.end;
		res.expr = compile(stat.expr);
		return res;
	}

	Block compile(ast.Block stat, bool setupEnv = true) {
		auto res = new Block;
		res.start = stat.start;
		res.end = stat.end;
		if (setupEnv) env = new Environment(false, env);
		foreach (s; stat.body) {
			res.body ~= compile(s);
		}
		if (setupEnv) env = env.parent;
		return res;
	}

	DeclarationStat compile(ast.DeclarationStat stat) {
		auto res = new DeclarationStat;
		res.start = stat.start;
		res.end = stat.end;
		foreach (e; stat.values) {
			res.values ~= compile(e);
		}
		foreach (v; stat.keys) {
			res.keys ~= env.make(v);
		}
		return res;
	}

	Block compile(ast.FunctionDeclarationStat stat) {
		auto res = new Block;
		res.start = stat.start;
		res.end = stat.end;
		auto decl = new DeclarationStat;
		decl.start = stat.start;
		decl.end = stat.start; // this is not a typo (the declaration only refers to the `local` keyword)
		if (stat.key != "") {
			decl.keys ~= env.make(stat.key);
		}
		auto assign = new AssignStat;
		assign.start = stat.start;
		assign.end = stat.end;
		if (stat.key != "") {
			auto lvalue = new LocalExpr;
			lvalue.start = stat.start;
			lvalue.end = stat.end;
			lvalue.id = env.get(stat.key);
			assign.keys ~= lvalue;
		}
		assign.values ~= compile(stat.value);
		res.body ~= decl;
		res.body ~= assign;
		return res;
	}

	WhileStat compile(ast.WhileStat stat) {
		auto res = new WhileStat;
		res.start = stat.start;
		res.end = stat.end;
		res.cond = compile(stat.cond);
		res.body = compile(stat.body);
		return res;
	}

	RepeatStat compile(ast.RepeatStat stat) {
		auto res = new RepeatStat;
		res.start = stat.start;
		res.end = stat.end;
		res.endCond = compile(stat.endCond);
		res.body = compile(stat.body);
		return res;
	}

	IfStat compile(ast.IfStat stat) {
		auto res = new IfStat;
		res.start = stat.start;
		res.end = stat.end;
		foreach (e; stat.entries) {
			res.entries ~= IfEntry(compile(e.cond), compile(e.body));
		}
		if (!stat.elseBody.isNull) {
			res.elseBody = compile(stat.elseBody.get).nullable;
		}
		return res;
	}

	NumericForStat compile(ast.NumericForStat stat) {
		auto res = new NumericForStat;
		res.start = stat.start;
		res.end = stat.end;
		res.low = compile(stat.low);
		res.high = compile(stat.high);
		if (!stat.step.isNull) {
			res.step = compile(stat.step.get).nullable;
		}
		env = new Environment(false, env);
		res.var = env.make(stat.var);
		res.body = compile(stat.body, false);
		env = env.parent;
		return res;
	}

	ForeachStat compile(ast.ForeachStat stat) {
		auto res = new ForeachStat;
		res.start = stat.start;
		res.end = stat.end;
		foreach (e; stat.iter) {
			res.iter ~= compile(e);
		}
		env = new Environment(false, env);
		foreach (v; stat.vars) {
			res.vars ~= env.make(v);
		}
		res.body = compile(stat.body, false);
		env = env.parent;
		return res;
	}

	ReturnStat compile(ast.ReturnStat stat) {
		auto res = new ReturnStat;
		res.start = stat.start;
		res.end = stat.end;
		foreach (v; stat.values) {
			res.values ~= compile(v);
		}
		return res;
	}

	AtomicStat compile(ast.AtomicStat stat) {
		auto res = new AtomicStat;
		res.start = stat.start;
		res.end = stat.end;
		switch (stat.type) {
		case ast.AtomicStatType.Break:
			res.type = AtomicStatType.Break;
			break;
		default: assert(0);
		}
		return res;
	}

	Expr compile(ast.Expr expr) {
		if (auto e = cast(ast.PrefixExpr)expr) return compile(e);
		if (auto e = cast(ast.AtomicExpr)expr) return compile(e);
		if (auto e = cast(ast.NumberExpr)expr) return compile(e);
		if (auto e = cast(ast.StringExpr)expr) return compile(e);
		if (auto e = cast(ast.FunctionExpr)expr) return compile(e);
		if (auto e = cast(ast.BinaryExpr)expr) return compile(e);
		if (auto e = cast(ast.UnaryExpr)expr) return compile(e);
		if (auto e = cast(ast.TableExpr)expr) return compile(e);
		assert(0);
	}

	Expr compile(ast.PrefixExpr expr) {
		if (auto e = cast(ast.LvalueExpr)expr) return compile(e);
		if (auto e = cast(ast.BracketExpr)expr) return compile(e);
		if (auto e = cast(ast.CallExpr)expr) return compile(e);
		assert(0);
	}

	LvalueExpr compile(ast.LvalueExpr expr) {
		if (auto e = cast(ast.VariableExpr)expr) return compile(e);
		if (auto e = cast(ast.IndexExpr)expr) return compile(e);
		assert(0);
	}

	LvalueExpr compile(ast.VariableExpr expr) {
		if (env.has(expr.name)) {
			UUID id = env.get(expr.name);
			if (env.isUpvalue(expr.name)) {
				UpvalueExpr res = new UpvalueExpr;
				res.start = expr.start;
				res.end = expr.end;
				res.id = id;
				return res;
			}
			else {
				LocalExpr res = new LocalExpr;
				res.start = expr.start;
				res.end = expr.end;
				res.id = id;
				return res;
			}
		}
		else {
			GlobalExpr res = new GlobalExpr;
			res.start = expr.start;
			res.end = expr.end;
			res.name = expr.name;
			return res;
		}
	}

	IndexExpr compile(ast.IndexExpr expr) {
		IndexExpr res = new IndexExpr;
		res.start = expr.start;
		res.end = expr.end;
		res.base = compile(expr.base);
		res.key = compile(expr.key);
		return res;
	}

	BracketExpr compile(ast.BracketExpr expr) {
		BracketExpr res = new BracketExpr;
		res.start = expr.start;
		res.end = expr.end;
		res.expr = compile(expr.expr);
		return res;
	}

	CallExpr compile(ast.CallExpr expr) {
		CallExpr res = new CallExpr;
		res.start = expr.start;
		res.end = expr.end;
		res.base = compile(expr.base);
		res.method = expr.method;
		foreach (arg; expr.args) {
			res.args ~= compile(arg);
		}
		return res;
	}

	AtomicExpr compile(ast.AtomicExpr expr) {
		AtomicExpr res = new AtomicExpr;
		res.start = expr.start;
		res.end = expr.end;
		switch (expr.type) {
		case ast.AtomicExprType.Nil:
			res.type = AtomicExprType.Nil;
			break;
		case ast.AtomicExprType.False:
			res.type = AtomicExprType.False;
			break;
		case ast.AtomicExprType.True:
			res.type = AtomicExprType.True;
			break;
		case ast.AtomicExprType.VariadicTuple:
			res.type = AtomicExprType.VariadicTuple;
			break;
		default: assert(0);
		}
		return res;
	}

	NumberExpr compile(ast.NumberExpr expr) {
		NumberExpr res = new NumberExpr;
		res.start = expr.start;
		res.end = expr.end;
		res.value = expr.value;
		return res;
	}

	StringExpr compile(ast.StringExpr expr) {
		StringExpr res = new StringExpr;
		res.start = expr.start;
		res.end = expr.end;
		res.value = expr.value;
		return res;
	}

	FunctionExpr compile(ast.FunctionExpr expr) {
		FunctionExpr res = new FunctionExpr;
		res.start = expr.start;
		res.end = expr.end;
		res.variadic = expr.variadic;
		env = new Environment(true, env);
		foreach (v; expr.args) {
			res.args ~= env.make(v);
		}
		res.body = compile(expr.body, false);
		res.localsCount = env.vars.length;
		foreach (u; env.upvalues.byValue) res.upvalues ~= u;
		foreach (u; env.closed.byKey) res.closed ~= u;
		env = env.parent;
		return res;
	}

	FunctionExpr compileToplevel(ast.Block stat) {
		auto res = new FunctionExpr;
		res.start = stat.start;
		res.end = stat.end;
		res.variadic = true;
		env = new Environment(true, env);
		res.body = compile(stat, false);
		res.localsCount = env.vars.length;
		foreach (u; env.upvalues.byValue) res.upvalues ~= u;
		foreach (u; env.closed.byKey) res.closed ~= u;
		env = env.parent;
		return res;
	}

	BinaryExpr compile(ast.BinaryExpr expr) {
		BinaryExpr res = new BinaryExpr;
		res.start = expr.start;
		res.end = expr.end;
		res.opToken = expr.opToken;
		res.op = expr.op;
		res.lhs = compile(expr.lhs);
		res.rhs = compile(expr.rhs);
		return res;
	}

	UnaryExpr compile(ast.UnaryExpr expr) {
		UnaryExpr res = new UnaryExpr;
		res.start = expr.start;
		res.end = expr.end;
		res.op = expr.op;
		res.expr = compile(expr.expr);
		return res;
	}

	TableExpr compile(ast.TableExpr expr) {
		TableExpr res = new TableExpr;
		res.start = expr.start;
		res.end = expr.end;
		foreach (field; expr.fields) {
			if (auto f = field.peek!(ast.TableField)) {
				TableField compiled = {
					key: compile(f.key),
					value: compile(f.value)
				};
				res.fields ~= FieldEntry(compiled);
			}
			else {
				res.fields ~= FieldEntry(compile(field.get!(ast.Expr)));
			}
		}
		return res;
	}

}

/** Compile an AST block into an IR block */
FunctionExpr compileAST(ast.Block block) {
	return new ASTCompiler().compileToplevel(block);
}

unittest {
	import zua.parser.parser : Parser;
	import zua.diagnostic : Diagnostic;

	Diagnostic[] d;
	auto lexer = new Lexer(q"(
		local i = 2
		print(i)
	)", d);
	auto parser = new Parser(lexer, d);
	auto tree = parser.toplevel();

	assert(tree.body.length == 2);

	const ir = compileAST(tree);

	assert(ir.closed.length == 0);
	assert(ir.upvalues.length == 0);

	auto bd = ir.body;

	const decl = bd.body[0];
	const print = bd.body[1];

	const decl2 = cast(DeclarationStat)decl;
	assert(decl2);

	const print2 = cast(ExprStat)print;
	assert(print2);

	const print3 = cast(CallExpr)print2.expr;
	assert(print3);

	assert(cast(GlobalExpr)print3.base);
	assert(print3.args.length == 1);

	const local = cast(LocalExpr)print3.args[0];
	assert(local);

	assert(decl2.keys.length == 1);
	assert(decl2.keys[0] == local.id);

	assert(d == []);
}

unittest {
	import zua.parser.parser : Parser;
	import zua.diagnostic : Diagnostic;

	Diagnostic[] dg;
	auto lexer = new Lexer(q"(
		for i in i do
			(function()
				return i
				local i
				return i
			end)()
			return i
		end
	)", dg);
	auto parser = new Parser(lexer, dg);
	auto tree = parser.toplevel();

	assert(tree.body.length == 1);

	const ir = compileAST(tree);

	assert(ir.closed.length == 1);
	assert(ir.upvalues.length == 0);

	auto bd = ir.body;

	assert(bd.body.length == 1);

	auto a = cast(ForeachStat)bd.body[0];
	assert(a);
	assert(a.iter.length == 1);
	assert(a.vars.length == 1);
	assert(a.body.body.length == 2);
	assert(a.vars[0] == ir.closed[0]);

	auto b = cast(GlobalExpr)a.iter[0];
	assert(b);
	assert(b.name == "i");

	auto c = cast(ExprStat)a.body.body[0];
	assert(c);

	auto d = cast(CallExpr)c.expr;
	assert(d);
	assert(d.args == []);

	auto de = cast(BracketExpr)d.base;
	assert(de);

	auto e = cast(FunctionExpr)de.expr;
	assert(e);
	assert(e.upvalues.length == 1);
	assert(e.upvalues[0] == a.vars[0]);
	assert(e.args == []);
	assert(!e.variadic);
	assert(e.body.body.length == 3);

	auto f = cast(ReturnStat)e.body.body[0];
	assert(f);
	assert(f.values.length == 1);

	auto g = cast(UpvalueExpr)f.values[0];
	assert(g);
	assert(g.id == a.vars[0]);

	auto h = cast(ReturnStat)a.body.body[1];
	assert(h);
	assert(h.values.length == 1);

	auto i = cast(LocalExpr)h.values[0];
	assert(i);
	assert(i.id == a.vars[0]);

	auto j = cast(DeclarationStat)e.body.body[1];
	assert(j);
	assert(j.keys.length == 1);
	assert(j.values.length == 0);

	auto k = cast(ReturnStat)e.body.body[2];
	assert(k);
	assert(k.values.length == 1);

	auto l = cast(LocalExpr)k.values[0];
	assert(l);
	assert(l.id == j.keys[0]);
	assert(l.id != a.vars[0]);

	assert(dg == []);
}