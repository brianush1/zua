module zua.vm.std.table;
import zua.vm.engine;
import zua.vm.reflection;
import std.algorithm.mutation;
import std.typecons;
import std.variant;
import std.conv;

private string ltable_concat(TableValue table, Nullable!string nsep, Nullable!long ni, Nullable!long nj) {
	string sep = nsep.isNull ? "" : nsep.get;
	long i = ni.isNull ? 1 : ni.get;
	long j = nj.isNull ? cast(long) table.length.num : nj.get;

	string res;
	foreach (at; i .. j + 1) {
		if (at > i) res ~= sep;
		Value v = table.get(Value(at));
		if (v.type != ValueType.String && v.type != ValueType.Number) {
			throw new Exception("invalid value (" ~ v.typeStr ~ ") at index " ~ at.to!string ~ " in table for 'concat'");
		}
		res ~= v.toString;
	}
	return res;
}

private void ltable_insert(TableValue table, Algebraic!(double, Value) mpos, Nullable!Value value) {
	if (value.isNull) {
		if (auto n = mpos.peek!double) {
			table.rawset(Value(table.length.num + 1), Value(*n));
		}
		else {
			table.rawset(Value(table.length.num + 1), mpos.get!Value);
		}
	}
	else {
		if (mpos.peek!double == null) {
			throw new Exception("bad argument #2 to 'insert' (number expected, got " ~ mpos.get!Value.typeStr ~ ")");
		}
		double pos = cast(double)cast(long)mpos.get!double;
		if (table.rawhas(Value(pos))) {
			Value prev = *table.rawget(Value(pos));
			double i = pos + 1;
			for (; table.rawhas(Value(i)); ++i) {
				Value nprev = *table.rawget(Value(i));
				table.rawset(Value(i), prev);
				prev = nprev;
			}
			table.rawset(Value(i), prev);
		}
		table.rawset(Value(pos), value.get);
	}
}

private double ltable_maxn(TableValue table) {
	double max = 0;

	for (size_t i = table.array.length; i > 0; --i) {
		if (table.rawhas(Value(i))) {
			max = i;
			break;
		}
	}

	foreach (Tuple!(Value, Value) pair; table.hash.iterator) {
		if (pair[0].type == ValueType.Number) {
			const double n = pair[0].num;
			if (n > max) max = n;
		}
	}

	return max;
}

private Value[] ltable_remove(TableValue table, Nullable!long mpos) {
	if (mpos.isNull) {
		Value len = table.length;
		if (len.num == 0) return [];
		Value res = *table.rawget(len);
		table.rawset(len, Value());
		return [res];
	}
	else {
		double pos = cast(double)mpos.get;
		if (!table.rawhas(Value(pos))) return [];
		Value res = *table.rawget(Value(pos));
		double i = pos;
		for (; table.rawhas(Value(i + 1)); ++i) {
			table.rawset(Value(i), *table.rawget(Value(i + 1)));
		}
		table.rawset(Value(i), Value());
		return [res];
	}
}

private bool lt(Nullable!FunctionValue compare, Value a, Value b) {
	if (compare.isNull) {
		return a.lessThan(b);
	}
	else {
		Value[] res = compare.get.ccall([a, b]);
		if (res.length == 0) return false;
		else return res[0].toBool;
	}
}

private pragma(inline) bool le(Nullable!FunctionValue compare, Value a, Value b) {
	return !lt(compare, b, a);
	// (a <= b) is !(b < a)
}

private size_t partition(Nullable!FunctionValue cmp, Value[] arr) {
	Value a = arr[0];
	Value b = arr[arr.length / 2];
	Value c = arr[$ - 1];

	Value pivot;

	if ((le(cmp, b, a) && lt(cmp, a, c)) || (le(cmp, c, a) && lt(cmp, a, b))) {
		pivot = a;
		swap(arr[0], arr[$ - 1]);
	}
	else if ((le(cmp, a, b) && lt(cmp, b, c)) || (le(cmp, c, b) && lt(cmp, b, a))) {
		pivot = b;
		swap(arr[arr.length / 2], arr[$ - 1]);
	}
	else pivot = c;

	size_t i = -1;
	foreach (j; 0 .. arr.length - 1) {
		if (lt(cmp, arr[j], pivot)) {
			i++;
			swap(arr[i], arr[j]);
		}
	}
	swap(arr[i + 1], arr[$ - 1]);
	return i + 1;
}

private void sort(Nullable!FunctionValue compare, Value[] arr) {
	size_t index = partition(compare, arr);
	if (index > 1) sort(compare, arr[0 .. index]);
	if (index < arr.length - 1) sort(compare, arr[index + 1 .. $]);
}

private void ltable_sort(TableValue table, Nullable!FunctionValue compare) {
	size_t length = cast(size_t) table.length.num;
	if (length == 0) return;
	Value[] arr;
	arr.length = length;
	foreach (i; 0 .. length) {
		Value* v = table.rawget(Value(i + 1));
		if (v != null) arr[i] = *v;
	}
	sort(compare, arr);
	foreach (i; 0 .. length) {
		table.rawset(Value(i + 1), arr[i]);
	}
}

private void ltable_foreachi(TableValue table, FunctionValue func) {
	for (double i = 1;; ++i) {
		if (!table.rawhas(Value(i))) break;
		func.ccall([Value(i), *table.rawget(Value(i))]);
	}
}

private void ltable_foreach(TableValue table, FunctionValue func) {
	foreach (i; 0 .. table.array.length) {
		Value v = table.array[i];
		if (!v.isNil) func.ccall([Value(i + 1), v]);
	}
	foreach (Tuple!(Value, Value) pair; table.hash.iterator) {
		if (!pair[1].isNil) func.ccall([pair[0], pair[1]]);
	}
}

private Value ltable_getn(TableValue table) {
	return table.length;
}

private void ltable_setn(TableValue) {
	throw new Exception("'setn' is obsolete");
}

/** Get table library */
Value tablelib() {
	TableValue res = new TableValue;
	res.set(Value("concat"), exposeFunction!(ltable_concat, "concat"));
	res.set(Value("insert"), exposeFunction!(ltable_insert, "insert"));
	res.set(Value("maxn"), exposeFunction!(ltable_maxn, "maxn"));
	res.set(Value("remove"), exposeFunction!(ltable_remove, "remove"));
	res.set(Value("sort"), exposeFunction!(ltable_sort, "sort"));

	res.set(Value("foreach"), exposeFunction!(ltable_foreach, "foreach"));
	res.set(Value("foreachi"), exposeFunction!(ltable_foreachi, "foreachi"));
	res.set(Value("getn"), exposeFunction!(ltable_getn, "getn"));
	res.set(Value("setn"), exposeFunction!(ltable_setn, "setn"));
	return Value(res);
}