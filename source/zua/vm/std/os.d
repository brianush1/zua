module zua.vm.std.os;
import zua.vm.engine;
import zua.vm.reflection;
import std.typecons;
import std.variant;
import std.conv;
import core.time;

version(linux) {
	version = ZuaUseCPUTime;
}
version(OpenBSD) {
	version = ZuaUseCPUTime;
}
version(Solaris) {
	version = ZuaUseCPUTime;
}

private double los_clock() {
	version (ZuaUseCPUTime) {
		auto now = MonoTimeImpl!(ClockType.threadCPUTime).currTime;
		return now.ticks / cast(double)now.ticksPerSecond;
	}
	else version(Windows) {
		return 0;
	}
	else {
		auto now = MonoTime.currTime;
		return now.ticks / cast(double)now.ticksPerSecond;
	}
}

private double los_difftime(double t2, double t1) {
	return t2 - t1;
}

/** Get os library */
Value oslib() {
	TableValue res = new TableValue;
	res.set(Value("clock"), exposeFunction!(los_clock, "clock"));
	res.set(Value("difftime"), exposeFunction!(los_difftime, "difftime"));

	return Value(res);
}