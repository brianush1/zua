module zua.interop.table;
import zua.interop;
import zua.vm.engine;
import std.typecons;

/** Wrapper around Lua tables */
struct Table {

	/** The internal data for this Table; should seldom be accessed by user code */
	Value _internalTable;

	package this(Value table) {
		_internalTable = table;
	}

	@disable this();

	/** Create a new, empty Table */
	static Table create() {
		return Table(Value(new TableValue));
	}

	/** Get the metatable */
	Nullable!Table metatable() {
		if (_internalTable.metatable) {
			return Nullable!Table(Table(Value(_internalTable.metatable)));
		}
		else {
			return Nullable!Table();
		}
	}

	/** Set the metatable */
	void metatable(Nullable!Table newMetatable) {
		if (newMetatable.isNull) {
			_internalTable.table.metatable = null;
		}
		else {
			_internalTable.table.metatable = newMetatable.get._internalTable.table;
		}
	}

	/** Get the length of this table */
	size_t length() {
		return cast(size_t)_internalTable.table.length.num;
	}

	/** Invokes the metatable seamlessly when performing unary negation */
	DConsumable opUnary(string s)() if (s == "-") {
		const Nullable!(Value[]) attempt = _internalTable.metacall("__unm", [v]);
		if (attempt.isNull) {
			throw new LuaError(Value("attempt to perform arithmetic on a table value"));
		}
		Value[] res = cast(Value[]) attempt.get;
		if (res.length == 0) {
			return makeConsumable(Value());
		}
		else {
			return makeConsumable(res[0]);
		}
	}

	/** Seamless index of a table */
	DConsumable opIndex(T)(T value) if (isConvertible!T) {
		return makeConsumable(_internalTable.table.get(DConsumable(value).makeInternalValue));
	}

	/** Seamless assign to a table */
	void opIndexAssign(T, K)(T value, K key) if (isConvertible!T && isConvertible!K) {
		DConsumable v;
		static if (__traits(compiles, v.__ctor!(T, key)(value))) {
			v.__ctor!(T, key)(value);
		}
		else {
			v = DConsumable(value);
		}
		_internalTable.table.set(DConsumable(key).makeInternalValue, v.makeInternalValue);
	}

	/** Seamless assign to a table, passing a preferred name for the given value */
	void expose(string key, T)(T value) if (isConvertible!T) {
		DConsumable v;
		v.__ctor!(T, key)(value);
		_internalTable.table.set(DConsumable(key).makeInternalValue, v.makeInternalValue);
	}

}