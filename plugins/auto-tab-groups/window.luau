--!strict

local grouping = require("./lib/grouping")
local sidebar = require("./lib/sidebar")
-- CSS projects these segments over native tabs and reveals the native list when segments are absent.
local sheet = tern.fs.read("styles.css")
-- Empty sessions provide no WindowCx, including after reload; install the persisted surface immediately.
if tern.kv.get("enabled") ~= false then tern.css("sidebar", sheet) end
local nativeHidden = false
local hideNative = [[
.tabs-v.tn-status:not(.tabs-auto) #sidebar > .tn-vt,
.tabs-v.tn-status:not(.tabs-auto) #sidebar > .tn-vt-find { visibility: hidden; }
]]
local revealNative = (string.gsub(hideNative, "hidden", "visible"))
local windowTitle: string? = nil
local function setTitle(value: string?)
	if value == windowTitle then return end
	windowTitle = value
	if value == nil then
		tern.css("window-title", '.tabs-v.tn-status:not(.tabs-auto) #tabbar .tb-tabs::after { content: none; }')
	else
		-- Pane titles are untrusted CSS string contents, not selectors or declarations.
		local escaped = string.gsub(value, '[%c\\"]', function(char)
			return string.format("\\%x ", string.byte(char))
		end)
		tern.css("window-title", '.tabs-v.tn-status:not(.tabs-auto) #tabbar .tb-tabs::after { content: "' .. escaped .. '"; }')
	end
end
local function showNative()
	setTitle(nil)
	if nativeHidden then
		tern.css("native-navigation", revealNative)
		nativeHidden = false
	end
end
local enabled = false
local folded: { [string]: boolean } = tern.kv.get("folded") or {}
local tokens: { [string]: number } = {}
local serial = 0
local view: sidebar.View = { segments = {}, actions = {} }
local model: grouping.Model? = nil
local registered: { [string]: string } = {}
type CacheEntry = { root: string?, pending: boolean, dirty: boolean? }
local cache: { [string]: CacheEntry } = {}
local inflight = 0
local queued = false
local signature = ""
local desired: { [string]: any } = { tabs = "Vertical", status_bar = true, tabs_autohide = false }
local update: (WindowCx) -> ()

local function invalidate()
	for _, entry in cache do entry.dirty = true end
end

local function schedule()
	if queued then return end
	queued = true
	tern.timer(0, function(cx)
		queued = false
		if cx then update(cx) else showNative() end
	end)
end

local function apply(cx: WindowCx, value: boolean)
	if value == enabled then return end
	if value then
		if tern.kv.get("previous-settings") == nil then
			local previous: { [string]: any } = {}
			for key in desired do previous[key] = cx.settings:get(key) end
			tern.kv.set("previous-settings", previous)
		end
		cx.settings:set_many(desired)
		tern.css("sidebar", sheet)
	else
		tern.css("sidebar", "")
		showNative()
		local previous = tern.kv.get("previous-settings")
		local restore: { [string]: any } = {}
		if type(previous) == "table" then
			for key, wanted in desired do
				if cx.settings:get(key) == wanted then restore[key] = previous[key] end
			end
		end
		if next(restore) then cx.settings:set_many(restore) end
		tern.kv.set("previous-settings", nil)
		view = { segments = {}, actions = {} }
		model = nil
	end
	enabled = value
	signature = ""
	tern.chrome.refresh()
end

local function dispatch(id: string, cx: WindowCx)
	local action = view.actions[id]
	if not enabled or not action then return end
	if action.kind == "fold" and action.key then
		folded[action.key] = not folded[action.key]
		tern.kv.set("folded", folded)
	elseif action.kind == "focus" and action.pane then
		local pane = cx.session:pane(action.pane)
		if pane and not pane.parked then cx.layout:focus(action.pane) end
	elseif action.kind == "session" and action.session then
		cx.sessions:switch(action.session)
	end
	update(cx)
end

local function token(key: string)
	if tokens[key] == nil then
		serial += 1
		tokens[key] = serial
	end
end

