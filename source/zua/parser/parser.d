module zua.parser.parser;
import zua.parser.lexer;
import zua.compiler.ir : BinaryOperation, UnaryOperation;
import zua.diagnostic;
import zua.parser.ast;
import std.typecons;
import std.conv;

private alias PrefixParselet = Expr delegate(Token op);
private alias InfixParselet = Expr delegate(Expr left, Token op);

/** A parser for Lua */
final class Parser {

	private Lexer lexer;
	private Diagnostic[]* diagnostics;

	private PrefixParselet[string] prefixOps;
	private InfixParselet[Tuple!(uint, string)] infixOps;

	/** Any infix operator with a precedence >= this one requires the lhs to be a prefixexp */
	private uint prefixexpTreshold = 85;

	private void registerGenericInfix(bool leftAssociative = true)(uint precedence, string op, BinaryOperation bOp) {
		infixOps[tuple(precedence, op)] = delegate(Expr left, Token opToken) {
			BinaryExpr result = new BinaryExpr();
			result.start = left.start;
			result.opToken = opToken;
			result.lhs = left;
			result.op = bOp;
			static if (leftAssociative) {
				result.rhs = expr(precedence);
			}
			else {
				result.rhs = expr(precedence - 1);
			}
			result.end = lexer.last.get;
			return result;
		};
	}

	private void registerGenericPrefix(uint precedence, string op, UnaryOperation bOp) {
		prefixOps[op] = delegate(Token opToken) {
			UnaryExpr result = new UnaryExpr();
			result.start = opToken;
			result.op = bOp;
			result.expr = expr(precedence);
			result.end = lexer.last.get;
			return result;
		};
	}

	/** Create a new parser */
	this(Lexer lexer, ref Diagnostic[] diagnostics) {
		this.lexer = lexer;
		this.diagnostics = &diagnostics;

		registerGenericInfix(10, "or", BinaryOperation.Or);

		registerGenericInfix(20, "and", BinaryOperation.And);

		registerGenericInfix(30, "<", BinaryOperation.CmpLt);
		registerGenericInfix(30, ">", BinaryOperation.CmpGt);
		registerGenericInfix(30, "<=", BinaryOperation.CmpLe);
		registerGenericInfix(30, ">=", BinaryOperation.CmpGe);
		registerGenericInfix(30, "~=", BinaryOperation.CmpNe);
		registerGenericInfix(30, "==", BinaryOperation.CmpEq);

		registerGenericInfix!false(40, "..", BinaryOperation.Concat);
		
		registerGenericInfix(50, "+", BinaryOperation.Add);
		registerGenericInfix(50, "-", BinaryOperation.Sub);

		registerGenericInfix(60, "*", BinaryOperation.Mul);
		registerGenericInfix(60, "/", BinaryOperation.Div);
		registerGenericInfix(60, "%", BinaryOperation.Mod);

		registerGenericPrefix(70, "not", UnaryOperation.Not);
		registerGenericPrefix(70, "#", UnaryOperation.Length);
		registerGenericPrefix(70, "-", UnaryOperation.Negate);

		registerGenericInfix!false(80, "^", BinaryOperation.Exp);

		prefixOps["("] = delegate(Token opToken) {
			BracketExpr result = new BracketExpr();
			result.start = opToken;
			result.expr = expr();

			lexer.consume!(No.toConsume, "to close bracket expression")(TokenType.Symbol, ")");

			result.end = lexer.last.get;
			return result;
		};

		infixOps[tuple(90u, "(")] = delegate(Expr left, Token opToken) {
			if (cast(BracketExpr)left) {
				const prev = decodeIndex(left.end.index, lexer.source);
				const here = decodeIndex(opToken.index, lexer.source);
				if (prev.line != here.line) {
					Diagnostic err;
					err.message = "ambiguous syntax; is this a function call or two separate expressions?";
					err.type = DiagnosticType.Error;
					err.add(left.end, opToken);

					Quickfix meantToCall = {
						message: "convert to a function call",
						ranges: [QuickfixRange(left.end, opToken, ")(")]
					};
					err.quickfix ~= meantToCall;

					Quickfix separate = {
						message: "convert to separate expressions",
						ranges: [QuickfixRange(left.end, ");")]
					};
					err.quickfix ~= separate;

					*this.diagnostics ~= err;
				}
			}

			CallExpr result = new CallExpr();
			result.start = left.start;
			result.base = left;
			result.args = tupleExpr();

			lexer.consume!(No.toConsume, "to close argument list")(TokenType.Symbol, ")");

			result.end = lexer.last.get;
			return result;
		};

		infixOps[tuple(100u, "[")] = delegate(Expr left, Token _) {
			IndexExpr result = new IndexExpr();
			result.start = left.start;
			result.base = left;
			result.key = expr();

			lexer.consume!(No.toConsume, "to close index parameter")(TokenType.Symbol, "]");

			result.end = lexer.last.get;
			return result;
		};

		infixOps[tuple(100u, ".")] = delegate(Expr left, Token _) {
			IndexExpr result = new IndexExpr();
			result.start = left.start;
			result.base = left;

			const ident = lexer.consume(TokenType.Identifier);
			if (ident[0]) {
				StringExpr key = new StringExpr();
				key.start = ident[1];
				key.value = ident[1].value;
				key.end = ident[1];

				result.key = key;
			}
			else {
				ErrorExpr key = new ErrorExpr();
				key.start = ident[1];
				key.end = ident[1];

				result.key = key;
			}

			result.end = lexer.last.get;
			return result;
		};

		infixOps[tuple(100u, ":")] = delegate(Expr left, Token _) {
			CallExpr result = new CallExpr();
			result.start = left.start;
			result.base = left;

			const ident = lexer.consume(TokenType.Identifier);
			if (ident[0]) {
				result.method = ident[1].value;
			}

			lexer.consume!(No.toConsume, "to begin argument list in method call")(TokenType.Symbol, "(");
			result.args = tupleExpr();
			lexer.consume!(No.toConsume, "to close argument list")(TokenType.Symbol, ")");

			result.end = lexer.last.get;
			return result;
		};
	}

