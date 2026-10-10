--!strict

export type Root = { cwd: string, root: string? }
export type Project = { key: string, path: string, label: string, kind: string, panes: { PaneInfo }, count: number }
export type SessionGroup = { key: string, id: number, name: string, current: boolean, projects: { Project } }
export type Model = { host: number, sessions: { SessionGroup }, count: number }

local grouping = {}

local function normalized(path: string): string
	while #path > 1 and path:match("[/\\]$") and not path:match("^%a:[/\\]$") do
		path = path:sub(1, -2)
	end
	return path
end

local function dirname(path: string): string
	local clean = normalized(path)
	local slash = clean:match("^.*()[/\\]")
	if slash == nil then return "" end
	if slash == 1 or (slash == 3 and clean:match("^%a:")) then return clean:sub(1, slash) end
	return clean:sub(1, slash - 1)
end

function grouping.directory(pane: PaneInfo): string
	if pane.path ~= nil and (pane.path:match("^[/\\]") or pane.path:match("^%a:[/\\]")) then
		return if pane.kind == "git" then normalized(pane.path) else dirname(pane.path)
	end
	if pane.cwd ~= nil and pane.cwd ~= "" then
		return normalized(pane.cwd)
	end
	return ""
end

local function encode(value: string): string
	return tostring(#value) .. ":" .. value
end

local function idstr(value: number): string
	return tostring(value)
end

local function basename(path: string): string
	if path == "" or path == "/" then return path end
	local slash = path:match("^.*()[/\\]")
	return if slash == nil then path else path:sub(slash + 1)
end


local function project_key(host: number, session: number, kind: string, path: string): string
	return "p" .. encode(idstr(host)) .. encode(idstr(session)) .. encode(kind) .. encode(path)
end

local function session_key(host: number, session: number): string
	return "s" .. encode(idstr(host)) .. encode(idstr(session))
end


local function project_label(path: string): string
	if path == "" then return "Unknown" end
	if path == "/" then return "/" end
	return basename(path)
end

function grouping.build(panes: { PaneInfo }, tabs: { TabInfo }, sessions: { ManagedSession }, host: ManagedHost, roots: { [number]: Root }): Model
	local tab_by_id: { [number]: TabInfo } = {}
	for _, tab in tabs do tab_by_id[tab.id] = tab end

	local host_panes: { [number]: boolean } = {}
	for _, id in host.panes do host_panes[id] = true end
	local session_by_id: { [number]: ManagedSession } = {}
	local session_groups: { [number]: SessionGroup } = {}
	local result_sessions: { SessionGroup } = {}
	for _, session in sessions do
		if session.host == host.id and session.id ~= 0 then
			session_by_id[session.id] = session
			if session_groups[session.id] == nil then
				local group: SessionGroup = { key = session_key(host.id, session.id), id = session.id, name = session.name, current = session.current, projects = {} }
				session_groups[session.id] = group
				table.insert(result_sessions, group)
			end
		end
	end

	local pane_order: { PaneInfo } = {}
	for _, pane in panes do table.insert(pane_order, pane) end
	table.sort(pane_order, function(a: PaneInfo, b: PaneInfo): boolean return a.pane < b.pane end)
	local project_groups: { [string]: Project } = {}
	local total_count = 0
	for _, pane in pane_order do
		if not host_panes[pane.pane] then continue end
		local tab = if pane.tab == nil then nil else tab_by_id[pane.tab]
		local parked = pane.parked == true or tab == nil
		local session_id = if parked then 0 else (tab :: TabInfo).session
		local session_group = session_groups[session_id]
		if session_group == nil then
			local session = session_by_id[session_id]
			local name = if parked then "Parked" elseif session ~= nil then session.name else "Session " .. idstr(session_id)
			local current = if parked then false elseif session ~= nil then session.current else false
			session_group = { key = session_key(host.id, session_id), id = session_id, name = name, current = current, projects = {} }
			session_groups[session_id] = session_group
			table.insert(result_sessions, session_group)
		end

		local directory = grouping.directory(pane)
		local root = roots[pane.pane]
        local trusted_root = root ~= nil and normalized(root.cwd) == directory and root.root ~= nil and root.root ~= ""
		local path = if trusted_root then normalized(root.root :: string) else directory
		local kind = if trusted_root then "git" elseif directory ~= "" then "cwd" else "unknown"
		local p_key = project_key(host.id, session_id, kind, path)
		local project = project_groups[p_key]
		if project == nil then
			project = { key = p_key, path = path, label = project_label(path), kind = kind, panes = {}, count = 0 }
			project_groups[p_key] = project
			table.insert(session_group.projects, project)
		end
		project.count += 1
		total_count += 1
		table.insert(project.panes, pane)
end

	-- Prefer a unique parent name; retain full paths when short names remain ambiguous.
	for _, session_group in result_sessions do
            local labels: { [string]: number } = {}
            local paths: { [string]: number } = {}
			local qualifiers: { [string]: number } = {}
            for _, project in session_group.projects do
                labels[project.label] = (labels[project.label] or 0) + 1
                paths[project.path] = (paths[project.path] or 0) + 1
				local qualifier = encode(project.label) .. encode(basename(dirname(project.path)))
				qualifiers[qualifier] = (qualifiers[qualifier] or 0) + 1
            end
            for _, project in session_group.projects do
                if labels[project.label] > 1 then
					local parent = basename(dirname(project.path))
					local qualifier = encode(project.label) .. encode(parent)
					local suffix = if parent ~= "" and qualifiers[qualifier] == 1 then parent else project.path
					project.label ..= " — " .. suffix
                    if paths[project.path] > 1 then project.label ..= " [" .. project.kind .. "]" end
                end
            end
            table.sort(session_group.projects, function(a: Project, b: Project): boolean
                local al = string.lower(a.label)
                local bl = string.lower(b.label)
                if al ~= bl then return al < bl end
                if a.path ~= b.path then return a.path < b.path end
                return a.kind < b.kind
            end)
        end

	table.sort(result_sessions, function(a: SessionGroup, b: SessionGroup): boolean return a.id < b.id end)
	return { host = host.id, sessions = result_sessions, count = total_count }
end

return grouping
