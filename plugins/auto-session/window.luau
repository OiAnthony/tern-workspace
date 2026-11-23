--!strict

local logic = require("./lib/logic")

local POLL_MS = 250
local active_timer: TimerHandle? = nil
local lifecycle = logic.new_lifecycle_state()

type StoredRecord = logic.Record

local function session_key(session: ManagedSession): string
	return "session:" .. tostring(session.host) .. ":" .. tostring(session.id)
end

local function load_record(key: string): StoredRecord
	local value = tern.kv.get(key)
	if type(value) ~= "table" then
		return { auto_name = nil, manual = false, pending_name = nil }
	end

	local auto_name = value.auto_name
	local pending_name = value.pending_name
	return {
		auto_name = if type(auto_name) == "string" then auto_name else nil,
		manual = value.manual == true,
		pending_name = if type(pending_name) == "string" then pending_name else nil,
	}
end

local function changed(before: StoredRecord, after: StoredRecord): boolean
	return before.auto_name ~= after.auto_name
		or before.manual ~= after.manual
		or before.pending_name ~= after.pending_name
end

local function first_leaf(tree: TabTree): number?
	if tree.pane ~= nil then
		return tree.pane
	end
	if tree[1] == nil then
		return nil
	end
	return first_leaf(tree[1])
end

local function main_pane(cx: WindowCx, session_id: number): number?
	local first_tab: TabInfo? = nil
	for _, tab in cx.session:tabs() do
		if tab.session == session_id and (first_tab == nil or tab.position < first_tab.position) then
			first_tab = tab
		end
	end
	if first_tab == nil then
		return nil
	end

	local layout = cx.session:layout(first_tab.id)
	if layout == nil then
		return nil
	end
	return first_leaf(layout.root)
end

local function snapshot(
	cx: WindowCx
): ({ logic.SessionSnapshot }, { logic.TabSnapshot }, { logic.PaneSnapshot })
	local sessions: { logic.SessionSnapshot } = {}
	for _, s in cx.sessions:list() do
		table.insert(sessions, {
			id = s.id,
			host = s.host,
			locked = s.locked,
			tabs = s.tabs,
		})
	end

	local tabs: { logic.TabSnapshot } = {}
	for _, t in cx.session:tabs() do
		table.insert(tabs, {
			id = t.id,
			session = t.session,
		})
	end

	local panes: { logic.PaneSnapshot } = {}
	for _, p in cx.session:panes() do
		table.insert(panes, {
			pane = p.pane,
			tab = p.tab,
			parked = p.parked,
		})
	end

	return sessions, tabs, panes
end

local function observe_sessions(cx: WindowCx): ({ logic.SessionSnapshot }, { logic.PaneSnapshot })
	local sessions, tabs, panes = snapshot(cx)
	logic.observe_layout(lifecycle, sessions, tabs, panes)
	return sessions, panes
end

local function close_emptied_sessions(cx: WindowCx)
	local sessions, panes = observe_sessions(cx)
	local ids = logic.sessions_to_close(lifecycle, sessions, panes)
	for _, session_id in ids do
		logic.forget_session(lifecycle, session_id)
		pcall(function()
			cx.sessions:close(session_id)
		end)
	end
end

local function sync_name(cx: WindowCx)
	local session = cx.sessions:current()
	local pane_id = main_pane(cx, session.id)
	if pane_id == nil then
		return
	end

	local pane = cx.session:pane(pane_id)
	if pane == nil or pane.cwd == nil or pane.cwd == "" then
		return
	end

	local target_name = logic.basename(pane.cwd)
	if target_name == nil then
		return
	end

	local key = session_key(session)
	local before = load_record(key)
	local after, rename_to = logic.observe(before, session.name, target_name)
	if rename_to ~= nil then
		local pending: StoredRecord = {
			auto_name = before.auto_name,
			manual = before.manual,
			pending_name = rename_to,
		}
		tern.kv.set(key, pending)
		cx.sessions:rename(session.id, rename_to)
		after = { auto_name = rename_to, manual = false, pending_name = nil }
	end
	if changed(before, after) then
		tern.kv.set(key, after)
	end
end

local function sync(cx: WindowCx)
	close_emptied_sessions(cx)
	sync_name(cx)
end

local function schedule(delay_ms: number?)
	if active_timer ~= nil then
		return
	end
	active_timer = tern.timer(delay_ms or POLL_MS, function(cx)
		active_timer = nil
		if cx ~= nil then
			sync(cx)
			schedule()
		end
	end)
end

tern.on("window_start", function(cx)
	sync(cx)
	schedule()
end)

for _, event_name in { "pane_closed", "tab_closed" } do
	tern.on(event_name, function(_, cx)
		close_emptied_sessions(cx)
		sync_name(cx)
	end)
end

tern.on("session_ended", function(ev: SessionEndedEvent, cx)
	logic.forget_session(lifecycle, ev.session)
	sync(cx)
end)

for _, event_name in { "focus", "pane_created", "tab_created", "cwd" } do
	tern.on(event_name, function(_, cx)
		sync(cx)
	end)
end

-- Seed lifecycle tracking and restart polling immediately after plugin load or reload.
schedule(1)
