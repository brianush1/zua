module zua.parser.lexer;
import zua.diagnostic;
import std.variant;
import std.utf;
import std.typecons;
import std.string;
import std.container.rbtree;
import std.range.primitives;
import std.format;
import std.conv;

/** Describes the type of a token */
enum TokenType {
	Eof,
	Identifier,
	Keyword,
	String,
	Number,
	Symbol,
	Comment,
	BlockComment
}

/** A single token in a source file */
struct Token {

	/** Describes the type of this token */
	TokenType type;

	/** The raw value of this token */
	string rawValue;

	/** The parsed value of this token */
	string value;

	/** Only used for numbers; the numeric value of this token */
	double numValue;

	/** The index at which this token is located */
	size_t index;

}

alias IgnoreCommentTokens = Flag!"ignoreCommentTokens";
alias ToConsume = Flag!"toConsume";

private struct LexerState {
	size_t diagnosticsLength;
	size_t index;
	Nullable!Token last;
}

/** A lexer for Lua */
final class Lexer {

	private string code;
	private size_t index;
	private Diagnostic[]* diagnostics;

	private LexerState[] stateStack;

	private RedBlackTree!string keywords;

	private string[] symbols;

	/** The last consumed token */
	Nullable!Token last;

	/** Create a new lexer from a piece of code */
	this(string code, ref Diagnostic[] diagnostics) {
		this.code = code;
		this.diagnostics = &diagnostics;

		keywords = redBlackTree!string(
			"and", "break", "do", "else", "elseif",
			"end", "false", "for", "function", "if",
			"in", "local", "nil", "not", "or",
			"repeat", "return", "then", "true", "until", "while"
		);

		symbols = [
			"...",

			"..",
			"==", "~=", "<=", ">=",

			"+", "-", "*", "/", "%", "^", "#",
			"<", ">", "=",
			"(", ")", "{", "}", "[", "]",
			";", ":", ",", ".", 
		];
	}

	/** Get the source code that this Lexer is lexing */
	string source() {
		return code;
	}

	/** Save the current state of the lexer */
	void save() {
		const LexerState state = {
			diagnosticsLength: (*diagnostics).length,
			index: index,
			last: last
		};

		stateStack ~= state;
	}

	/** Restore the previously-saved lexer state */
	void restore() {
		const LexerState state = stateStack.back;
		(*diagnostics) = (*diagnostics)[0..state.diagnosticsLength];
		index = state.index;
		last = state.last;

		discard();
	}

	/** Discard the previously-saved lexer state */
	void discard() {
		stateStack.popBack();
	}

	/** Peek a segment of characters */
	private dstring peekChars(size_t length) {
		dstring result;

		size_t prevIndex = index;

		foreach (i; 0..length) {
			if (prevIndex >= code.length) return "";
			result ~= code.decode!(Yes.useReplacementDchar)(prevIndex);
		}

		return result;
	}

	/** Peek the next char */
	private dchar peekChar() {
		if (charEof) return 0;
		size_t prevIndex = index;
		return code.decode!(Yes.useReplacementDchar)(prevIndex);
	}

	/** Consume a segment of characters */
	private dstring nextChars(size_t length) {
		dstring result;

		foreach (i; 0..length) {
			if (charEof) return "";
			result ~= code.decode!(Yes.useReplacementDchar)(index);
		}

		return result;
	}

	/** Consume the next char in the lexer */
	private dchar nextChar() {
		if (charEof) return 0;
		return code.decode!(Yes.useReplacementDchar)(index);
	}

	/** Check if we're at the end of the file */
	private bool charEof() {
		return index >= code.length;
	}

	/** Read a string for as long as the given predicate holds true */
	private string readWhile(bool delegate(dchar c) predicate) {
		string result;
		while (!charEof && predicate(peekChar())) {
			result ~= nextChar();
		}
		return result;
	}

	private void skipWhitespace() {
		readWhile(c => " \t\r\n"d.indexOf(c) != -1);
	}

	private bool isIdentifierCharacter(dchar c) {
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
	}

	private bool isNumeralCharacter(dchar c) {
		return (c >= '0' && c <= '9') || c == '.';
	}

	private bool isHexadecimalCharacter(dchar c) {
		return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
	}

