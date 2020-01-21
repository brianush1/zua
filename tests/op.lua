local MSG = "[ ] FAILED operator tests"

assert(1 < 2, MSG)
assert(not (1 > 2), MSG)
assert(1 <= 2, MSG)
assert(1 <= 1, MSG)
assert(2 >= 1, MSG)
assert(1 <= 1, MSG)

assert(1 .. 2 == "12", MSG)
assert(1 .. 2 ~= 12, MSG)
assert("Hello, " .. "World!" == "Hello, World!", MSG)
assert("Hello, " .. " World!" ~= "Hello, World!", MSG)
assert(67 + 13 == 80, MSG)
assert(67 - 13 == 54, MSG)
assert(10 / 5 == 2, MSG)
assert(15 / 5 == 3, MSG)
assert(7 / 4 == 1.75, MSG)
assert(7 % 4 == 3, MSG)
assert(-1 % 4 == 3, MSG)
assert(7 % -4 == -1, MSG)
assert(-1 % -4 == -1, MSG)
assert(-5 % -4 == -1, MSG)

assert(-4 == -1 * 4, MSG)
assert(2^52 == 4503599627370496, MSG)

assert(2^53 == 2^53 + 1, MSG)
assert(2^53 ~= 2^53 + 2, MSG)

assert(2^54 == 2^54 + 1, MSG)
assert(2^54 == 2^54 + 2, MSG)
assert(2^54 ~= 2^54 + 3, MSG)
assert(2^54 ~= 2^54 + 4, MSG)
assert(2^54 + 4 == 2^54 + 3, MSG)

assert((2^788)^0.5 == 2^394, MSG)
assert(2^3^4 == 2^(3^4), MSG)
assert((2^3)^4 ~= 2^(3^4), MSG)

assert(2 * 3 + 4 == 10, MSG)
assert(2 + 3 * 4 == 14, MSG)

assert(not pcall(function() return {} < {} end), MSG)
assert(not pcall(function() return (2).a end), MSG)

local relOffset = 0

local function f(a)
	if relOffset == 3 then
		relOffset = 7
	else
		relOffset = relOffset + 1
	end
end

f(3)

assert(relOffset == 1, MSG)

local m = 1
for i = 1, 0 do
	m = 2
end

assert(m == 1, MSG)

print("[X] passed operator tests")