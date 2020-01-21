local MSG = "[ ] FAILED upvalues tests"
local t = {}

local function gen(i)
	t[#t + 1] = i
	return i
end

gen(1)
gen(2)
t[gen(5)] = gen(6)
assert(table.concat(t, ",") == "1,2,5,6,6", MSG)

local function x()
	return x
end

assert(x() == x, MSG)

local prev = x

local x = function()
	return x
end

assert(x() == prev, MSG)
assert(x() ~= x, MSG)

print("[X] passed upvalues tests")