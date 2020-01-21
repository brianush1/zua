module zua.vm.std.bit32;
import zua.vm.engine;
import zua.vm.reflection;
import std.typecons;

private uint lbit32_arshift(uint x, long disp) {
	if (disp < 0) return x << -disp;
	return cast(uint)(cast(int)x >> disp);
}

private uint lbit32_band(uint[] op...) {
	uint res = 0xFFFFFFFF;
	foreach (i; op) {
		res &= i;
	}
	return res;
}

private uint lbit32_bnot(uint x) {
	return ~x;
}

private uint lbit32_bor(uint[] op...) {
	uint res = 0;
	foreach (i; op) {
		res |= i;
	}
	return res;
}

private bool lbit32_btest(uint[] op...) {
	uint res = 0xFFFFFFFF;
	foreach (i; op) {
		res &= i;
	}
	return res != 0;
}

private uint lbit32_bxor(uint[] op...) {
	uint res = 0;
	foreach (i; op) {
		res ^= i;
	}
	return res;
}

private uint lbit32_extract(uint x, long start, long width = 1) {
	if (start < 0) {
		throw new Exception("bad argument #2 to 'extract' (field cannot be negative)");
	}
	else if (width < 1) {
		throw new Exception("bad argument #3 to 'extract' (width must be positive)");
	}
	else if (start + width > 32) {
		throw new Exception("trying to access non-existent bits");
	}
	else if (width == 32) {
		return x;
	}

	return (x >> start) & (1 << width) - 1;
}

private uint lbit32_replace(uint x, uint v, long start, long width = 1) {
	if (start < 0) {
		throw new Exception("bad argument #2 to 'replace' (field cannot be negative)");
	}
	else if (width < 1) {
		throw new Exception("bad argument #3 to 'replace' (width must be positive)");
	}
	else if (start + width > 32) {
		throw new Exception("trying to access non-existent bits");
	}
	else if (width == 32) {
		return v;
	}

	uint zeroed = x & ~((1 << width) - 1 << start);
	return zeroed | ((v & (1 << width) - 1) << start);
}

private uint lbit32_lrotate(uint x, long disp) {
	disp %= 32;
	if (disp < 0) disp += 32;
	return (x << disp) | (x >> (32 - disp));
}

private uint lbit32_lshift(uint x, long disp) {
	if (disp >= 32 || disp <= -32) return 0;
	if (disp < 0) return x >> -disp;
	return x << disp;
}

private uint lbit32_rrotate(uint x, long disp) {
	disp %= 32;
	if (disp < 0) disp += 32;
	return (x >> disp) | (x << (32 - disp));
}

private uint lbit32_rshift(uint x, long disp) {
	if (disp >= 32 || disp <= -32) return 0;
	if (disp < 0) return x << -disp;
	return x >> disp;
}

/** Get bit32 library */
Value bit32lib() {
	TableValue res = new TableValue;
	res.set(Value("arshift"), exposeFunction!(lbit32_arshift, "arshift"));
	res.set(Value("band"), exposeFunction!(lbit32_band, "band"));
	res.set(Value("bnot"), exposeFunction!(lbit32_bnot, "bnot"));
	res.set(Value("bor"), exposeFunction!(lbit32_bor, "bor"));
	res.set(Value("btest"), exposeFunction!(lbit32_btest, "btest"));
	res.set(Value("bxor"), exposeFunction!(lbit32_bxor, "bxor"));
	res.set(Value("extract"), exposeFunction!(lbit32_extract, "extract"));
	res.set(Value("replace"), exposeFunction!(lbit32_replace, "replace"));
	res.set(Value("lrotate"), exposeFunction!(lbit32_lrotate, "lrotate"));
	res.set(Value("lshift"), exposeFunction!(lbit32_lshift, "lshift"));
	res.set(Value("rrotate"), exposeFunction!(lbit32_rrotate, "rrotate"));
	res.set(Value("rshift"), exposeFunction!(lbit32_rshift, "rshift"));
	return Value(res);
}