	private Token* readLongString(string tokenName) {
		// assume char = '['
		const size_t prevIndex = index;
		nextChar();
		string open = "[";
		string closeSeq = "]";
		uint level = 0;
		while (peekChar() == '=') {
			level++;
			open ~= '=';
			closeSeq ~= '=';
			nextChar();
		}
		closeSeq ~= ']';
		if (peekChar() == '[') {
			int closeLevel = -1;
			bool closed = false;
			size_t closeBeginP = -1;
			size_t closeBegin = -1;
			size_t closeEnd = -1;
			string rawValue = open ~ readWhile(delegate(ic) {
				if (ic == ']') {
					if (closeBeginP != -1) {
						closeBegin = closeBeginP;
						closeEnd = index + 1;
					}

					if (closeLevel == level) {
						closed = true;
						return false;
					}
					else {
						closeLevel = 0;
						closeBeginP = index;
					}
				}
				else if (ic == '=' && closeLevel != -1) {
					closeLevel++;
				}
				else {
					closeLevel = -1;
				}
				return true;
			});

			if (!closed) {
				Diagnostic err;
				err.type = DiagnosticType.Error;
				err.message = "unclosed " ~ tokenName;
				err.add(index);
				const Quickfix close = {
					message: "add closing sequence to " ~ tokenName,
					ranges: [QuickfixRange(index, index, closeSeq)]
				};
				err.quickfix ~= close;
				if (closeBegin != -1) {
					const Quickfix fixExistingClose = {
						message: "fix existing closing sequence to match level of " ~ tokenName,
						ranges: [QuickfixRange(closeBegin, closeEnd, closeSeq)]
					};
					err.quickfix ~= fixExistingClose;
				}
				*diagnostics ~= err;
			}
			else {
				nextChar();
				rawValue ~= "]";
			}

			string value = rawValue[2 + level .. $ - (2 + level)];

			if (value.length > 0 && value[0] == '\n') {
				value = value[1..$];
			}

			Token* result = new Token;
			result.value = value;
			result.rawValue = rawValue;
			result.type = TokenType.String;
			result.index = prevIndex;
			return result;
		}
		else { // turns out it wasn't a string...
			index = prevIndex;
			return null;
		}
	}