	/**
	 * Read a block.
	 * If includeStart is yes, then the immediate next token is skipped over.
	 */
	private Block block(Flag!"includeStart" includeStart)(string endKeyword = "end") {
		Block result = new Block();
		result.start = lexer.peek();
		static if (includeStart == Yes.includeStart) lexer.next();
		while (!lexer.eof && !lexer.isNext(TokenType.Keyword, endKeyword)) {
			result.body ~= stat();
			lexer.tryConsume(TokenType.Symbol, ";");
		}

		if (lexer.eof) {
			Diagnostic err;
			err.message = "missing '" ~ endKeyword ~ "'";
			err.add(lexer.next());
			err.type = DiagnosticType.Error;
			*diagnostics ~= err;
		}
		else {
			lexer.next();
		}

		result.end = lexer.last.get(result.start);
		return result;
	}

	private Block block(string startKeyword = "do", string endKeyword = "end") {
		if (this.lexer.isNext(TokenType.Keyword, startKeyword)) {
			return block!(Yes.includeStart)(endKeyword);
		}
		else {
			lexer.consume!(No.toConsume)(TokenType.Keyword, startKeyword);
			return block!(No.includeStart)(endKeyword);
		}
	}

	private string[] nameList() {
		string[] result;
		auto name = lexer.consume(TokenType.Identifier);

		if (name[0]) result ~= name[1].value;

		while (lexer.isNext(TokenType.Symbol, ",")) {
			lexer.save();
			lexer.next(); // skip over comma
			if (lexer.isNext(TokenType.Identifier)) {
				lexer.discard();
				result ~= lexer.next().value;
			}
			else { // if not an identifier, put the comma back and return
				lexer.restore();
				break;
			}
		}

		return result;
	}

	private Expr[] tupleExpr() {
		if (lexer.isNext(TokenType.Symbol, ")")
			|| lexer.isNext(TokenType.Keyword, "end")
			|| lexer.isNext(TokenType.Keyword, "until")
			|| lexer.isNext(TokenType.Keyword, "else")
			|| lexer.isNext(TokenType.Keyword, "elseif")) return [];

		Expr[] result;
		result ~= expr();

		while (lexer.tryConsume(TokenType.Symbol, ",")) {
			result ~= expr();
		}

		return result;
	}

