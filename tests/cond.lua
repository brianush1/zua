local MSG = "[ ] FAILED conditional operator tests"

assert(true and true, MSG .. " (1)")
assert(not (true and false), MSG .. " (2)")
assert(not (false and false), MSG .. " (3)")
assert(not (false and true), MSG .. " (4)")

assert(true or true, MSG .. " (5)")
assert(true or false, MSG .. " (6)")
assert(not (false or false), MSG .. " (7)")
assert(false or true, MSG .. " (8)")

print("[X] passed conditional operator tests")