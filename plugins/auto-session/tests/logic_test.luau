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

local function assert_list_equal(actual, expected, message)
	assert_equal(#actual, #expected, (message or "list length") .. " (length)")
	for i = 1, #expected do
		assert_equal(actual[i], expected[i], (message or "list item") .. " [" .. tostring(i) .. "]")
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

-- Auto-close tests
do
	-- 1. Emptying a previously populated session closes it when another session exists on the same host
	local state = logic.new_lifecycle_state()
	logic.observe_layout(state, {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 0, locked = false, tabs = 1 },
	}, {
		{ id = 10, session = 1 },
		{ id = 20, session = 2 },
	}, {
		{ pane = 100, tab = 10, parked = false },
		{ pane = 200, tab = 20, parked = false },
	})

	local sessions_after = {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 0, locked = false, tabs = 0 },
	}
	local panes_after = {
		{ pane = 100, tab = 10, parked = false },
	}
	logic.observe_layout(state, sessions_after, { { id = 10, session = 1 } }, panes_after)
	assert_list_equal(logic.sessions_to_close(state, sessions_after, panes_after), { 2 }, "closes emptied session")
end

do
	-- 2. Never closes a session that was never populated (e.g. freshly created empty session)
	local state = logic.new_lifecycle_state()
	local sessions = {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 0, locked = false, tabs = 0 },
	}
	local panes = {
		{ pane = 100, tab = 10, parked = false },
	}
	logic.observe_layout(state, sessions, { { id = 10, session = 1 } }, panes)
	assert_list_equal(logic.sessions_to_close(state, sessions, panes), {}, "skips never-populated empty session")
end

do
	-- 3. Respects locked sessions
	local state = logic.new_lifecycle_state()
	logic.observe_layout(state, {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 0, locked = true, tabs = 1 },
	}, {
		{ id = 10, session = 1 },
		{ id = 20, session = 2 },
	}, {
		{ pane = 100, tab = 10, parked = false },
		{ pane = 200, tab = 20, parked = false },
	})
	local sessions_after = {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 0, locked = true, tabs = 0 },
	}
	local panes_after = { { pane = 100, tab = 10, parked = false } }
	logic.observe_layout(state, sessions_after, { { id = 10, session = 1 } }, panes_after)
	assert_list_equal(logic.sessions_to_close(state, sessions_after, panes_after), {}, "skips locked session")
end

do
	-- 4. Never closes the only remaining session on a host (even if another host has sessions)
	local state = logic.new_lifecycle_state()
	logic.observe_layout(state, {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 1, locked = false, tabs = 1 },
	}, {
		{ id = 10, session = 1 },
		{ id = 20, session = 2 },
	}, {
		{ pane = 100, tab = 10, parked = false },
		{ pane = 200, tab = 20, parked = false },
	})
	local sessions_after = {
		{ id = 1, host = 0, locked = false, tabs = 0 },
		{ id = 2, host = 1, locked = false, tabs = 1 },
	}
	local panes_after = { { pane = 200, tab = 20, parked = false } }
	logic.observe_layout(state, sessions_after, { { id = 20, session = 2 } }, panes_after)
	assert_list_equal(logic.sessions_to_close(state, sessions_after, panes_after), {}, "skips sole session on host")
end

do
	-- 5. Protects a session whose only pane was parked, while still closing a different emptied session
	local state = logic.new_lifecycle_state()
	logic.observe_layout(state, {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 0, locked = false, tabs = 1 },
		{ id = 3, host = 0, locked = false, tabs = 1 },
	}, {
		{ id = 10, session = 1 },
		{ id = 20, session = 2 },
		{ id = 30, session = 3 },
	}, {
		{ pane = 100, tab = 10, parked = false },
		{ pane = 200, tab = 20, parked = false },
		{ pane = 300, tab = 30, parked = false },
	})

	-- Pane 100 parked in session 1; pane 200 closed in session 2
	local sessions_mid = {
		{ id = 1, host = 0, locked = false, tabs = 0 },
		{ id = 2, host = 0, locked = false, tabs = 0 },
		{ id = 3, host = 0, locked = false, tabs = 1 },
	}
	local panes_mid = {
		{ pane = 100, tab = nil, parked = true },
		{ pane = 300, tab = 30, parked = false },
	}
	logic.observe_layout(state, sessions_mid, { { id = 30, session = 3 } }, panes_mid)
	assert_list_equal(
		logic.sessions_to_close(state, sessions_mid, panes_mid),
		{ 2 },
		"protects parked session 1 while closing emptied session 2"
	)

	-- Later pane 100 is closed too -> now session 1 should close
	logic.forget_session(state, 2)
	local sessions_final = {
		{ id = 1, host = 0, locked = false, tabs = 0 },
		{ id = 3, host = 0, locked = false, tabs = 1 },
	}
	local panes_final = {
		{ pane = 300, tab = 30, parked = false },
	}
	logic.observe_layout(state, sessions_final, { { id = 30, session = 3 } }, panes_final)
	assert_list_equal(
		logic.sessions_to_close(state, sessions_final, panes_final),
		{ 1 },
		"closes session 1 once its parked pane is gone"
	)
end

do
	-- 6. Unknown parked pane ownership fails safe and avoids closing any empty session
	local state = logic.new_lifecycle_state()
	logic.observe_layout(state, {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 0, locked = false, tabs = 1 },
	}, {
		{ id = 10, session = 1 },
		{ id = 20, session = 2 },
	}, {
		{ pane = 999, tab = nil, parked = true },
		{ pane = 100, tab = 10, parked = false },
		{ pane = 200, tab = 20, parked = false },
	})
	local sessions_after = {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 0, locked = false, tabs = 0 },
	}
	local panes_after = {
		{ pane = 999, tab = nil, parked = true },
		{ pane = 100, tab = 10, parked = false },
	}
	logic.observe_layout(state, sessions_after, { { id = 10, session = 1 } }, panes_after)
	assert_list_equal(
		logic.sessions_to_close(state, sessions_after, panes_after),
		{},
		"unknown parked pane blocks auto-close"
	)
end

do
	-- 7. Moving the last pane to another session empties source session -> closes source session
	local state = logic.new_lifecycle_state()
	logic.observe_layout(state, {
		{ id = 1, host = 0, locked = false, tabs = 1 },
		{ id = 2, host = 0, locked = false, tabs = 1 },
	}, {
		{ id = 10, session = 1 },
		{ id = 20, session = 2 },
	}, {
		{ pane = 100, tab = 10, parked = false },
		{ pane = 200, tab = 20, parked = false },
	})
	local sessions_after = {
		{ id = 1, host = 0, locked = false, tabs = 2 },
		{ id = 2, host = 0, locked = false, tabs = 0 },
	}
	local tabs_after = {
		{ id = 10, session = 1 },
		{ id = 21, session = 1 },
	}
	local panes_after = {
		{ pane = 100, tab = 10, parked = false },
		{ pane = 200, tab = 21, parked = false },
	}
	logic.observe_layout(state, sessions_after, tabs_after, panes_after)
	assert_list_equal(
		logic.sessions_to_close(state, sessions_after, panes_after),
		{ 2 },
		"closes session emptied by moving its last pane"
	)
end

print("auto-session logic tests passed")
