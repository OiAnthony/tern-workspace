--!strict

local grouping = require("../lib/grouping")
type GroupingModel = grouping.Model
type GroupingSession = grouping.SessionGroup
type GroupingProject = grouping.Project
type GroupingRoot = grouping.Root

local function pane(id: number, cwd: string?, tab: number?, extras: any?): PaneInfo
	local value: any = { pane = id, cwd = cwd or "", title = "", program = "", tab = tab }
	if extras ~= nil then for key, item in extras do value[key] = item end end
	return value :: PaneInfo
end

local function tab(id: number, session: number, position: number, overrides: any?): TabInfo
	local value: any = { id = id, session = session, position = position, pane = 0, name = nil, cwd = "", program = "", title = "", panes = 1, busy = false }
	if overrides ~= nil then for key, item in overrides do value[key] = item end end
	return value :: TabInfo
end

local function session(id: number, host: number, name: string, current: boolean?): ManagedSession
	return { id = id, name = name, host = host, current = current or false, locked = false, note = nil, tabs = 0 }
end

local function host(id: number, name: string, kind: "local" | "remote", pane_ids: { number }): ManagedHost
	return {
		id = id, name = name, kind = kind, state = "connected", address = nil, detail = nil,
		identity = nil, current = false, rtt_ms = nil, sessions = {}, panes = pane_ids,
	}
end

local function find_session(model: GroupingModel, host_id: number, session_id: number): GroupingSession
	assert(model.host == host_id)
	for _, group in model.sessions do if group.id == session_id then return group end end
    error("session not found")
end

local function find_project(group: GroupingSession, path: string, kind: string?): GroupingProject
    for _, project in group.projects do
        if project.path == path and (kind == nil or project.kind == kind) then return project end
    end
    error("project not found")
end

