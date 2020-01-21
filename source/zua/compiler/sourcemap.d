module zua.compiler.sourcemap;
import std.typecons;

alias SourceIndices = Tuple!(size_t, "start", size_t, "end");

/** An object that maps a bytecode index onto source indices */
final class SourceMap {

	private Tuple!(SourceIndices, size_t)[] data;
	private size_t ip;

	/** Write to source map */
	void write(size_t start, size_t end, size_t repeat) {
		SourceIndices i = tuple(start, end);
		if (data.length > 0 && data[$ - 1][0] == i) {
			data[$ - 1][1] += repeat;
		}
		else {
			data ~= tuple(i, repeat);
		}
		ip += repeat;
	}

	/** Resolve a bytecode index */
	SourceIndices resolve(size_t index) {
		size_t at;
		foreach (v; data) {
			if (index >= at && index < at + v[1])
				return v[0];
			at += v[1];
		}
		return SourceIndices(0, 0);
	}
}