module zua.diagnostic;
import zua.parser.lexer;
import std.algorithm.sorting;
import std.array;
import std.typecons;
import std.algorithm;

/** Determines what type of diagnostic it represents */
enum DiagnosticType {
	Error,
	Warning,
	Info
}

/** Describes how a quickfix should be performed on a range */
struct QuickfixRange {

	/** Describes the range in the *original* document to modify */
	size_t from;
	size_t to; /// ditto

	/** The code to replace the given range with */
	string replaceWith;

	/** Create a new quickfix range */
	this(size_t from, size_t to, string replaceWith) {
		this.from = from;
		this.to = to;
		this.replaceWith = replaceWith;
	}

	/** Create a new quickfix range */
	this(Token token, string replaceWith) {
		this.from = token.index;
		this.to = token.index + token.rawValue.length;
		this.replaceWith = replaceWith;
	}

	/** Create a new quickfix range */
	this(Token from, Token to, string replaceWith) {
		this.from = from.index;
		this.to = to.index + to.rawValue.length;
		this.replaceWith = replaceWith;
	}

	int opCmp(ref const QuickfixRange other) const {
		if (from < other.from) {
			return -1;
		}
		else if (from > other.from) {
			return 1;
		}
		else {
			return 0;
		}
	}

	bool opEquals(ref const QuickfixRange other) const {
		return from == other.from;
	}

	ulong toHash() const {
		return typeid(from).getHash(&from);
	}

}

/** Describes a quickfix option */
struct Quickfix {

	/** A message describing the fix */
	string message;

	/** A list of quickfix range operations to apply. Ranges may not overlap */
	const(QuickfixRange)[] ranges;

}

/** Stores a diagnostic message */
struct Diagnostic {

	/** Determines what type of diagnostic it represents */
	DiagnosticType type;

	/** The diagonstic message */
	string message;

	/** The ranges of indices that this diagnostic message partains to */
	size_t[2][] ranges;

	/** Provides a list of possible quickfixes */
	const(Quickfix)[] quickfix;

	/** Create a new diagnostic message */
	this(DiagnosticType type, string message) {
		this.type = type;
		this.message = message;
	}

	/** Add a range of indices to this diagnostic message */
	void add(size_t from, size_t to) {
		ranges ~= [from, to];
	}

	/** Add a single index to this diagnostic message */
	void add(size_t at) {
		ranges ~= [at, at];
	}

	/** Add a single token to this diagnostic message */
	void add(Token token) {
		add(token.index, token.index + token.rawValue.length);
	}

	/** Add a range of tokens to this diagnostic message, inclusive */
	void add(Token from, Token to) {
		add(from.index, to.index + to.rawValue.length);
	}

}

/** Return the modified source code after the application of a quickfix */
string apply(Quickfix fix, string source) {
	QuickfixRange[] ranges = fix.ranges.dup;
	sort!"a > b"(ranges);

	foreach (range; ranges) {
		source = source[0..range.from] ~ range.replaceWith ~ source[range.to..$];
	}

	return source;
}

/** Return the zero-indexed line number and local index from absolute index */
auto decodeIndex(size_t index, string source) { // TODO: make this efficient
	Tuple!(size_t, "line", size_t, "index") result;

	index = min(source.length, index);

	size_t currIndex = 0;

	const lines = source.split('\n');
	foreach (lineNum; 0..lines.length) {
		const line = lines[lineNum];
		if (index >= currIndex && index <= currIndex + line.length) {
			result.line = lineNum;
			result.index = index - currIndex;
			break;
		}

		currIndex += line.length + 1;
	}

	return result;
}

unittest {
	const string source = "ABCDEF";

	const Quickfix fix = {
		message: "",
		ranges: [QuickfixRange(1, 2, ".."), QuickfixRange(4, 5, "::")]
	};

	assert(fix.apply(source) == "A..CD::F");
}