	private Token nextInternal() {
		skipWhitespace();

		Token result;
		result.index = index;

		if (charEof) {
			result.type = TokenType.Eof;
			return result;
		}

		const dchar c = peekChar();

		if (peekChars(2) == "--"d) {
			nextChars(2);

			if (peekChar() == '[') {
				const auto res = readLongString("block comment");
				if (res !is null) {
					result = *res;
					result.type = TokenType.BlockComment;
					return result;
				}
			}

			result.rawValue = result.value = readWhile(delegate(c) {
				return c != '\n';
			});

			result.type = TokenType.Comment;
			return result;
		}

		if (peekChars(2) == "0x"d) {
			nextChars(2);
			const string value = readWhile(delegate(c) {
				return isHexadecimalCharacter(c);
			});

			if (value == "") { // if it's just 0x, it's clearly not a number
				index -= 2; // put it back and continue
			}
			else {
				result.value = value.to!ulong(16).to!string;
				result.numValue = value.to!ulong(16).to!double;
				result.rawValue = "0x" ~ value;
				result.type = TokenType.Number;
				return result;
			}
		}
		else if (isNumeralCharacter(c)) {
			bool dot = false;
			string value = readWhile(delegate(c) {
				if (c == '.') {
					if (dot) return false; // if we already have a dot, don't read two dots
					dot = true;
				}

				return isNumeralCharacter(c);
			});

			if (value == ".") { // if it's just a dot, it's clearly not a number
				index--; // put it back and continue
			}
			else {
				double numValue = value.to!double;
				if (peekChar() == 'e') {
					value ~= 'e';
					nextChar();
					bool pos = true;
					if (peekChar() == '+') {
						value ~= '+';
						nextChar();
					}
					else if (peekChar() == '-') {
						value ~= '-';
						pos = false;
						nextChar();
					}
					const string exp = readWhile(delegate(c) {
						return isNumeralCharacter(c) && c != '.';
					});
					value ~= exp;
					numValue *= 10.0 ^^ ((!pos ? -1 : 1) * exp.to!double);
				}
				result.numValue = numValue;
				result.value = value;
				result.rawValue = value;
				result.type = TokenType.Number;
				return result;
			}
		}

		if (isIdentifierCharacter(c)) {
			const string value = readWhile(&isIdentifierCharacter);
			result.value = value;
			result.rawValue = value;
			result.type = value in keywords ? TokenType.Keyword : TokenType.Identifier;
			return result;
		}

		if (c == '"' || c == '\'') {
			bool escape = false;
			int digits = 0;
			int codepoint = 0;
			string value;
			bool closed = false;
			string rawValue = [nextChar()].toUTF8 ~ readWhile(delegate(ic) {
				if (escape) {
					if (ic == 'a') value ~= '\a';
					else if (ic == 'b') value ~= '\b';
					else if (ic == 'f') value ~= '\f';
					else if (ic == 'n') value ~= '\n';
					else if (ic == 'r') value ~= '\r';
					else if (ic == 't') value ~= '\t';
					else if (ic == 'v') value ~= '\v';
					else if (ic >= '0' && ic <= '9') {
						digits = 1;
						codepoint = ic - '0';
					}
					else value ~= ic;
					escape = false;
				}
				else if (ic == '\n') {
					return false;
				}
				else if (ic >= '0' && ic <= '9' && digits > 0 && digits < 3) {
					digits++;
					codepoint *= 10;
					codepoint += ic - '0';
				}
				else {
					if (digits > 0) {
						value ~= cast(char)codepoint;
						digits = 0;
					}

					if (ic == '\\') escape = true;
					else if (ic == c) {
						closed = true;
						return false;
					}
					else value ~= ic;
				}
				return true;
			});

			if (digits > 0) value ~= cast(char)codepoint;

			if (!closed) {
				Diagnostic err;
				err.type = DiagnosticType.Error;
				err.message = "unclosed string";
				err.add(index);
				if (escape) {
					const Quickfix close = {
						message: "remove extraneous '\\' and add closing quote to string",
						ranges: [QuickfixRange(index - 1, index, [c].toUTF8)]
					};
					err.quickfix ~= close;
				}
				else {
					const Quickfix close = {
						message: "add closing quote to string",
						ranges: [QuickfixRange(index, index, [c].toUTF8)]
					};
					err.quickfix ~= close;
				}
				*diagnostics ~= err;
			}
			else {
				rawValue ~= [nextChar()].toUTF8;
			}

			result.value = value;
			result.rawValue = rawValue;
			result.type = TokenType.String;
			return result;
		}

		if (c == '[') {
			const auto res = readLongString("string");
			if (res !is null) return *res;
		}

		foreach (symbol; symbols) {
			const auto utf32sym = symbol.toUTF32;
			if (peekChars(utf32sym.length) == utf32sym) {
				result.value = symbol;
				result.rawValue = symbol;
				result.type = TokenType.Symbol;
				nextChars(utf32sym.length);
				return result;
			}
		}

		nextChar();
		Diagnostic err;
		err.type = DiagnosticType.Error;
		err.message = "unknown character";
		err.add(result.index, index);
		const Quickfix remove = {
			message: "remove unknown character",
			ranges: [QuickfixRange(result.index, index, "")]
		};
		err.quickfix ~= remove;
		*diagnostics ~= err;

		return nextInternal();
	}

	/** Consume the next token and return it */
	Token next(IgnoreCommentTokens ignoreCommentTokens = Yes.ignoreCommentTokens)() {
		static if (ignoreCommentTokens == Yes.ignoreCommentTokens) {
			Token result = next!(No.ignoreCommentTokens)();
			if (result.type == TokenType.Comment || result.type == TokenType.BlockComment) return next();
			else return result;
		}
		else {
			const Token result = nextInternal();
			last = result;
			return result;
		}
	}

	/** Peek the next token and return it, leaving the lexer in the same state as it was before */
	Token peek(IgnoreCommentTokens ignoreCommentTokens = Yes.ignoreCommentTokens)() {
		save();
		const Token result = next!ignoreCommentTokens();
		restore();
		return result;
	}

