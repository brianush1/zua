local MSG = "[ ] FAILED table tests"
local SIZE = 10^2

assert(#{} == 0, MSG)
assert(#{"a"} == 1, MSG)

local arr = {}
for i = 1, SIZE do
	arr[i] = i * 3 -- allow array part
end
for i = SIZE, 1, -1 do
	assert(arr[i] == i * 3, MSG)
end

local t = {}
for i = 1, SIZE do
	t[i + 0.25] = i * 3 -- force into hash part
end
for i = SIZE + 0.25, 1.25, -1 do
	assert(t[i] == (i - 0.25) * 3, MSG)
end

assert(not pcall(function()
	local t = {}
	t[nil] = true
end), MSG)

assert(not pcall(function()
	local t = setmetatable({}, {__newindex = function() end})
	t[nil] = true
end), MSG)

assert(pcall(function()
	local t = setmetatable({}, {__index = function() end})
	local a = t[nil]
end), MSG)

assert(not pcall(function()
	local t = setmetatable({}, {__index = function() end, __newindex = function() end})
	local a = t[nil]
	t[nil] = true
end), MSG)

local t = {"a", "b", "c", [2] = "d"}
assert(table.concat(t, ",") == "a,b,c", MSG)

local t = {"a", [2] = "d", "b", "c"}
assert(table.concat(t, ",") == "a,b,c", MSG)

local t = {"a", [2] = "b", [3] = "c", [2] = "d"}
assert(table.concat(t, ",") == "a,d,c", MSG)

local t = {"a", [2] = "d", [2] = "b", [3] = "c"}
assert(table.concat(t, ",") == "a,b,c", MSG)

local function fun(...)
	return {...}, {..., "a"}, {"a", ...}
end

local t, t2, t3 = fun(3, 2, 1)

assert(#t == 3, MSG)
for i = 1, 3 do
	assert(t[i] == 4 - i, MSG)
end

assert(#t2 == 2, MSG)
assert(table.concat(t2, ",") == "3,a", MSG)

assert(#t3 == 4, MSG)
assert(table.concat(t3, ",") == "a,3,2,1", MSG)

local function give123()
	return 1, 2, 3
end

assert(table.concat({4, give123()}, ",") == "4,1,2,3", MSG)
assert(table.concat({give123(), 4}, ",") == "1,4", MSG)

print("[X] passed table tests")