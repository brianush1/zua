module zua.vm.std.string;
import zua.vm.engine;
import zua.vm.reflection;
import std.algorithm.mutation;
import std.typecons;
import std.variant;
import std.conv;

private ubyte[] lstring_byte(string s, Nullable!long ni, Nullable!long nj) {
	long i = ni.isNull ? 1 : ni.get;
	long j = nj.isNull ? i : nj.get;

	if (i < 0) i += s.length; else i--;
	if (j < 0) j += s.length; else j--;

	if (i > j) return [];

	if (i < 0) i = 0;
	if (j > s.length) j = s.length - 1;

	return cast(ubyte[]) s[i .. j + 1];
}

private string lstring_char(long[] args...) {
	string str;

	foreach (i; 0 .. args.length) {
		long v = args[i];
		if (v < 0 || v > 255) {
			throw new Exception("bad argument #" ~ (i + 1).to!string ~ " to 'char' (invalid value)");
		}
		str ~= cast(char) v;
	}

	return str;
}

private size_t lstring_len(string s) {
	return s.length;
}

private string lstring_lower(string s) {
	string res;
	res.reserve(s.length);
	foreach (c; s) {
		if (c >= 'A' && c <= 'Z') res ~= c + ('a' - 'A');
		else res ~= c;
	}
	return res;
}

private string lstring_rep(string s, long n) {
	if (n < 1) return "";
	string res;
	res.reserve(s.length * n);
	foreach (i; 0 .. n) {
		res ~= s;
	}
	return res;
}

private string lstring_reverse(string s) {
	string res;
	res.reserve(s.length);
	foreach_reverse (c; s) {
		res ~= c;
	}
	return res;
}

private string lstring_sub(string s, Nullable!long ni, Nullable!long nj) {
	long i = ni.isNull ? 1 : ni.get;
	long j = nj.isNull ? i : nj.get;

	if (i < 0) i += s.length; else i--;
	if (j < 0) j += s.length; else j--;

	if (i > j) return [];

	if (i < 0) i = 0;
	if (j > s.length) j = s.length - 1;

	return s[i .. j + 1];
}

private string lstring_upper(string s) {
	string res;
	res.reserve(s.length);
	foreach (c; s) {
		if (c >= 'a' && c <= 'z') res ~= c - ('a' - 'A');
		else res ~= c;
	}
	return res;
}

/** Get string library */
Value stringlib() {
	TableValue res = new TableValue;
	res.set(Value("byte"), exposeFunction!(lstring_byte, "byte"));
	res.set(Value("char"), exposeFunction!(lstring_char, "char"));
	res.set(Value("len"), exposeFunction!(lstring_len, "len"));
	res.set(Value("lower"), exposeFunction!(lstring_lower, "lower"));
	res.set(Value("rep"), exposeFunction!(lstring_rep, "rep"));
	res.set(Value("reverse"), exposeFunction!(lstring_reverse, "reverse"));
	res.set(Value("sub"), exposeFunction!(lstring_sub, "sub"));
	res.set(Value("upper"), exposeFunction!(lstring_upper, "upper"));
	return Value(res);
}