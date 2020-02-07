local MSG = "[ ] FAILED proxy tests"

local a = newproxy(false)
assert(getmetatable(a) == nil, MSG)

local b = newproxy(true)

local mt = getmetatable(b)
assert(mt ~= nil, MSG)
assert(not pcall(setmetatable, b, {}), MSG)
mt.__metatable = "The metatable is locked"
assert(getmetatable(b) ~= mt, MSG)
assert(not pcall(function()
	return b + b
end), MSG)
mt.__add = function(x, y)
	assert(x == y, MSG)
	return "asd"
end
assert(b + b == "asd", MSG)

local c = newproxy(b)
assert(not pcall(function() return b + c end), MSG)
assert(c + c == "asd", MSG)
assert(getmetatable(c) == getmetatable(b), MSG)

assert(not pcall(newproxy, 1), MSG)
assert(not pcall(newproxy, a), MSG)

assert(pcall(newproxy, nil), MSG)
assert(pcall(newproxy), MSG)
assert(pcall(newproxy, true), MSG)
assert(pcall(newproxy, false), MSG)
assert(pcall(newproxy, b), MSG)
assert(pcall(newproxy, c), MSG)

print("[X] passed proxy tests")