	private FunctionExpr functionBody() {
		FunctionExpr result = new FunctionExpr();
		result.start = lexer.peek();

		lexer.consume!(No.toConsume)(TokenType.Symbol, "(");

		if (lexer.tryConsume(TokenType.Symbol, "...")) {
			result.variadic = true;
		}
		else if (!lexer.isNext(TokenType.Symbol, ")")) {
			result.args = nameList();
			if (lexer.tryConsume(TokenType.Symbol, ",")) {
				result.variadic = true;
				lexer.consume!(Yes.toConsume)(TokenType.Symbol, "...");
			}
		}

		lexer.consume!(No.toConsume)(TokenType.Symbol, ")");

		result.body = block!(No.includeStart);

		result.end = lexer.last.get(result.start);
		return result;
	}

	private Stat stat() {
		if (lexer.isNext(TokenType.Keyword, "do")) {
			return block();
		}
		else if (lexer.tryConsume(TokenType.Keyword, "while")) {
			WhileStat result = new WhileStat();
			result.start = lexer.last.get;
			result.cond = expr();
			result.body = block();
			result.end = lexer.last.get;
			return result;
		}
		else if (lexer.isNext(TokenType.Keyword, "repeat")) {
			RepeatStat result = new RepeatStat();
			result.start = lexer.peek();
			result.body = block("repeat", "until");
			result.endCond = expr();
			result.end = lexer.last.get;
			return result;
		}
		else if (lexer.tryConsume(TokenType.Keyword, "if")) {
			IfStat result = new IfStat();
			result.start = lexer.last.get;

			enum IfBlockType {
				If,
				Else,
				End
			}

			IfBlockType nextType = IfBlockType.If;
			while (nextType == IfBlockType.If) {
				Expr ifCond = expr();
				Block ifBody = new Block();
				ifBody.start = lexer.consume!(No.toConsume)(TokenType.Keyword, "then")[1];
				while (!lexer.eof && !lexer.isNext(TokenType.Keyword, "end") && !lexer.isNext(TokenType.Keyword, "elseif")
					&& !lexer.isNext(TokenType.Keyword, "else")) {
					ifBody.body ~= stat();
					lexer.tryConsume(TokenType.Symbol, ";");
				}

				if (lexer.eof) {
					Diagnostic err;
					err.message = "missing 'end'";
					err.add(lexer.next());
					err.type = DiagnosticType.Error;
					*diagnostics ~= err;
				}
				else {
					if (lexer.isNext(TokenType.Keyword, "end")) nextType = IfBlockType.End;
					else if (lexer.isNext(TokenType.Keyword, "elseif")) nextType = IfBlockType.If;
					else if (lexer.isNext(TokenType.Keyword, "else")) nextType = IfBlockType.Else;
					lexer.next();
				}

				ifBody.end = lexer.last.get;
				result.entries ~= cast(Tuple!(Expr, "cond", Block, "body"))tuple(ifCond, ifBody);
			}

			if (nextType == IfBlockType.Else) {
				result.elseBody = block!(No.includeStart).nullable;
			}

			result.end = lexer.last.get;
			return result;
		}
		else if (lexer.tryConsume(TokenType.Keyword, "for")) {
			Token start = lexer.last.get;
			Tuple!(bool, Token) firstVar = lexer.consume(TokenType.Identifier);
			if (!firstVar[0]) {
				ErrorStat stat = new ErrorStat();
				stat.start = start;
				stat.end = start;
				return stat;
			}

			if (lexer.tryConsume(TokenType.Symbol, "=")) {
				NumericForStat result = new NumericForStat();
				result.start = start;
				result.var = firstVar[1].value;
				result.low = expr();
				lexer.consume(TokenType.Symbol, ",");
				result.high = expr();
				if (lexer.tryConsume(TokenType.Symbol, ",")) {
					result.step = expr();
				}
				result.body = block();
				result.end = lexer.last.get;
				return result;
			}
			else {
				ForeachStat result = new ForeachStat();
				result.start = start;
				result.vars ~= firstVar[1].value;
				if (lexer.tryConsume(TokenType.Symbol, ",")) {
					result.vars ~= nameList();
				}
				lexer.consume(TokenType.Keyword, "in");
				result.iter = tupleExpr();
				result.body = block();
				result.end = lexer.last.get;
				return result;
			}
		}
		else if (lexer.tryConsume(TokenType.Keyword, "local")) {
			if (lexer.tryConsume(TokenType.Keyword, "function")) {
				FunctionDeclarationStat result = new FunctionDeclarationStat();
				result.start = lexer.last.get;
				auto name = lexer.consume(TokenType.Identifier);
				if (name[0]) {
					result.key = name[1].value;
				}
				else {
					result.key = "";
				}

				FunctionExpr fn = functionBody();
				fn.start = result.start;
				result.value = fn;
				result.end = lexer.last.get;
				return result;
			}
			else {
				DeclarationStat result = new DeclarationStat();
				result.start = lexer.last.get;
				result.keys = nameList();
				if (lexer.tryConsume(TokenType.Symbol, "=")) {
					result.values = tupleExpr();
				}
				result.end = lexer.last.get;
				return result;
			}
		}
		else if (lexer.tryConsume(TokenType.Keyword, "function")) {
			AssignStat result = new AssignStat();
			result.start = lexer.last.get;
			auto name = lexer.consume(TokenType.Identifier);
			LvalueExpr key = null;
			if (name[0]) {
				VariableExpr var = new VariableExpr();
				var.start = name[1];
				var.name = name[1].value;
				var.end = name[1];
				key = var;
			}
			else {
				key = new ErrorExpr();
			}

			while (lexer.tryConsume(TokenType.Symbol, ".")) {
				auto indexName = lexer.consume(TokenType.Identifier);
				if (indexName[0]) {
					IndexExpr var = new IndexExpr();
					var.start = key.start;
					StringExpr str = new StringExpr;
					str.start = indexName[1];
					str.value = indexName[1].value;
					str.end = indexName[1];
					var.base = key;
					var.key = str;
					var.end = lexer.last.get;
					key = var;
				}
				else {
					key = new ErrorExpr();
					break;
				}
			}

			bool namecall = false;

			if (lexer.tryConsume(TokenType.Symbol, ":")) {
				auto indexName = lexer.consume(TokenType.Identifier);
				if (indexName[0]) {
					IndexExpr var = new IndexExpr();
					var.start = key.start;
					StringExpr str = new StringExpr;
					str.start = indexName[1];
					str.value = indexName[1].value;
					str.end = indexName[1];
					var.base = key;
					var.key = str;
					var.end = lexer.last.get;
					key = var;
					namecall = true;
				}
				else {
					key = new ErrorExpr();
				}
			}

			result.keys ~= key;

			FunctionExpr fn = functionBody();
			fn.start = result.start;
			result.values ~= fn;
			result.end = lexer.last.get;
			if (namecall) {
				fn.args = "self" ~ fn.args;
			}
			return result;
		}
		else if (lexer.tryConsume(TokenType.Keyword, "return")) {
			ReturnStat result = new ReturnStat();
			result.start = lexer.last.get;
			result.values = tupleExpr();
			result.end = lexer.last.get;
			return result;
		}
		else if (lexer.tryConsume(TokenType.Keyword, "break")) {
			AtomicStat result = new AtomicStat();
			result.start = lexer.last.get;
			result.type = AtomicStatType.Break;
			result.end = lexer.last.get;
			return result;
		}
		else {
			lexer.save();

			Expr base = expr();
			if (cast(LvalueExpr)base && (lexer.isNext(TokenType.Symbol, ",") || lexer.isNext(TokenType.Symbol, "="))) {
				lexer.discard();
				LvalueExpr[] keys;
				keys ~= cast(LvalueExpr)base;
				while (lexer.tryConsume(TokenType.Symbol, ",")) {
					Expr k = expr();
					if (auto lvalue = cast(LvalueExpr)k) {
						keys ~= lvalue;
					}
					else {
						Diagnostic err;
						err.message = "expected lvalue expression";
						err.type = DiagnosticType.Error;
						err.add(k.start, k.end);
						*diagnostics ~= err;
					}
				}
				lexer.consume!(No.toConsume, "to separate keys from values in assignment statement")(TokenType.Symbol, "=");
				AssignStat res = new AssignStat;
				res.start = base.start;
				res.keys = keys;
				res.values = tupleExpr();
				res.end = lexer.last.get;
				return res;
			}
			else if (auto call = cast(CallExpr)base) {
				lexer.discard();
				ExprStat res = new ExprStat;
				res.start = base.start;
				res.end = base.end;
				res.expr = base;
				return res;
			}

			lexer.restore();

			Diagnostic err;
			err.message = "expected statement";
			err.type = DiagnosticType.Error;
			err.add(lexer.next());
			*diagnostics ~= err;

			ErrorStat result = new ErrorStat();
			result.start = lexer.last.get;
			result.end = lexer.last.get;
			return result;
		}
	}

