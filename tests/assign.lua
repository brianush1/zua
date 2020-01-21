local MSG = "[ ] FAILED assignment tests"
assert(foo == nil, MSG)
foo = 7
assert(foo == 7, MSG)
local foo = 2
assert(foo == 2, MSG)
foo = 3
assert(foo == 3, MSG)
assert(_G.foo == 7, MSG)

goo = foo
local goo = goo
assert(goo == 3, MSG)
assert(_G.goo == goo, MSG)
goo = 4
assert(goo == 4, MSG)
assert(_G.goo == 3, MSG)
assert(_G.goo ~= goo, MSG)

boo = 2
assert(_G.boo == boo and boo == 2, MSG)
boo = 3
assert(_G.boo == boo and boo == 3, MSG)

local x, y
x, y = 1, 2
assert(x == 1 and y == 2, MSG)

u, v = 3, 4
assert(u == 3 and v == 4, MSG)

local l1, l2 = {}, {}
assert(l1 ~= l2, MSG)

g1, l1[1], l2[1], g2 = 1, 2, 3, 4

assert(g1 == 1 and g2 == 4, MSG)
assert(l1[1] == 2 and l2[1] == 3, MSG)

print("[X] passed assignment tests")