	/**
	 * Attempt to consume the next token.
	 * If the token is missing and toConsume is Yes, the following token will be consumed regardless of whether it matches the given pattern.
	 * Returns (false, Token) if the token is not of the required type; returns (true, Token) otherwise
	 */
	Tuple!(bool, Token) consume(ToConsume toConsume = Yes.toConsume, string message = "")
		(TokenType type, string value = "") {
		save();

		Token token;
		if (type == TokenType.Comment || type == TokenType.BlockComment) token = next!(No.ignoreCommentTokens);
		else token = next();

		if (token.type == type && (value == "" || token.value == value)) {
			return tuple(true, token);
		}
		else {
			static if (toConsume == No.toConsume) restore();
			else discard();

			string finalMessage = "expected " ~ type.to!string;

			if (value != "") finalMessage ~= " '" ~ value ~  "'";
			if (message != "") finalMessage ~= " " ~ message;

			finalMessage ~= ", got " ~ token.type.to!string;

			Diagnostic err;
			err.type = DiagnosticType.Error;
			err.message = finalMessage;
			err.add(token);
			*diagnostics ~= err;

			return tuple(false, token);
		}
	}

	/** Check if the next token matches the given pattern */
	bool isNext(TokenType type, string value = "") {
		Token token;
		if (type == TokenType.Comment || type == TokenType.BlockComment) token = peek!(No.ignoreCommentTokens);
		else token = peek();

		return token.type == type && (value == "" || token.value == value);
	}

	/**
	 * Attempt to consume the next token if it matches the given pattern.
	 * Has no effect on the state of the lexer if the token is not found.
	 */
	bool tryConsume(TokenType type, string value = "") {
		if (isNext(type, value)) {
			consume(type, value);
			return true;
		}
		else return false;
	}

	/** Check if the next token is EOF */
	bool eof() {
		return isNext(TokenType.Eof);
	}

}

unittest {
	Diagnostic[] diagnostics;
	Lexer lex = new Lexer(q"(--[[ hello
world ]] ident0__)", diagnostics);

	assert(lex.isNext(TokenType.BlockComment, " hello\nworld "));
	assert(lex.isNext(TokenType.Identifier));
	assert(!lex.isNext(TokenType.Identifier, "a"));

	const Token t = lex.next!(No.ignoreCommentTokens);
	assert(t.type == TokenType.BlockComment);
	assert(t.value == " hello\nworld ");

	assert(diagnostics.length == 0);
}

unittest {
	Diagnostic[] diagnostics;
	Lexer lex = new Lexer(q"(--[[ hello
world ]] ident0__)", diagnostics);

	const Token t = lex.next();
	assert(t.type == TokenType.Identifier);
	assert(t.value == "ident0__");

	assert(diagnostics.length == 0);
}

unittest {
	Diagnostic[] diagnostics;
	Lexer lex = new Lexer(q"(--[[ hello
world ]] ident0__)", diagnostics);

	const Tuple!(bool, Token) t = lex.consume(TokenType.Identifier);
	assert(t[0] == true);
	assert(t[1].type == TokenType.Identifier);
	assert(t[1].value == "ident0__");

	assert(diagnostics.length == 0);
}

unittest {
	Diagnostic[] diagnostics;
	Lexer lex = new Lexer(q"(--[[ hello
world ]] ident0__)", diagnostics);

	const Tuple!(bool, Token) t = lex.consume(TokenType.Identifier, "ident0__");
	assert(t[0] == true);
	assert(t[1].type == TokenType.Identifier);
	assert(t[1].value == "ident0__");

	assert(diagnostics.length == 0);
}

unittest {
	Diagnostic[] diagnostics;
	Lexer lex = new Lexer(q"(--[[ hello
world ]] ident0__)", diagnostics);

	const Tuple!(bool, Token) t = lex.consume(TokenType.Identifier, "asd");
	assert(t[0] == false);
	assert(t[1].type == TokenType.Identifier);
	assert(t[1].value == "ident0__");

	assert(diagnostics.length == 1);
}

unittest {
	Diagnostic[] diagnostics;
	Lexer lex = new Lexer(q"(--[[ hello
world ]] 2. ident0__)", diagnostics);

	const Tuple!(bool, Token) t = lex.consume(TokenType.Identifier);
	assert(t[0] == false);
	assert(t[1].type == TokenType.Number);
	assert(t[1].value == "2.");

	assert(lex.peek().type == TokenType.Identifier);

	assert(diagnostics.length == 1);
}

unittest {
	Diagnostic[] diagnostics;
	Lexer lex = new Lexer(q"(--[[ hello
world ]] 2. ident0__)", diagnostics);

	const Tuple!(bool, Token) t = lex.consume!(No.toConsume)(TokenType.Identifier);
	assert(t[0] == false);
	assert(t[1].type == TokenType.Number);
	assert(t[1].value == "2.");

	assert(lex.peek().type == TokenType.Number);

	assert(diagnostics.length == 1);
}

