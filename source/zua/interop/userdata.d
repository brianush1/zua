module zua.interop.userdata;
import zua.interop.table;
import zua.interop;
import zua.vm.engine;
import std.typecons;
import std.uuid;

/** Wrapper around Lua userdata */
struct Userdata {

	/** The internal data for this userdata; should seldom be accessed by user code */
	Value _internalUserdata;

	package this(Value userdata) {
		_internalUserdata = userdata;
	}

	@disable this();

	/** Create a new userdata */
	static Userdata create(void* ptr, Nullable!Table metatable = Nullable!Table()) {
		auto res = Userdata(Value(new UserdataValue(ptr, null)));
		if (!metatable.isNull) {
			res.metatable = metatable;
		}
		return res;
	}

	/** Get the metatable */
	Nullable!Table metatable() {
		if (_internalUserdata.metatable) {
			return Nullable!Table(Table(Value(_internalUserdata.metatable)));
		}
		else {
			return Nullable!Table();
		}
	}

	/** Set the metatable */
	void metatable(Nullable!Table newMetatable) {
		if (newMetatable.isNull) {
			_internalUserdata.userdata.metatable = null;
		}
		else {
			_internalUserdata.userdata.metatable = newMetatable.get._internalTable.table;
		}
	}

	/** Set the metatable */
	pragma(inline) void metatable(Table newMetatable) {
		metatable = newMetatable.Nullable!Table;
	}

	/** Set the metatable */
	pragma(inline) void metatable(typeof(null)) {
		metatable = Nullable!Table();
	}

	/** Get the internal data pointer */
	void* data() {
		return _internalUserdata.userdata.data;
	}

	/** Set the internal data pointer */
	void data(void* value) {
		_internalUserdata.userdata.data = value;
	}

	/** Get the owner UUID of this userdata */
	UUID owner() {
		return _internalUserdata.userdata.ownerId;
	}

	/** Set the owner UUID of this userdata */
	void owner(UUID value) {
		_internalUserdata.userdata.ownerId = value;
	}

}