-- Git roots merge nested working directories; stale roots are ignored, and prefix paths stay distinct.
do
	local panes: { PaneInfo } = {
        pane(1, "/work/repo/a", 11), pane(2, "/work/repo/b/", 11),
        pane(3, "/work/repo-extra", 12), pane(4, "/work/repo", 13),
        pane(5, "/work/sibling-a", 14), pane(6, "/work/sibling-b", 15),
    }
    local tabs: { TabInfo } = { tab(11, 1, 1), tab(12, 1, 2), tab(13, 1, 3), tab(14, 1, 4), tab(15, 1, 5) }
    local roots: { [number]: GroupingRoot } = {
		[1] = { cwd = "/work/repo/a", root = "/work/repo/" },
		[2] = { cwd = "/work/repo/b", root = "/work/repo" },
		[3] = { cwd = "/work/repo", root = "/work/repo" }, -- stale for pane 3
	}
	local current_host = host(1, "local", "local", { 1, 2, 3, 4, 5, 6 })
	setmetatable(current_host.panes :: any, { __metatable = "native array" })
	setmetatable(panes, { __metatable = "native array" })
	local model = grouping.build(panes :: any, tabs, { session(1, 1, "main", true) }, current_host, roots)
	local group = find_session(model, 1, 1)
    assert(#group.projects == 5)
	local repo = find_project(group, "/work/repo", "git")
	assert(repo.count == 2 and repo.panes[1].pane == 1 and repo.panes[2].pane == 2)
    assert(find_project(group, "/work/repo-extra").kind == "cwd")
    assert(find_project(group, "/work/repo-extra").count == 1)
    assert(find_project(group, "/work/sibling-a") ~= find_project(group, "/work/sibling-b"))
    assert(model.count == 6)
end

-- Panes from one tab stay in their own projects; project order is independent of native tab order.
do
	local panes: { PaneInfo } = { pane(22, "/one", 8), pane(21, "/two", 7), pane(20, "/one", 7) }
	local tabs: { TabInfo } = { tab(7, 4, 2, { name = "Named", panes = 2 }), tab(8, 4, 1, { title = "Title" }) }
	local model = grouping.build(panes, tabs, { session(4, 2, "work") }, host(2, "remote", "remote", { 20, 21, 22 }), {})
	local group = find_session(model, 2, 4)
	assert(model.count == 3)
	local one = find_project(group, "/one")
	local two = find_project(group, "/two")
	assert(one.count == 2 and two.count == 1)
	assert(one.panes[1].pane == 20 and one.panes[2].pane == 22)
	assert(two.panes[1].pane == 21)
end

-- Only the selected host contributes sessions/panes; keys remain isolated across host switches.
do
	local panes: { PaneInfo } = {
		pane(31, "/alpha/app", 1), pane(32, "/beta/app", 1),
		pane(33, "/alpha/app", 2), pane(34, "/alpha/app", 3),
	}
	local tabs: { TabInfo } = { tab(1, 1, 1), tab(2, 2, 1), tab(3, 1, 1) }
	local hosts: { ManagedHost } = { host(10, "local", "local", { 31, 32 }), host(20, "remote", "remote", { 33, 34 }) }
	local sessions = { session(1, 10, "A"), session(2, 20, "B"), session(1, 20, "A") }
	local local_model = grouping.build(panes, tabs, sessions, hosts[1], {})
	local remote_model = grouping.build(panes, tabs, sessions, hosts[2], {})
	local local_group = find_session(local_model, 10, 1)
	local remote_one = find_session(remote_model, 20, 1)
	local remote_two = find_session(remote_model, 20, 2)
	assert(#local_group.projects == 2)
	assert(local_group.projects[1].label ~= local_group.projects[2].label)
	assert(#remote_one.projects == 1 and #remote_two.projects == 1)
	assert(remote_one.projects[1].key ~= remote_two.projects[1].key)
	assert(local_group.projects[1].key ~= remote_one.projects[1].key)
	assert(#local_model.sessions == 1 and local_model.count == 2)
	assert(#remote_model.sessions == 2 and remote_model.count == 2)
	assert(remote_one.projects[1].panes[1].pane == 34)
	assert(remote_two.projects[1].panes[1].pane == 33)
end

-- Parked panes share their own id-0 session; native paths use dirname and unknown paths remain blank.
do
	local panes: { PaneInfo } = {
		pane(41, "", nil, { parked = true, path = "/files/project/doc.txt", kind = "file" }),
		pane(42, "", nil, { path = "/boards/plan.board", kind = "board" }),
		pane(43, "", nil, { path = "/notebooks/demo.ipynb", kind = "notebook" }),
		pane(44, "", nil, { kind = "browser", path = "https://example.test" }),
		pane(45, "", nil, { kind = "git", path = "/repo/" }),
	}
	local model = grouping.build(panes, {}, { session(9, 3, "ordinary") }, host(3, "local", "local", { 41, 42, 43, 44, 45 }), {})
	local parked = find_session(model, 3, 0)
	assert(parked ~= nil and parked.name == "Parked" and not parked.current)
    assert(#parked.projects == 5)
    local parked_project = find_project(parked, "/files/project")
    assert(parked_project.panes[1].pane == 41)
	assert(model.count == 5)
	assert(grouping.directory(panes[1]) == "/files/project")
	assert(grouping.directory(panes[2]) == "/boards")
	assert(grouping.directory(panes[3]) == "/notebooks")
	assert(grouping.directory(panes[4]) == "")
	assert(grouping.directory(panes[5]) == "/repo")
	local unknown = find_project(parked, "")
	assert(unknown ~= nil and unknown.kind == "unknown" and unknown.count == 1)
	local ordinary = find_session(model, 3, 9)
	assert(ordinary ~= nil and #ordinary.projects == 0)
end

-- A transient pane missing current-host membership is excluded until membership is known.
do
	local panes = { pane(51, "/same", 51), pane(52, "/same", 52) }
	local model = grouping.build(panes, { tab(51, 1, 1), tab(52, 1, 2) }, { session(1, 0, "main") }, host(0, "local", "local", { 51 }), {})
	assert(model.count == 1)
	assert(find_project(find_session(model, 0, 1), "/same").panes[1].pane == 51)
end

-- A native block's file location takes precedence over a launch cwd; drive roots stay roots.
assert(grouping.directory(pane(60, "/launch", 60, { kind = "database", path = "/project/data.sqlite" })) == "/project")
assert(grouping.directory(pane(61, "", 61, { kind = "file", path = "C:\\project\\note.txt" })) == "C:\\project")
assert(grouping.directory(pane(62, "C:\\", 62)) == "C:\\")

local sidebar = require("../lib/sidebar")

local function has_token(tone: string?, expected: string): boolean
	if tone == nil then return false end
	for token in string.gmatch(tone, "%S+") do
		if token == expected then return true end
	end
	return false
end

local function pane_segment(view: any, id: number): any
	local command = "plugin.auto-tab-groups.pane-" .. tostring(id)
	for _, segment in view.segments do
		if segment.command == command then return segment end
	end
	error("pane segment not found: " .. tostring(id))
end

local function build_sidebar(panes: { PaneInfo }, tabs: { TabInfo }): any
	local pane_ids = {}
	for _, item in panes do table.insert(pane_ids, item.pane) end
	local model = grouping.build(panes, tabs, { session(1, 3, "main") }, host(3, "local", "local", pane_ids), {})
	local tokens: { [string]: number } = {}
	for _, group in model.sessions do
		for _, project in group.projects do tokens[project.key] = 1 end
	end
	return sidebar.build(model, {}, tokens)
end

-- Same-tab panes retain independent working/unread marks; seeing one never clears another.
do
	local panes: { PaneInfo } = {
		pane(71, "/shared", 7, { title = "Running", busy = true, kind = "terminal" }),
		pane(72, "/shared", 7, { title = "Unread", alert = true, at_prompt = true, kind = "agent" }),
	}
	local tabs = { tab(7, 1, 1, { panes = 2 }) }
	local view = build_sidebar(panes, tabs)
	local running = pane_segment(view, 71)
	local unread = pane_segment(view, 72)
	assert(has_token(running.tone, "atg-busy") and not has_token(running.tone, "atg-alert"))
	assert(has_token(unread.tone, "atg-alert") and not has_token(unread.tone, "atg-busy"))
	panes[2].alert = false
	panes[2].focused = true
	local read = pane_segment(build_sidebar(panes, tabs), 72)
	assert(read.text == "Unread" and read.tone == "atg-pane atg-focused")
	assert(has_token(pane_segment(build_sidebar(panes, tabs), 71).tone, "atg-busy"))
end

-- Seen prompt, failure and exit metadata never manufacture a new notification mark.
do
	local panes: { PaneInfo } = {
		pane(73, "/read", 8, { title = "Prompt", at_prompt = true, alert = false }),
		pane(74, "/read", 8, { title = "Error", error = "failed", alert = false }),
		pane(75, "/read", 8, { title = "Exited", exited = 7, alert = false }),
	}
	local tabs = { tab(8, 1, 1, { panes = 3 }) }
	local view = build_sidebar(panes, tabs)
	for _, item in panes do assert(pane_segment(view, item.pane).tone == "atg-pane") end
	panes[1].busy = true
	assert(has_token(pane_segment(build_sidebar(panes, tabs), 73).tone, "atg-busy"))
	panes[1].busy = false
	assert(pane_segment(build_sidebar(panes, tabs), 73).tone == "atg-pane")
end

-- Alert, focus, and floating are orthogonal to the main state; parked and native panes keep their own semantics.
do
	local panes: { PaneInfo } = {
		pane(77, "/flags", 10, { title = "Focused alert", focused = true, alert = true, busy = true }),
		pane(78, "", nil, { title = "Parked file", parked = true, path = "/files/parked.txt", kind = "file" }),
		pane(79, "", 10, { title = "Native file", kind = "file", path = "/files/native.txt" }),
		pane(80, "/flags", 10, { title = "Floating", floating = true, at_prompt = true }),
	}
	local view = build_sidebar(panes, { tab(10, 1, 1, { panes = 3 }) })
	local focused = pane_segment(view, 77)
	assert(has_token(focused.tone, "atg-focused") and has_token(focused.tone, "atg-alert") and has_token(focused.tone, "atg-busy"))
	local parked
	for _, segment in view.segments do
		if segment.text == "Parked file" then parked = segment end
	end
	assert(parked ~= nil and parked.command == nil and has_token(parked.tone, "atg-parked"))
	local native = pane_segment(view, 79)
	assert(native.text == "Native file")
	assert(not has_token(native.tone, "atg-busy") and not has_token(native.tone, "atg-alert"))
	local floating = pane_segment(view, 80)
	assert(has_token(floating.tone, "atg-floating") and not has_token(floating.tone, "atg-alert"))
end

-- Pane labels preserve title/program/kind/id fallback and literal status-looking names without added suffixes.
do
	local panes: { PaneInfo } = {
		pane(81, "/names", 11, { title = "Busy", busy = true }),
		pane(82, "/names", 11, { program = "Error", exited = 1 }),
		pane(83, "/names", 11, { kind = "file" }),
		pane(84, "/names", 11, {}),
	}
	local view = build_sidebar(panes, { tab(11, 1, 1, { panes = 4 }) })
	assert(pane_segment(view, 81).text == "Busy")
	assert(pane_segment(view, 82).text == "Error")
	assert(pane_segment(view, 83).text == "file")
	assert(pane_segment(view, 84).text == "Pane 84")
end

print("grouping tests passed")
