module zua.pattern;
import std.bitmanip;

/** Denotes an error occurring at any point during the execution of a pattern */
final class PatternError : Exception {
	/** Create a new PatternError */
	this(string msg) {
		super(msg);
	}
}

/** A pattern */
final class Pattern {
	/** Whether or not to anchor this pattern to the start of the subject string */
	bool startAnchor;

	/** Whether or not to anchor this pattern to the end of the subject string */
	bool endAnchor;

	/** The items that comprise this pattern */
	PatternItem[] items;
}

/** An abstract pattern item */
abstract class PatternItem {}

/** A capture */
final class Capture : PatternItem {
	/** The items to match in this capture */
	PatternItem[] items;
}

/** The type of sequence to match*/
enum SequenceType {
	Greedy0, /// *
	Greedy1, /// +
	NonGreedy1, /// -
	Maybe, /// ?
}

/** Matches a sequence */
final class SequenceMatch : PatternItem {
	/** The type of sequence to match */
	SequenceType type;

	/** The character class to match */
	CharClass charClass;
}

/** Matches a pattern that has been previously captured */
final class CaptureMatch : PatternItem {
	/** The 0-based index of the capture to match */
	int index;
}

/** Matches a balanced string */
final class BalancedMatch : PatternItem {
	/** The left character */
	char left;

	/** The right character */
	char right;
}

/** An abstract character class */
abstract class CharClass : PatternItem {}

/** A literal character class */
final class LiteralChar : CharClass {
	/** The character value to match */
	char value;
}

/** Represents a character set */
final class SetClass : CharClass {
	/** Holds the contents of this set class */
	BitArray set;

	/** Create a new SetClass */
	this() {
		set.length = 256;
	}

	/** Create a new SetClass, including the given characters in the set */
	this(string str) {
		this();
		foreach (c; str) {
			set[cast(ubyte)c] = true;
		}
	}
}