unittest {
	Diagnostic[] diagnostics;
	const Token a = new Lexer(q"('alo\n123"')", diagnostics).nextInternal();
	const Token b = new Lexer(q"("alo\n123\"")", diagnostics).nextInternal();
	const Token c = new Lexer(q"('\97lo\10\04923"')", diagnostics).nextInternal();
	const Token d = new Lexer(q"([[alo
123"]])", diagnostics).nextInternal();
	const Token e = new Lexer(q"([==[
alo
123"]==])", diagnostics).nextInternal();

	const Token f = new Lexer(q"([==[]==])", diagnostics).nextInternal();
	const Token g = new Lexer(q"([==[]]]==])", diagnostics).nextInternal();
	const Token h = new Lexer(q"([=[[==[]==]]=])", diagnostics).nextInternal();

	assert(a.type == TokenType.String);
	assert(b.type == TokenType.String);
	assert(c.type == TokenType.String);
	assert(d.type == TokenType.String);
	assert(e.type == TokenType.String);
	assert(f.type == TokenType.String);
	assert(g.type == TokenType.String);
	assert(h.type == TokenType.String);

	assert(a.value == "alo\n123\"");
	assert(a.value == b.value);
	assert(a.value == c.value);
	assert(a.value == d.value);
	assert(a.value == e.value);

	assert(f.value == "");
	assert(g.value == "]]");
	assert(h.value == "[==[]==]");

	assert(diagnostics.length == 0);

	Diagnostic[] da;

	new Lexer(q"("x\")", da).nextInternal();
	new Lexer(q"([==[x]=])", da).nextInternal();
	new Lexer(q"([==[x]=]])", da).nextInternal();

	assert(da.length == 3);

	assert(da[0].quickfix.length == 1);
	assert(da[1].quickfix.length == 2);
	assert(da[2].quickfix.length == 2);

	assert(da[0].quickfix[0].apply(q"("x\")") == q"("x\"")");

	assert(da[1].quickfix[0].apply(q"([==[x]=])") == q"([==[x]=]]==])");
	assert(da[1].quickfix[1].apply(q"([==[x]=])") == q"([==[x]==])");

	assert(da[2].quickfix[0].apply(q"([==[x]=]])") == q"([==[x]=]]]==])");
	assert(da[2].quickfix[1].apply(q"([==[x]=]])") == q"([==[x]=]==])");
}

unittest {
	Diagnostic[] diagnostics;
	Lexer l = new Lexer(" \r\r\n    \thi", diagnostics);
	assert(l.index == 0);
	l.skipWhitespace();
	assert(l.index == 9);
	assert(l.peekChar() == 'h');
	assert(l.nextChar() == 'h');
	assert(l.nextChar() == 'i');
	assert(l.nextChar() == 0);

	assert(diagnostics.length == 0);
}

unittest {
	Diagnostic[] diagnostics;
	Lexer l = new Lexer(" \r\r\n   \t", diagnostics);
	assert(l.index == 0);
	l.skipWhitespace();
	assert(l.index == 8);
	assert(l.peekChar() == 0);

	assert(diagnostics.length == 0);
}

unittest {
	Diagnostic[] diagnostics;
	Lexer l = new Lexer(" hi and bye", diagnostics);

	const Token hi = l.nextInternal();
	const Token and = l.nextInternal();
	const Token bye = l.nextInternal();

	assert(hi.type == TokenType.Identifier);
	assert(and.type == TokenType.Keyword);
	assert(bye.type == TokenType.Identifier);

	assert(hi.value == "hi");
	assert(and.value == "and");
	assert(bye.value == "bye");

	assert(hi.index == 1);
	assert(and.index == 4);
	assert(bye.index == 8);

	assert(diagnostics.length == 0);
}

unittest {
	Diagnostic[] diagnostics;
	Lexer l = new Lexer(" hi And bye", diagnostics);

	const Token hi = l.nextInternal();
	const Token and = l.nextInternal();
	const Token bye = l.nextInternal();

	assert(hi.type == TokenType.Identifier);
	assert(and.type == TokenType.Identifier);
	assert(bye.type == TokenType.Identifier);

	assert(hi.value == "hi");
	assert(and.value == "And");
	assert(bye.value == "bye");

	assert(hi.index == 1);
	assert(and.index == 4);
	assert(bye.index == 8);

	assert(diagnostics.length == 0);
}