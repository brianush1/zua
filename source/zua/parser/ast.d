module zua.parser.ast;
import zua.parser.lexer;
import zua.compiler.ir : BinaryOperation, UnaryOperation;
import std.typecons;
import std.variant;

/** Represents a single AST node */
abstract class AstNode {
	/** The range of tokens that represent this AST node */
	Token start;
	Token end; /// ditto
}

/** A statement */
abstract class Stat : AstNode {}

/** An erroneous statement */
final class ErrorStat : Stat {}

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
	string[] keys;

	/** The values to set each variable to */
	Expr[] values;
}

/** A local function declaration statement */
final class FunctionDeclarationStat : Stat {
	/** The variable to declare */
	string key;

	/** The value to assign it */
	FunctionExpr value;
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
	string var;

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
	string[] vars;

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
abstract class Expr : AstNode {}

/** An erroneous expression */
final class ErrorExpr : LvalueExpr {}

/** A prefix expression */
abstract class PrefixExpr : Expr {}

/** An expression whose value can be set */
abstract class LvalueExpr : PrefixExpr {}

/** A variable expression */
final class VariableExpr : LvalueExpr {
	/** The name of this variable */
	string name;
}

/** An index expression */
final class IndexExpr : LvalueExpr {
	/** The object to index */
	Expr base;

	/** The key to use in indexing the given object */
	Expr key;
}

/** A bracket expression */
final class BracketExpr : PrefixExpr {
	/** The expression in the bracket expression */
	Expr expr;
}

/** A function call expression */
final class CallExpr : PrefixExpr {
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
	/** A list of argument names */
	string[] args;

	/** Determines if the function is variadic */
	bool variadic;

	/** The body of the function */
	Block body;
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