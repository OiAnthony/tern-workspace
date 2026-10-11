--!strict

local grouping = require("./grouping")
local sidebar = {}

export type Action = { kind: string, key: string?, pane: number?, session: number?, label: string }
export type View = { segments: { StatusSegment }, actions: { [string]: Action } }

local function text(value: string?): string
	return if value == nil or value == "" then "" else value
end

local function add_row(view: View, label: string, tone: string, command: string?)
	table.insert(view.segments, { text = label, tone = tone, command = command })
end
local function add_info(view: View, label: string, tone: string)
	table.insert(view.segments, { text = label, tone = tone })
end

local function action(view: View, id: string, value: Action)
	view.actions[id] = value
end


local function pane_label(pane: PaneInfo): string
	local title = text(pane.title)
	local fallback = text(pane.program)
	if fallback == "" then fallback = text(pane.kind) end
	return if title ~= "" then title else if fallback ~= "" then fallback else "Pane " .. tostring(pane.pane)
end


local function pane_tone(pane: PaneInfo, parked: boolean): string
	local tone = "atg-pane"
	if parked then tone ..= " atg-parked" elseif pane.focused then tone ..= " atg-focused" end
	-- Tern clears alert when the pane is seen. Prompt/exit metadata is not an unread mark.
	if pane.busy == true then tone ..= " atg-busy" end
	if pane.alert then tone ..= " atg-alert" end
	if pane.floating then tone ..= " atg-floating" end
	return tone
end

local function render_project(view: View, project: grouping.Project, folded: { [string]: boolean }, tokens: { [string]: number }, parked: boolean)
	local project_token = tokens[project.key]
	if project_token == nil then return end
	local id = "group-" .. tostring(project_token)
	local is_folded = folded[project.key] == true
	local command = "plugin.auto-tab-groups." .. id
	action(view, id, { kind = "fold", key = project.key, label = "Toggle project: " .. project.label })
	add_row(view, project.label, if is_folded then "atg-group atg-folded" else "atg-group", command)

	local children_visible = not is_folded
	for _, pane in project.panes do
		local pane_id = "pane-" .. tostring(pane.pane)
		local pane_command: string? = nil
		if not pane.parked and not parked then
			pane_command = "plugin.auto-tab-groups." .. pane_id
			action(view, pane_id, { kind = "focus", pane = pane.pane, label = "Focus pane " .. tostring(pane.pane) .. ": " .. pane_label(pane) .. " — " .. project.label })
		end
		if children_visible then
			table.insert(view.segments, {
				text = pane_label(pane),
				tone = pane_tone(pane, pane.parked == true or parked),
				command = pane_command,
			})
		end
	end
end

function sidebar.build(model: grouping.Model, folded: { [string]: boolean }, tokens: { [string]: number }): View
	local view: View = { segments = {}, actions = {} }
	for index, session in model.sessions do
			local tone = if index == 1 then "atg-session" else "atg-session-separated"
			local session_id = "session-" .. tostring(model.host) .. "-" .. tostring(session.id)
			local session_label = session.name
			local session_command = "plugin.auto-tab-groups." .. session_id
			if session.id == 0 then
				add_info(view, session_label, tone)
			else
				action(view, session_id, { kind = "session", session = session.id, label = "Switch session: " .. session.name })
				add_row(view, session_label, tone, session_command)
			end
			for _, project in session.projects do
				render_project(view, project, folded, tokens, session.id == 0)
			end
	end
	return view
end

return sidebar
