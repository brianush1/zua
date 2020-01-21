module zua.vm.std.math;
import zua.vm.engine;
import zua.vm.reflection;
import std.typecons;
import std.random;
import std.math;

private double lmath_abs(double x) {
	if (x < 0) return -x;
	else return x;
}

private double lmath_acos(double x) {
	return acos(x);
}

private double lmath_asin(double x) {
	return asin(x);
}

private double lmath_atan(double x) {
	return atan(x);
}

private double lmath_atan2(double y, double x) {
	return atan2(y, x);
}

private double lmath_ceil(double x) {
	return ceil(x);
}

private double lmath_cos(double x) {
	return cos(x);
}

private double lmath_cosh(double x) {
	return cosh(x);
}

private double lmath_deg(double x) {
	return x * 180 / PI;
}

private double lmath_exp(double x) {
	return exp(x);
}

private double lmath_floor(double x) {
	return floor(x);
}

private double lmath_fmod(double x, double y) {
	return fmod(x, y);
}

private double lmath_mod(double x, double y) {
	return fmod(x, y);
}

private Tuple!(double, int) lmath_frexp(double x) {
	int exp;
	double res = frexp(x, exp);
	return tuple(res, exp);
}

private double lmath_ldexp(double m, int e) {
	return m * pow(2.0, e);
}

private double lmath_log(double x) {
	return log(x);
}

private double lmath_log10(double x) {
	return log10(x);
}

private double lmath_max(double x, double y) {
	if (x > y) return x;
	else return y;
}

private double lmath_min(double x, double y) {
	if (x < y) return x;
	else return y;
}

private Tuple!(double, double) lmath_modf(double x) {
	if (isNaN(x)) return tuple(x, x);
	long i = cast(long)x;
	return tuple(cast(double)i, x - i);
}

private double lmath_pow(double x, double y) {
	return pow(x, y);
}

private double lmath_rad(double x) {
	return x * PI / 180;
}

private Random rand;

static this() {
	rand = Random(unpredictableSeed);
}

private double lmath_random(Nullable!long m, Nullable!long n) {
	if (m.isNull && n.isNull) {
		return uniform!"[)"(0.0, 1.0, rand);
	}
	else if (m.isNull && !n.isNull) {
		throw new Exception("bad argument #1 to 'random' (number expected, got nil)");
	}
	else if (!m.isNull && n.isNull) {
		return uniform!"[]"(1L, m.get, rand);
	}
	else if (!m.isNull && !n.isNull) {
		return uniform!"[]"(m.get, n.get, rand);
	}
	else assert(0);
}

private void lmath_randomseed(long x) {
	rand.seed(cast(uint)x);
}

private double lmath_sin(double x) {
	return sin(x);
}

private double lmath_sinh(double x) {
	return sinh(x);
}

private double lmath_sqrt(double x) {
	return sqrt(x);
}

private double lmath_tan(double x) {
	return tan(x);
}

private double lmath_tanh(double x) {
	return tanh(x);
}

/** Get math library */
Value mathlib() {
	TableValue res = new TableValue;
	res.set(Value("abs"), exposeFunction!(lmath_abs, "abs"));
	res.set(Value("acos"), exposeFunction!(lmath_acos, "acos"));
	res.set(Value("asin"), exposeFunction!(lmath_asin, "asin"));
	res.set(Value("atan"), exposeFunction!(lmath_atan, "atan"));
	res.set(Value("atan2"), exposeFunction!(lmath_atan2, "atan2"));
	res.set(Value("ceil"), exposeFunction!(lmath_ceil, "ceil"));
	res.set(Value("cos"), exposeFunction!(lmath_cos, "cos"));
	res.set(Value("cosh"), exposeFunction!(lmath_cosh, "cosh"));
	res.set(Value("deg"), exposeFunction!(lmath_deg, "deg"));
	res.set(Value("exp"), exposeFunction!(lmath_exp, "exp"));
	res.set(Value("floor"), exposeFunction!(lmath_floor, "floor"));
	res.set(Value("fmod"), exposeFunction!(lmath_fmod, "fmod"));
	res.set(Value("mod"), exposeFunction!(lmath_mod, "mod"));
	res.set(Value("frexp"), exposeFunction!(lmath_frexp, "frexp"));
	res.set(Value("huge"), Value(double.infinity));
	res.set(Value("ldexp"), exposeFunction!(lmath_ldexp, "ldexp"));
	res.set(Value("log"), exposeFunction!(lmath_log, "log"));
	res.set(Value("log10"), exposeFunction!(lmath_log10, "log10"));
	res.set(Value("max"), exposeFunction!(lmath_max, "max"));
	res.set(Value("min"), exposeFunction!(lmath_min, "min"));
	res.set(Value("modf"), exposeFunction!(lmath_modf, "modf"));
	res.set(Value("pi"), Value(PI));
	res.set(Value("pow"), exposeFunction!(lmath_pow, "pow"));
	res.set(Value("rad"), exposeFunction!(lmath_rad, "rad"));
	res.set(Value("random"), exposeFunction!(lmath_random, "random"));
	res.set(Value("randomseed"), exposeFunction!(lmath_randomseed, "randomseed"));
	res.set(Value("sin"), exposeFunction!(lmath_sin, "sin"));
	res.set(Value("sinh"), exposeFunction!(lmath_sinh, "sinh"));
	res.set(Value("sqrt"), exposeFunction!(lmath_sqrt, "sqrt"));
	res.set(Value("tan"), exposeFunction!(lmath_tan, "tan"));
	res.set(Value("tanh"), exposeFunction!(lmath_tanh, "tanh"));
	return Value(res);
}