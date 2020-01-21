-- Tests taken from Lua 5.2 test suite
local MSG = "[ ] FAILED bit32 library tests"

assert(bit32.band() == bit32.bnot(0), MSG)
assert(bit32.btest() == true, MSG)
assert(bit32.bor() == 0, MSG)
assert(bit32.bxor() == 0, MSG)

assert(bit32.band() == bit32.band(0xffffffff), MSG)
assert(bit32.band(1,2) == 0, MSG)

assert(bit32.band(-1) == 0xffffffff, MSG)
assert(bit32.band(2^33 - 1) == 0xffffffff, MSG)
assert(bit32.band(-2^33 - 1) == 0xffffffff, MSG)
assert(bit32.band(2^33 + 1) == 1, MSG)
assert(bit32.band(-2^33 + 1) == 1, MSG)
assert(bit32.band(-2^40) == 0, MSG)
assert(bit32.band(2^40) == 0, MSG)
assert(bit32.band(-2^40 - 2) == 0xfffffffe, MSG)
assert(bit32.band(2^40 - 4) == 0xfffffffc, MSG)

assert(bit32.lrotate(0, -1) == 0, MSG)
assert(bit32.lrotate(0, 7) == 0, MSG)
assert(bit32.lrotate(0x12345678, 4) == 0x23456781, MSG)
assert(bit32.rrotate(0x12345678, -4) == 0x23456781, MSG)
assert(bit32.lrotate(0x12345678, -8) == 0x78123456, MSG)
assert(bit32.rrotate(0x12345678, 8) == 0x78123456, MSG)
assert(bit32.lrotate(0xaaaaaaaa, 2) == 0xaaaaaaaa, MSG)
assert(bit32.lrotate(0xaaaaaaaa, -2) == 0xaaaaaaaa, MSG)
for i = -50, 50 do
	assert(bit32.lrotate(0x89abcdef, i) == bit32.lrotate(0x89abcdef, i%32), MSG)
end

assert(bit32.lshift(0x12345678, 4) == 0x23456780, MSG)
assert(bit32.lshift(0x12345678, 8) == 0x34567800, MSG)
assert(bit32.lshift(0x12345678, -4) == 0x01234567, MSG)
assert(bit32.lshift(0x12345678, -8) == 0x00123456, MSG)
assert(bit32.lshift(0x12345678, 32) == 0, MSG)
assert(bit32.lshift(0x12345678, -32) == 0, MSG)
assert(bit32.rshift(0x12345678, 4) == 0x01234567, MSG)
assert(bit32.rshift(0x12345678, 8) == 0x00123456, MSG)
assert(bit32.rshift(0x12345678, 32) == 0, MSG)
assert(bit32.rshift(0x12345678, -32) == 0, MSG)
assert(bit32.arshift(0x12345678, 0) == 0x12345678, MSG)
assert(bit32.arshift(0x12345678, 1) == 0x12345678 / 2, MSG)
assert(bit32.arshift(0x12345678, -1) == 0x12345678 * 2, MSG)
assert(bit32.arshift(-1, 1) == 0xffffffff, MSG)
assert(bit32.arshift(-1, 24) == 0xffffffff, MSG)
assert(bit32.arshift(-1, 32) == 0xffffffff, MSG)
assert(bit32.arshift(-1, -1) == (-1 * 2) % 2^32, MSG)

local c = {0, 1, 2, 3, 10, 0x80000000, 0xaaaaaaaa, 0x55555555, 0xffffffff, 0x7fffffff}

for _, b in pairs(c) do
	assert(bit32.band(b) == b, MSG)
	assert(bit32.band(b, b) == b, MSG)
	assert(bit32.btest(b, b) == (b ~= 0), MSG)
	assert(bit32.band(b, b, b) == b, MSG)
	assert(bit32.btest(b, b, b) == (b ~= 0), MSG)
	assert(bit32.band(b, bit32.bnot(b)) == 0, MSG)
	assert(bit32.bor(b, bit32.bnot(b)) == bit32.bnot(0), MSG)
	assert(bit32.bor(b) == b, MSG)
	assert(bit32.bor(b, b) == b, MSG)
	assert(bit32.bor(b, b, b) == b, MSG)
	assert(bit32.bxor(b) == b, MSG)
	assert(bit32.bxor(b, b) == 0, MSG)
	assert(bit32.bxor(b, 0) == b, MSG)
	assert(bit32.bnot(b) ~= b, MSG)
	assert(bit32.bnot(bit32.bnot(b)) == b, MSG)
	assert(bit32.bnot(b) == 2^32 - 1 - b, MSG)
	assert(bit32.lrotate(b, 32) == b, MSG)
	assert(bit32.rrotate(b, 32) == b, MSG)
	assert(bit32.lshift(bit32.lshift(b, -4), 4) == bit32.band(b, bit32.bnot(0xf)), MSG)
	assert(bit32.rshift(bit32.rshift(b, 4), -4) == bit32.band(b, bit32.bnot(0xf)), MSG)
	for i = -40, 40 do
		assert(bit32.lshift(b, i) == math.floor((b * 2^i) % 2^32), MSG)
	end
end

assert(not pcall(bit32.band, {}), MSG)
assert(not pcall(bit32.bnot, "a"), MSG)
assert(not pcall(bit32.lshift, 45), MSG)
assert(not pcall(bit32.lshift, 45, print), MSG)
assert(not pcall(bit32.rshift, 45, print), MSG)

assert(bit32.extract(0x12345678, 0, 4) == 8, MSG)
assert(bit32.extract(0x12345678, 4, 4) == 7, MSG)
assert(bit32.extract(0xa0001111, 28, 4) == 0xa, MSG)
assert(bit32.extract(0xa0001111, 31, 1) == 1, MSG)
assert(bit32.extract(0x50000111, 31, 1) == 0, MSG)
assert(bit32.extract(0x50000111, 31) == 0, MSG) -- this wasn't tested in the Lua test suite (!)
assert(bit32.extract(0xf2345679, 0, 32) == 0xf2345679, MSG)

assert(not pcall(bit32.extract, 0, -1), MSG)
assert(not pcall(bit32.extract, 0, 32), MSG)
assert(not pcall(bit32.extract, 0, 0, 33), MSG)
assert(not pcall(bit32.extract, 0, 31, 2), MSG)

assert(bit32.replace(0x12345678, 5, 28, 4) == 0x52345678, MSG)
assert(bit32.replace(0x12345678, 0x87654321, 0, 32) == 0x87654321, MSG)
assert(bit32.replace(0, 1, 2) == 2^2, MSG)
assert(bit32.replace(0, -1, 4) == 2^4, MSG)
assert(bit32.replace(-1, 0, 31) == 2^31 - 1, MSG)
assert(bit32.replace(-1, 0, 1, 2) == 2^32 - 7, MSG)

print("[X] passed bit32 library tests")