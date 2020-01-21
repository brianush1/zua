local MSG = "[ ] FAILED global environment tests"

local genv = getfenv(0)

assert(genv == _G, MSG)

local co
co = coroutine.create(function()

	setfenv(1, {})

	genv.assert(genv.getfenv(0) == genv)

	genv.setfenv(0, {})

	genv.assert(genv.getfenv(0) ~= genv) -- genv is thread-local

end)

assert(coroutine.resume(co), MSG)
assert(getfenv(0) == genv, MSG)

print("[X] passed global environment tests")