	private Expr atom() {
		if (lexer.isNext(TokenType.Number)) {
			const Token token = lexer.next();
			NumberExpr result = new NumberExpr();
			result.start = token;
			result.value = token.numValue;
			result.end = token;
			return result;
		}
		else if (lexer.isNext(TokenType.String)) {
			const Token token = lexer.next();
			StringExpr result = new StringExpr();
			result.start = token;
			result.value = token.value;
			result.end = token;
			return result;
		}
		else if (lexer.isNext(TokenType.Identifier)) {
			const Token token = lexer.next();
			VariableExpr result = new VariableExpr();
			result.start = token;
			result.name = token.value;
			result.end = token;
			return result;
		}
		else if (lexer.tryConsume(TokenType.Keyword, "nil")) {
			AtomicExpr result = new AtomicExpr();
			result.start = lexer.last.get;
			result.type = AtomicExprType.Nil;
			result.end = lexer.last.get;
			return result;
		}
		else if (lexer.tryConsume(TokenType.Keyword, "false")) {
			AtomicExpr result = new AtomicExpr();
			result.start = lexer.last.get;
			result.type = AtomicExprType.False;
			result.end = lexer.last.get;
			return result;
		}
		else if (lexer.tryConsume(TokenType.Keyword, "true")) {
			AtomicExpr result = new AtomicExpr();
			result.start = lexer.last.get;
			result.type = AtomicExprType.True;
			result.end = lexer.last.get;
			return result;
		}
		else if (lexer.tryConsume(TokenType.Symbol, "...")) {
			AtomicExpr result = new AtomicExpr();
			result.start = lexer.last.get;
			result.type = AtomicExprType.VariadicTuple;
			result.end = lexer.last.get;
			return result;
		}
		else if (lexer.tryConsume(TokenType.Keyword, "function")) {
			const start = lexer.last.get;
			FunctionExpr result = functionBody();
			result.start = start;
			return result;
		}
		else if (lexer.tryConsume(TokenType.Symbol, "{")) {
			TableExpr result = new TableExpr();
			result.start = lexer.last.get;

			while (!lexer.eof && !lexer.isNext(TokenType.Symbol, "}")) {
				if (lexer.tryConsume(TokenType.Symbol, "[")) {
					TableField field;
					field.key = expr();
					lexer.consume!(No.toConsume, "to close key component of table field")(TokenType.Symbol, "]");
					lexer.consume(TokenType.Symbol, "=");
					field.value = expr();
					result.fields ~= cast(FieldEntry)field;
				}
				else if (lexer.isNext(TokenType.Identifier)) {
					lexer.save();
					const keyToken = lexer.next();
					if (lexer.isNext(TokenType.Symbol, "=")) {
						lexer.discard();
						TableField field;
						StringExpr key = new StringExpr();
						key.start = keyToken;
						key.end = keyToken;
						key.value = keyToken.value;
						field.key = key;
						lexer.consume(TokenType.Symbol, "=");
						field.value = expr();
						result.fields ~= cast(FieldEntry)field;
					}
					else {
						lexer.restore();
						result.fields ~= cast(FieldEntry)expr();
					}
				}
				else {
					result.fields ~= cast(FieldEntry)expr();
				}

				if (!lexer.tryConsume(TokenType.Symbol, ";") && !lexer.tryConsume(TokenType.Symbol, ",")) {
					break;
				}
			}

			lexer.consume!(No.toConsume, "to close table constructor")(TokenType.Symbol, "}");

			result.end = lexer.last.get;
			return result;
		}
		else {
			Diagnostic err;
			err.message = "expected expression";
			err.type = DiagnosticType.Error;
			err.add(lexer.next());
			*diagnostics ~= err;
			
			ErrorExpr result = new ErrorExpr();
			result.start = lexer.last.get;
			result.end = lexer.last.get;
			return result;
		}
	}