update = function(cx: WindowCx)
	apply(cx, tern.kv.get("enabled") ~= false)
	if not enabled then return end
	-- Native orientation/status changes are explicit requests to leave this surface.
	for key, value in desired do
		if cx.settings:get(key) ~= value then
			tern.kv.set("enabled", false)
			apply(cx, false)
			return
		end
	end
	local panes = cx.session:panes()
	local focused = cx.session:focused()
	local hasFocus = false
	local title: string? = nil
	for _, pane in panes do
		if pane.pane == focused then
			hasFocus = true
			title = pane.title
			if title == nil or title == "" then title = pane.program end
			if title == nil or title == "" then title = pane.kind end
			if title == nil or title == "" then title = "Pane " .. tostring(pane.pane) end
			break
		end
	end
	setTitle(title)
	if hasFocus ~= nativeHidden then
		nativeHidden = hasFocus
		tern.css("native-navigation", if hasFocus then hideNative else revealNative)
	end
	local host = cx.hosts:current()
	local localPanes: { [number]: boolean } = {}
	if host.kind == "local" then
		for _, id in host.panes do localPanes[id] = true end
	end
	local roots: { [number]: grouping.Root } = {}
	local live: { [string]: boolean } = {}
	for _, pane in panes do
		local cwd = grouping.directory(pane)
		if localPanes[pane.pane] and cwd ~= "" then
			live[cwd] = true
			local entry = cache[cwd]
			if (not entry or (entry.dirty and not entry.pending)) and inflight < 2 then
				local request: CacheEntry = { pending = true, root = if entry then entry.root else nil }
				cache[cwd] = request
				inflight += 1
				cx.git:repo(cwd):next(function(repo, err)
					inflight -= 1
					if cache[cwd] == request then
						request.pending = false
						request.root = if repo and not err then repo.root else nil
					end
					schedule()
				end)
				entry = request
			end
			if entry and entry.root then roots[pane.pane] = { cwd = cwd, root = entry.root } end
		end
	end
	for cwd in cache do if not live[cwd] then cache[cwd] = nil end end
	local freshModel = grouping.build(panes, cx.session:tabs(), cx.sessions:list(), host, roots)
	model = freshModel
	local validKeys: { [string]: boolean } = {}
	for _, session in freshModel.sessions do
		for _, project in session.projects do
			token(project.key)
			validKeys[project.key] = true
		end
	end
	for key in tokens do if not validKeys[key] then tokens[key] = nil end end
	view = sidebar.build(freshModel, folded, tokens)
	for id, action in view.actions do
		if registered[id] ~= action.label then
			registered[id] = action.label
			tern.command({
				id = id, title = "Auto Tab Groups: " .. action.label,
				group = "Auto Tab Groups",
				available = function() return enabled and view.actions[id] ~= nil end,
				run = function(fresh) dispatch(id, fresh) end,
			})
		end
	end
	local nextSignature = tern.json.encode(view.segments)
	if nextSignature ~= signature then
		signature = nextSignature
		tern.chrome.refresh()
	end
end

tern.chrome.status(function()
	return if enabled then view.segments else nil
end)

tern.command({
	id = "toggle", title = "Auto Tab Groups: Toggle Sidebar", icon = "folder",
	keys = { "ctrl+alt+shift+t" },
	run = function(cx)
		tern.kv.set("enabled", not enabled)
		update(cx)
	end,
})
tern.command({
	id = "refresh", title = "Auto Tab Groups: Refresh Projects", icon = "folder",
	available = function() return enabled end,
	run = function(cx) invalidate(); update(cx) end,
})

local function navigate(cx: WindowCx, direction: number): boolean
	update(cx)
	local current = model
	local focused = cx.session:focused()
	if not enabled or not current or not focused then return false end
	local first: number? = nil
	local last: number? = nil
	local target: number? = nil
	local found = false
	for _, session in current.sessions do
		if session.id == 0 then continue end
		for _, project in session.projects do
			for _, pane in project.panes do
				if pane.parked then continue end
				if first == nil then first = pane.pane end
				if pane.pane == focused then
					found = true
					if direction < 0 then target = last end
				elseif found and direction > 0 and target == nil then
					target = pane.pane
				end
				last = pane.pane
			end
		end
	end
	if not found then return false end
	if target == nil then target = if direction < 0 then last else first end
	if target and target ~= focused then cx.layout:focus(target) end
	return true
end

tern.override("previous_tab", function(cx) return navigate(cx, -1) end)
tern.override("next_tab", function(cx) return navigate(cx, 1) end)


for _, event in { "focus", "pane_created", "pane_closed", "tab_created", "tab_closed", "command_started", "cwd", "title" } do
	tern.on(event, function(_, cx: WindowCx?)
		if not cx or cx.session:focused() == nil then showNative() end
		schedule()
	end)
end
tern.on("command_finished", function()
	-- A command can create/remove a repository above another pane's cwd.
	invalidate()
	schedule()
end)

local function tick(cx: WindowCx?)
	if cx then update(cx) else showNative() end
	tern.timer(1000, tick)
end
tern.timer(0, tick)
