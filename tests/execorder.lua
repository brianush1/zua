local assert = assert
local print = print
local table = table
local setmetatable = setmetatable
local MSG = "[ ] FAILED execution order tests"
local t = {}

local function gen(i, j)
	t[#t + 1] = i
	return j or i
end

gen(gen(1, 3), gen(2))
assert(table.concat(t, ",") == "1,2,3", MSG)

t = {}

gen(gen(1) + gen(2))
assert(table.concat(t, ",") == "1,2,3", MSG)

t = {}

do
	local mt
	mt = {
		__add = function(self, o)
			gen(self.n)
			gen(o.n)
			return setmetatable({ n = o.n + 10 * self.n }, mt)
		end
	}

	local a = setmetatable({ n = 1 }, mt)
	local b = setmetatable({ n = 2 }, mt)
	local c = setmetatable({ n = 3 }, mt)
	local d = a + b + c

	assert(table.concat(t, ",") == "1,2,12,3", MSG)

	t = {}

	local mt
	mt = {
		__concat = function(self, o)
			gen(self.n)
			gen(o.n)
			return setmetatable({ n = o.n + 10 * self.n }, mt)
		end
	}

	local a = setmetatable({ n = 1 }, mt)
	local b = setmetatable({ n = 2 }, mt)
	local c = setmetatable({ n = 3 }, mt)
	local d = a .. b .. c

	assert(table.concat(t, ",") == "2,3,1,23", MSG)
end

t = {}

local e = {}

a, (function()
	gen(1)

	setfenv(2, setmetatable({}, {
		__newindex = function(self, key, value)
			t[#t + 1] = key
			e[key] = value
		end
	}))

	return setmetatable({}, {
		__newindex = function()
			gen(6)
		end
	})
end)()[gen(2)], (function()
	return setmetatable({}, {
		__newindex = function()
			gen(8)
		end
	})
end)()[1], b = gen(3), gen(4), gen(5), gen(7)

assert(not a and e.a == 3, MSG)
assert(not b and e.b == 7, MSG)
assert(table.concat(t, ",") == "1,2,3,4,5,7,b,8,6,a", MSG)
print("[X] passed execution order tests")