	private Nullable!PrefixParselet nextPrefixOp() {
		if (lexer.isNext(TokenType.Keyword) || lexer.isNext(TokenType.Symbol)) {
			const op = lexer.peek().value;
			foreach (opStr; prefixOps.byKey) {
				if (opStr == op) return prefixOps[opStr].nullable;
			}
		}
		return Nullable!PrefixParselet();
	}

	private Nullable!(Tuple!(uint, InfixParselet)) nextInfixOp() {
		if (lexer.isNext(TokenType.Keyword) || lexer.isNext(TokenType.Symbol)) {
			const op = lexer.peek().value;
			foreach (pair; infixOps.byKey) {
				if (pair[1] == op) return tuple(pair[0], infixOps[pair]).nullable;
			}
		}
		return Nullable!(Tuple!(uint, InfixParselet))();
	}

	private Expr expr(uint precedence = 0) {
		Expr left;

		const prefixOp = nextPrefixOp();
		if (prefixOp.isNull) {
			left = atom();
		}
		else {
			left = prefixOp.get()(lexer.next());
		}

		bool changes = true;
		outer: while (changes) {
			changes = false;

			auto infixOp = nextInfixOp();
			while (!infixOp.isNull && infixOp.get[0] > precedence) {
				if (infixOp.get[0] >= prefixexpTreshold && !cast(PrefixExpr)left) {
					break outer;
				}

				changes = true;
				left = infixOp.get[1](left, lexer.next());

				infixOp = nextInfixOp();
			}

			// call precedence = 90
			if ((lexer.isNext(TokenType.Symbol, "{") || lexer.isNext(TokenType.String)) && 90 > precedence) {
				if (!cast(PrefixExpr)left) break outer;

				changes = true;
				CallExpr callExpr = new CallExpr();
				callExpr.start = left.start;
				callExpr.base = left;
				callExpr.args ~= atom();
				callExpr.end = lexer.last.get;
				left = callExpr;
			}
		}

		return left;
	}

