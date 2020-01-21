module zua.vm.std.coroutine;
import zua.vm.engine;
import zua.vm.reflection;
import std.typecons;
import std.random;
import core.thread;

private Value[] resumeParams;
private Value[] resumeResult;
private ThreadValue currentThread;

/** Represents a coroutine context */
struct Context {
	private Value[] resumeParams;
	private Value[] resumeResult;
	private ThreadValue currentThread;
}

/** Coroutine stack size */
const size_t STACKSIZE = 1024 * 1024 * 8;

/** Run a function in a toplevel thread */
Value[] runToplevel(TableValue env, FunctionValue func, Value[] args) {
	Context ctx = {
		resumeParams: resumeParams,
		resumeResult: resumeResult,
		currentThread: currentThread
	};

	ThreadValue co = new ThreadValue;
	co.env = env;
	co.status = CoroutineStatus.Suspended;
	co.fiber = new Fiber(delegate() {
		resumeResult = func.rawcall(resumeParams);
		co.status = CoroutineStatus.Dead;
	}, STACKSIZE);

	resumeParams = [];
	resumeResult = [];
	currentThread = co;

	scope(exit) {
		resumeParams = ctx.resumeParams;
		resumeResult = ctx.resumeResult;
		currentThread = ctx.currentThread;
	}

	co.status = CoroutineStatus.Running;
	resumeParams = args;
	Throwable err = co.fiber.call!(Fiber.Rethrow.no);
	if (co.status != CoroutineStatus.Dead) {
		co.status = CoroutineStatus.Suspended;
	}
	if (err !is null) {
		co.status = CoroutineStatus.Dead;
		throw err;
	}

	return resumeResult;
}

TableValue* getGlobalEnvPtr() {
	if (currentThread is null) {
		throw new Exception("internal error (escaped toplevel thread)");
	}
	else {
		return &currentThread.env;
	}
}

private ThreadValue lcoroutine_create(FunctionValue value) {
	FunctionValue caller = callstack[$ - 1].func;

	TableValue env = caller.env;
	if (env is null) env = *getGlobalEnvPtr;

	ThreadValue res = new ThreadValue;
	res.env = env;
	res.status = CoroutineStatus.Suspended;
	res.fiber = new Fiber(delegate() {
		resumeResult = value.rawcall(resumeParams);
		res.status = CoroutineStatus.Dead;
	}, STACKSIZE);

	return res;
}

private Value[] lcoroutine_resume(ThreadValue co, Value[] params...) {
	if (co.status == CoroutineStatus.Dead) {
		return [Value(false), Value("cannot resume dead coroutine")];
	}
	else if (co.status == CoroutineStatus.Running) {
		return [Value(false), Value("cannot resume running coroutine")];
	}
	else if (co.status == CoroutineStatus.Normal) {
		return [Value(false), Value("cannot resume normal coroutine")];
	}

	auto save = currentThread;
	if (currentThread) currentThread.status = CoroutineStatus.Normal;
	currentThread = co;
	currentThread.status = CoroutineStatus.Running;
	resumeParams = params;
	Throwable err = co.fiber.call!(Fiber.Rethrow.no);
	if (currentThread.status != CoroutineStatus.Dead) {
		currentThread.status = CoroutineStatus.Suspended;
	}
	currentThread = save;
	if (currentThread) currentThread.status = CoroutineStatus.Running;
	if (err !is null) {
		co.status = CoroutineStatus.Dead;
		if (auto e = cast(LuaError)err) {
			return [Value(false), e.data];
		}
		else if (auto e = cast(Exception)err) {
			return [Value(false), Value("an internal error occurred")];
		}
		else {
			throw err;
		}
	}
	return [Value(true), Value(resumeResult)];
}

private Value[] lcoroutine_yield(Value[] params...) {
	resumeResult = params;
	Fiber.yield();
	return resumeParams;
}

private ThreadValue lcoroutine_running() {
	return currentThread;
}

private string lcoroutine_status(ThreadValue co) {
	final switch (co.status) {
	case CoroutineStatus.Suspended: return "suspended";
	case CoroutineStatus.Running: return "running";
	case CoroutineStatus.Normal: return "normal";
	case CoroutineStatus.Dead: return "dead";
	}
}

private FunctionValue lcoroutine_wrap(FunctionValue func) {
	ThreadValue co = lcoroutine_create(func);
	FunctionValue res = new FunctionValue;
	res.env = null;
	res.engine = new class Engine {

		override Value[] callf(FunctionValue, Value[] args) {
			Value[] wres = lcoroutine_resume(co, args);
			if (wres[0] == Value(false)) {
				throw new LuaError(wres[1]);
			}
			else {
				return wres[1..$];
			}
		}

	};
	return res;
}

/** Get coroutine library */
Value coroutinelib() {
	TableValue res = new TableValue;
	res.set(Value("create"), exposeFunction!(lcoroutine_create, "create"));
	res.set(Value("resume"), exposeFunction!(lcoroutine_resume, "resume"));
	res.set(Value("running"), exposeFunction!(lcoroutine_running, "running"));
	res.set(Value("status"), exposeFunction!(lcoroutine_status, "status"));
	res.set(Value("wrap"), exposeFunction!(lcoroutine_wrap, "wrap"));
	res.set(Value("yield"), exposeFunction!(lcoroutine_yield, "yield"));
	return Value(res);
}