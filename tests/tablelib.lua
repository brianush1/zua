local MSG = "[ ] FAILED table library tests"

local t = {1, 2, 3, 4, 5, 6, 7, 8, 9}
table.insert(t, 10)
table.insert(t, 10)
table.insert(t, 10, 11)

assert(table.concat(t, ",") == "1,2,3,4,5,6,7,8,9,11,10,10", MSG)

local t = {}

for i = 1, 100 do
	t[i] = i
end

t[10^8] = 10^8

assert(table.maxn(t) == 10^8, MSG)

local t = {1, 2, 3, 4, 5, 6, 7, 8, 9}

table.remove(t, 4)

assert(table.concat(t, "", 2, 7) == "235678", MSG)

local t = {}

math.randomseed(11)

for i = 1, 1000 do
	t[i] = i
end

local init = table.concat(t, ",")

for i = 1000, 2, -1 do
	local j = math.random(1, i)
	t[i], t[j] = t[j], t[i]
end

assert(table.concat(t, ",") ~= init, MSG)

table.sort(t)

assert(table.concat(t, ",") == init, MSG)

print("[X] passed table library tests")