	/** Parse the top-level block */
	Block toplevel() {
		Block result = new Block();
		result.start = lexer.peek();
		while (!lexer.eof) {
			result.body ~= stat();
			lexer.tryConsume(TokenType.Symbol, ";");
		}

		result.end = lexer.last.get(result.start);
		return result;
	}

}

unittest {
	Diagnostic[] dg;
	const source = q"(
		x, y().b = 3, 4, 6
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	AssignStat a = cast(AssignStat)parser.stat();
	assert(a);
	assert(a.keys.length == 2);
	assert(a.values.length == 3);

	IndexExpr b = cast(IndexExpr)a.keys[1];
	assert(b);

	StringExpr c = cast(StringExpr)b.key;
	assert(c);
	assert(c.value == "b");

	CallExpr d = cast(CallExpr)b.base;
	assert(d);
	assert(d.args == []);

	VariableExpr e = cast(VariableExpr)a.keys[0];
	assert(e);
	assert(e.name == "x");
	
	VariableExpr f = cast(VariableExpr)d.base;
	assert(f);
	assert(f.name == "y");

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = q"(
		for x, y in x, y do
		end
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	ForeachStat a = cast(ForeachStat)parser.stat();
	assert(a);
	assert(a.vars.length == 2);
	assert(a.iter.length == 2);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = q"(
		for x, y in x do
		end
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	ForeachStat a = cast(ForeachStat)parser.stat();
	assert(a);
	assert(a.vars.length == 2);
	assert(a.iter.length == 1);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = q"(
		for x in x do
		end
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	ForeachStat a = cast(ForeachStat)parser.stat();
	assert(a);
	assert(a.vars.length == 1);
	assert(a.iter.length == 1);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = q"(
		for x = 1, 2, 3 do
		end
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	NumericForStat a = cast(NumericForStat)parser.stat();
	assert(a);
	assert(a.var == "x");
	assert(!a.step.isNull);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = q"(
		for x = 1, 2 do
		end
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	NumericForStat a = cast(NumericForStat)parser.stat();
	assert(a);
	assert(a.step.isNull);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = q"(
		if true then
		else
		end
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	IfStat a = cast(IfStat)parser.stat();
	assert(a);
	assert(a.entries.length == 1);
	assert(!a.elseBody.isNull);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = q"(
		if true then
		end
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	IfStat a = cast(IfStat)parser.stat();
	assert(a);
	assert(a.entries.length == 1);
	assert(a.elseBody.isNull);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = q"(
		if true then
		elseif false then
		end
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	IfStat a = cast(IfStat)parser.stat();
	assert(a);
	assert(a.entries.length == 2);
	assert(a.elseBody.isNull);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = q"(
		if true then
		elseif false then
		else
		end
	)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	IfStat a = cast(IfStat)parser.stat();
	assert(a);
	assert(a.entries.length == 2);
	assert(!a.elseBody.isNull);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = "repeat until true";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	RepeatStat a = cast(RepeatStat)parser.stat();
	assert(a);
	assert(cast(AtomicExpr)a.endCond);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = "while true do end";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);

	WhileStat a = cast(WhileStat)parser.stat();
	assert(a);
	assert(cast(AtomicExpr)a.cond);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = "(a)(b)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);
	parser.expr();
	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	const source = "(a)\n(b)";
	Lexer lexer = new Lexer(source, dg);
	Parser parser = new Parser(lexer, dg);
	parser.expr();
	assert(dg.length == 1);
	assert(dg[0].quickfix.length == 2);
	assert(dg[0].quickfix[0].apply(source) == "(a)(b)");
	assert(dg[0].quickfix[1].apply(source) == "(a);\n(b)");
}

