module zua.pattern.parser;
import zua.pattern;
import std.bitmanip;

/** A pattern parser */
final class Parser {
	private string pattern;
	private size_t index;

	/** Create a new Parser */
	this(string pattern) {
		this.pattern = pattern;
	}

private:

	bool eof() {
		return index >= pattern.length;
	}

	char nextChar() {
		return pattern[index++];
	}

	char peekChar() {
		return pattern[index];
	}

	CharClass nextCharClass(bool sqBracket = true) {
		char c = nextChar();
		if (c == '%') {
			if (eof) {
				throw new PatternError("malformed pattern (ends with '%')");
			}
			char nc = nextChar();
			BitArray set;
			set.length = 256;
			switch (nc) {
			case 'a':
				set['a' .. 'z' + 1] = true;
				set['A' .. 'Z' + 1] = true;
				break;
			case 'c':
				set[0 .. 0x1f + 1] = true;
				set[0x7f] = true;
				break;
			case 'd':
				set['0' .. '9' + 1] = true;
				break;
			default:
				LiteralChar res = new LiteralChar;
				res.value = nc;
				return res;
			}
			SetClass res = new SetClass;
			res.set = set;
			return res;
		}
		else if (c == '.') {
			BitArray set;
			set.length = 256;
			set[] = true;
			SetClass res = new SetClass;
			res.set = set;
			return res;
		}
		else if (c == '[' && sqBracket) {
			if (eof) {
				throw new PatternError("malformed pattern (missing ']')");
			}
			char fc = peekChar();
			bool complement = false;
			if (fc == '^') {
				nextChar();
				complement = true;
			}
			BitArray set;
			size_t save = index;
			CharClass first = nextCharClass(false);
			if (save + 1 == index) {
				
			}
			if (complement) set.flip();
			SetClass res = new SetClass;
			res.set = set;
			return res;
		}
		else {
			LiteralChar res = new LiteralChar;
			res.value = c;
			return res;
		}
	}

}