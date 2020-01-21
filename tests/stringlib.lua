local MSG = "[ ] FAILED string library tests"

assert(table.concat({("Hello, World!"):byte(1, 13)}, ",") == "72,101,108,108,111,44,32,87,111,114,108,100,33", MSG)
assert(string.char(72, 101, 108, 108, 111, 44, 32, 87, 111, 114, 108, 100, 33) == "Hello, World!", MSG)
assert(getmetatable("") == "The metatable is locked", MSG)

-- No bytecode dumps in Zua:
-- [INCONSISTENT]
assert(("").dump == nil, MSG)
assert(string.dump == nil, MSG)

math.randomseed(11)

local s = ""

for i = 1, 400 do
	s = s .. string.char(math.random(64 + 1, 64 + 26))
end

assert(400 == string.len(s) and #s == 400, MSG)

s = "a\0b\0c"
assert(s:byte(2) == 0, MSG)
assert(s:byte(4) == 0, MSG)
assert(s:len() == 5, MSG)

assert(("HELLO, WORLD!"):lower() == "hello, world!", MSG)
assert(("hello, world!"):lower() == "hello, world!", MSG)
assert(("Hello, world!"):lower() == "hello, world!", MSG)
assert(("HELLO, WORLD!"):upper() == "HELLO, WORLD!", MSG)
assert(("hello, world!"):upper() == "HELLO, WORLD!", MSG)
assert(("Hello, world!"):upper() == "HELLO, WORLD!", MSG)

local s = "Hello!"
local ss = ""

for i = 1, 300 do
	ss = ss .. s
end

assert(s:rep(300) == ss, MSG)

local s = "Hello, World!"

assert(s:reverse() == "!dlroW ,olleH", MSG)

assert(s:sub("3", 5) == "llo", MSG)
assert(s:sub(-11, 5) == "llo", MSG)
assert(s:sub(-11, -9) == "llo", MSG)
assert(s:sub(3, -9) == "llo", MSG)

print("[X] passed string library tests")