unittest {
	Diagnostic[] dg;
	Lexer lexer = new Lexer(q"(
		{
			a = 2;
			["x"] = 3,
			a;
		}

		{ a }
	)", dg);
	Parser parser = new Parser(lexer, dg);

	TableExpr a = cast(TableExpr)parser.expr();

	assert(a);
	assert(a.fields.length == 3);
	assert(a.fields[0].peek!TableField !is null);
	assert(a.fields[1].peek!TableField !is null);
	assert(a.fields[2].peek!Expr !is null);
	assert(cast(StringExpr)a.fields[0].get!TableField.key);
	assert(cast(NumberExpr)a.fields[0].get!TableField.value);
	assert(cast(StringExpr)a.fields[1].get!TableField.key);
	assert(cast(NumberExpr)a.fields[1].get!TableField.value);
	assert(cast(VariableExpr)a.fields[2].get!Expr);

	TableExpr b = cast(TableExpr)parser.expr();
	assert(b);
	assert(b.fields.length == 1);
	assert(b.fields[0].peek!Expr !is null);
	assert(cast(VariableExpr)b.fields[0].get!Expr);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	Lexer lexer = new Lexer(q"(
		a:b(c)

		a(b)

		a.b.c(d)

		a["b"]["c"](d)

		a "b"

		a { b }
	)", dg);
	Parser parser = new Parser(lexer, dg);

	CallExpr a = cast(CallExpr)parser.expr();
	assert(a);
	assert(!a.method.isNull);
	assert(a.method == "b");
	assert(a.args.length == 1);

	CallExpr b = cast(CallExpr)parser.expr();
	assert(b);
	assert(b.method.isNull);
	assert(b.args.length == 1);

	CallExpr c = cast(CallExpr)parser.expr();
	assert(c);
	assert(c.method.isNull);
	assert(c.args.length == 1);
	assert(cast(IndexExpr)c.base);

	CallExpr d = cast(CallExpr)parser.expr();
	assert(d);
	assert(d.method.isNull);
	assert(d.args.length == 1);
	assert(cast(IndexExpr)d.base);

	CallExpr e = cast(CallExpr)parser.expr();
	assert(e);
	assert(e.method.isNull);
	assert(e.args.length == 1);
	assert(cast(VariableExpr)e.base);
	assert(cast(StringExpr)e.args[0]);

	CallExpr f = cast(CallExpr)parser.expr();
	assert(f);
	assert(f.method.isNull);
	assert(f.args.length == 1);
	assert(cast(VariableExpr)f.base);
	assert(cast(TableExpr)f.args[0]);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] dg;
	Lexer lexer = new Lexer(q"(
		2 + 3 * 4

		2 + 3 + 4

		2 * 3 + 4

		2 ^ 3 ^ 4

		(2 + 3) * 4
	)", dg);
	Parser parser = new Parser(lexer, dg);

	BinaryExpr a = cast(BinaryExpr)parser.expr();
	assert(a);
	assert(a.op == BinaryOperation.Add);
	assert(cast(BinaryExpr)a.rhs);

	BinaryExpr b = cast(BinaryExpr)parser.expr();
	assert(b);
	assert(cast(BinaryExpr)b.lhs); // test left-associativity

	BinaryExpr c = cast(BinaryExpr)parser.expr();
	assert(c);
	assert(c.op == BinaryOperation.Add);
	assert(cast(BinaryExpr)c.lhs);

	BinaryExpr d = cast(BinaryExpr)parser.expr();
	assert(d);
	assert(d.op == BinaryOperation.Exp);
	assert(cast(BinaryExpr)d.rhs); // test right-associativity

	BinaryExpr e = cast(BinaryExpr)parser.expr();
	assert(e);
	assert(e.op == BinaryOperation.Mul);
	assert(cast(BracketExpr)e.lhs);
	assert(cast(BinaryExpr)(cast(BracketExpr)e.lhs).expr);

	assert(dg.length == 0);
}

