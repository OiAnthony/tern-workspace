local logic = require("../lib/logic")

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function assert_true(value, message)
	if not value then
		error(message or "expected true")
	end
end

-- Naming tests
assert_equal(logic.basename("/Users/anthony/tern-workspace"), "tern-workspace", "directory basename")
assert_equal(logic.basename("/Users/anthony/tern-workspace/"), "tern-workspace", "trailing slash basename")
assert_equal(logic.basename("/"), "root", "root basename")

local initial_record = {}
local record = initial_record
local action
record, action = logic.observe(record, "Bright Meadow", "workspace")
assert_equal(initial_record.auto_name, nil, "observation does not mutate stored record")
assert_equal(action, "workspace", "first observation renames")
assert_equal(record.auto_name, "workspace", "first observation records automatic name")

local completed_pending = { auto_name = "workspace", manual = false, pending_name = "other" }
completed_pending, action = logic.observe(completed_pending, "other", "other")
assert_equal(action, nil, "completed pending rename is accepted")
assert_equal(completed_pending.auto_name, "other", "completed pending rename records target")

record, action = logic.observe(record, "workspace", "other")
assert_equal(action, "other", "directory change renames")
assert_equal(record.auto_name, "other", "directory change records automatic name")

record, action = logic.observe(record, "Manually chosen", "third")
assert_equal(action, nil, "manual rename is preserved")
assert_true(record.manual, "manual rename locks the session")

record, action = logic.observe(record, "Manually chosen", "fourth")
assert_equal(action, nil, "locked session stays unchanged")

print("auto-session logic tests passed")
