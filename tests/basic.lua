local MSG = "[ ] FAILED basic standard library tests"

assert(_VERSION == "Lua 5.1", MSG)
assert(_ZUAVERSION == "Zua 1.0", MSG)

assert(collectgarbage, MSG)

-- no runtime code execution in Zua:
-- [INCONSISTENT]
assert(not dofile, MSG)
assert(not load, MSG)
assert(not loadfile, MSG)
assert(not loadstring, MSG)

assert(_G == getfenv())

local fenv = getfenv

function foo()
	fenv(2).assert(true, MSG)
	return x + y
end
assert(setfenv(foo, { x = 2 }) == foo, MSG)
getfenv(foo).y = 7
assert(not x and foo() == 9, MSG)

assert(getmetatable{} == nil, MSG)

do
	local t = {}
	setmetatable(t, {})
	getmetatable(t).__index = function(t, k)
		return k
	end
	assert(t.hello == "hello", MSG)
	t.hello = "world"
	assert(t.hello == "world", MSG)
	local meta = getmetatable(t)
	meta.__metatable = false
	assert(getmetatable(t) ~= meta, MSG)
	assert(getmetatable(t) == false, MSG)
end

do
	local arr = {}
	for i = 2, 100 do
		arr[i] = i
	end
	for i, v in ipairs(arr) do
		assert(false, MSG)
	end
	arr[1] = 1
	local count = 0
	for i, v in ipairs(arr) do
		count = count + 1
		assert(i == count and i == v, MSG)
	end
	assert(count == 100, MSG)
end

do
	local arr = {}
	arr[70] = true
	for i = 2, 100 do
		arr[i] = i
	end
	for i, v in ipairs(arr) do
		assert(false, MSG)
	end
	arr[1] = 1
	local count = 0
	for i, v in ipairs(arr) do
		count = count + 1
		assert(i == count and i == v, MSG)
	end
	assert(count == 100, MSG)
end

do
	local arr = {}
	local idx = {}
	for i = 1, 100 do
		local n
		repeat
			n = math.random(1, 100)
		until not arr[n]
		idx[#idx + 1] = n
		arr[n] = i
	end
	local count = 0
	for i, v in next, arr do
		arr[i] = nil
		count = count + 1
	end
	assert(count == 100, MSG)
end

do
	local arr = {}
	local idx = {}
	for i = 1, 100 do
		local n
		repeat
			n = math.random(1, 100)
		until not arr[n]
		idx[#idx + 1] = n
		arr[n] = i
	end
	local count = 0
	for i, v in pairs(arr) do
		arr[i] = nil
		count = count + 1
	end
	assert(count == 100, MSG)
end

do
	local function eq()
		return true
	end

	local a = setmetatable({}, {__eq = eq})
	local b = setmetatable({}, {__eq = eq})

	assert(a == b, MSG)
	assert(a == a, MSG)
	assert(not rawequal(a, b), MSG)
	assert(rawequal(a, a), MSG)
end

do
	local a = setmetatable({
		[2] = "a",
		foo = "hello"
	}, {
		__index = function() return "hi" end
	})

	assert(a[1] == "hi", MSG)
	assert(a[2] == "a", MSG)
	assert(a.foo == "hello", MSG)
	assert(rawget(a, 1) == nil, MSG)
	assert(rawget(a, 2) == "a", MSG)
	assert(rawget(a, "foo") == "hello", MSG)
end

do

	local a = setmetatable({}, {
		__newindex = function() end
	})

	a[1] = "hi"
	assert(a[1] == nil, MSG)
	rawset(a, 1, "hi")
	assert(a[1] == "hi", MSG)
	a[1] = nil
	assert(a[1] == nil, MSG)

end

do
	assert(select("#", 1, 2, 3) == 3, MSG)
	assert(select("#", 1, 2, nil) == 3, MSG)
	assert(select("#", 1, 2) == 2, MSG)

	assert(select("#", select(2, 1, 2, 3)) == 2, MSG)
	assert(select("#", select(2, 1, 2, nil)) == 2, MSG)
	assert(select("#", select(2, 1, 2)) == 1, MSG)

	assert(select("#", select(-2, 1, 2, 3)) == 2, MSG)
	assert(select("#", select(-2, 1, 2, nil)) == 2, MSG)
	assert(select("#", select(-2, 1, 2)) == 2, MSG)

	assert(select(2, 1, 2, 3) == 2, MSG)
	assert(select(3, 1, 2, 3) == 3, MSG)
	assert(select(4, 1, 2, 3) == nil, MSG)
	assert(select(1, 1, 2, 3) == 1, MSG)

	assert(select(-3, 1, 2, 3) == 1, MSG)
	assert(select(-2, 1, 2, 3) == 2, MSG)
	assert(select(-1, 1, 2, 3) == 3, MSG)
	assert(not pcall(select, -4, 1, 2, 3), MSG)
end

do
	assert(tonumber("0225") == 225, MSG)
	assert(tonumber("2.25") == 2.25, MSG)
	assert(tonumber("2.") == 2, MSG)
	assert(tonumber(".25") == .25, MSG)
	assert(tonumber("A7", 16) == 167, MSG)
	assert(tonumber("A7", 36) == 367, MSG)
end

assert(tostring(45) == "45", MSG)
assert(tostring(setmetatable({}, {
	__tostring = function() return "esgs" end
})) == "esgs", MSG)

assert(type(1) == "number", MSG)
assert(type(nil) == "nil", MSG)
assert(type("") == "string", MSG)
assert(type(false) == "boolean", MSG)
assert(type({}) == "table", MSG)
assert(type(type) == "function", MSG)

assert(select("#", unpack{1, 2, 3, 4}) == 4, MSG)
assert(table.concat({select(3, unpack{1, 2, 3, 4, 5, 6, 7})}, ",") == "3,4,5,6,7", MSG)

local function fun()
	error''
end

local a, b, c = xpcall(fun, function()
	setfenv(3, {
		didit = "hooray!"
	})
	return "boo"
end)

assert(a == false and b == "boo" and c == nil, MSG)
assert(getfenv(fun).didit == "hooray!", MSG)

print("[X] passed basic standard library tests")