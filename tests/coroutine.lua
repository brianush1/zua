local MSG = "[ ] FAILED coroutine tests"

-- Toplevel coroutines are available in Zua:
-- [INCONSISTENT]
assert(coroutine.running() ~= nil, MSG)

coroutine.wrap(function()
	local a, b = coroutine.resume(coroutine.running())
	assert(a == false and b == "cannot resume running coroutine", MSG)
end)()

local top = coroutine.running()

coroutine.wrap(function()
	local a, b = coroutine.resume(top)
	assert(a == false and b == "cannot resume normal coroutine", MSG)
end)()

local t
local co
co = coroutine.create(function(x, y)
	assert(x == 7 and y == 9)
	t = 2
	local a = coroutine.yield(3)
	assert(a == 7)
	
	assert(coroutine.status(co) == "running")
	assert(coroutine.status(top) == "normal")
	return 4
end)

assert(coroutine.status(co) == "suspended", MSG)
local a, b = coroutine.resume(co, 7, 9)
assert(a, MSG)
assert(b == 3, MSG)
assert(coroutine.status(co) == "suspended")
local a, b = coroutine.resume(co, 7)
assert(a, MSG)
assert(b == 4, MSG)
assert(coroutine.status(co) == "dead")

assert(not pcall(function()
	coroutine.wrap(function()
		assert(false)
	end)()
end), MSG)

assert(pcall(function()
	coroutine.resume(coroutine.create(function()
		assert(false)
	end))
end), MSG)

print("[X] passed coroutine tests")