unittest {
	Diagnostic[] d;
	Lexer lexer = new Lexer(q"(
		local function foo(a, ...)
			do end
		end

		local a, b, c

		return 2, "hi", false, ..., true, nil

		function bar() end

		local a = x
	)", d);
	Parser parser = new Parser(lexer, d);

	DeclarationStat fooDecl = cast(DeclarationStat)parser.stat();

	assert(fooDecl);
	assert(fooDecl.keys.length == 1);
	assert(fooDecl.keys[0] == "foo");
	assert(fooDecl.values.length == 1);

	FunctionExpr foo = cast(FunctionExpr)fooDecl.values[0];

	assert(foo.args.length == 1);
	assert(foo.args[0] == "a");
	assert(foo.variadic);

	Stat[] body = foo.body.body;

	assert(body.length == 1);
	assert(cast(Block)body[0]);

	DeclarationStat abcDecl = cast(DeclarationStat)parser.stat();

	assert(abcDecl);
	assert(abcDecl.keys == ["a", "b", "c"]);
	assert(abcDecl.values == []);

	ReturnStat ret = cast(ReturnStat)parser.stat();

	assert(ret);
	assert(ret.values.length == 6);

	{
		NumberExpr retVal = cast(NumberExpr)ret.values[0];

		assert(retVal);
		assert(retVal.value == 2);
	}

	{
		StringExpr retVal = cast(StringExpr)ret.values[1];

		assert(retVal);
		assert(retVal.value == "hi");
	}

	{
		AtomicExpr retVal = cast(AtomicExpr)ret.values[2];

		assert(retVal);
		assert(retVal.type == AtomicExprType.False);
	}

	{
		AtomicExpr retVal = cast(AtomicExpr)ret.values[3];

		assert(retVal);
		assert(retVal.type == AtomicExprType.VariadicTuple);
	}

	{
		AtomicExpr retVal = cast(AtomicExpr)ret.values[4];

		assert(retVal);
		assert(retVal.type == AtomicExprType.True);
	}

	{
		AtomicExpr retVal = cast(AtomicExpr)ret.values[5];

		assert(retVal);
		assert(retVal.type == AtomicExprType.Nil);
	}

	AssignStat barDecl = cast(AssignStat)parser.stat();

	assert(barDecl);
	assert(barDecl.keys.length == 1);
	assert(barDecl.values.length == 1);

	VariableExpr barVar = cast(VariableExpr)barDecl.keys[0];

	assert(barVar);
	assert(barVar.name == "bar");

	FunctionExpr bar = cast(FunctionExpr)barDecl.values[0];

	assert(bar.args.length == 0);
	assert(!bar.variadic);

	assert(bar.body.body.length == 0);

	DeclarationStat aDecl = cast(DeclarationStat)parser.stat();

	assert(aDecl);
	assert(aDecl.keys == ["a"]);
	assert(aDecl.values.length == 1);

	VariableExpr xVar = cast(VariableExpr)aDecl.values[0];

	assert(xVar);
	assert(xVar.name == "x");

	assert(d.length == 0);
}