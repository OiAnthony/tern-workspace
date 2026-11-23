--!strict

export type Record = {
	auto_name: string?,
	manual: boolean,
	pending_name: string?,
}

export type SessionSnapshot = {
	id: number,
	host: number,
	locked: boolean,
	tabs: number,
}

export type TabSnapshot = {
	id: number,
	session: number,
}

export type PaneSnapshot = {
	pane: number,
	tab: number?,
	parked: boolean?,
}

export type LifecycleState = {
	populated: { [number]: boolean },
	pane_sessions: { [number]: number },
}

local function basename(path: string): string?
	if path == "" then
		return nil
	end

	local trimmed = path:gsub("[/\\]+$", "")
	if trimmed == "" then
		return "root"
	end

	local name = trimmed:match("([^/\\]+)$")
	if name == nil or name == "" then
		return "root"
	end
	return name
end

local function observe(record: Record, current_name: string, target_name: string?): (Record, string?)
	local next_record: Record = {
		auto_name = record.auto_name,
		manual = record.manual,
		pending_name = record.pending_name,
	}
	if next_record.manual then
		return next_record, nil
	end

	if next_record.pending_name ~= nil then
		if current_name == next_record.pending_name then
			next_record.auto_name = next_record.pending_name
			next_record.pending_name = nil
			return next_record, nil
		end
		if current_name ~= next_record.auto_name then
			next_record.manual = true
			next_record.pending_name = nil
			return next_record, nil
		end
		return next_record, next_record.pending_name
	end

	if target_name == nil then
		return next_record, nil
	end

	if next_record.auto_name == nil then
		next_record.auto_name = target_name
		if current_name == target_name then
			return next_record, nil
		end
		return next_record, target_name
	end

	if current_name ~= next_record.auto_name then
		next_record.manual = true
		return next_record, nil
	end

	if current_name == target_name then
		return next_record, nil
	end

	next_record.auto_name = target_name
	return next_record, target_name
end

local function new_lifecycle_state(): LifecycleState
	return {
		populated = {},
		pane_sessions = {},
	}
end

local function observe_layout(
	state: LifecycleState,
	sessions: { SessionSnapshot },
	tabs: { TabSnapshot },
	panes: { PaneSnapshot }
)
	local active_sessions: { [number]: boolean } = {}
	for _, session in sessions do
		active_sessions[session.id] = true
		if session.tabs > 0 then
			state.populated[session.id] = true
		end
	end

	for session_id in state.populated do
		if not active_sessions[session_id] then
			state.populated[session_id] = nil
		end
	end

	local tab_sessions: { [number]: number } = {}
	for _, tab in tabs do
		tab_sessions[tab.id] = tab.session
	end

	local active_panes: { [number]: boolean } = {}
	for _, pane in panes do
		active_panes[pane.pane] = true
		if pane.tab ~= nil then
			local owner = tab_sessions[pane.tab]
			if owner ~= nil then
				state.pane_sessions[pane.pane] = owner
				state.populated[owner] = true
			end
		else
			local owner = state.pane_sessions[pane.pane]
			if owner ~= nil and active_sessions[owner] then
				state.populated[owner] = true
			end
		end
	end

	for pane_id in state.pane_sessions do
		if not active_panes[pane_id] then
			state.pane_sessions[pane_id] = nil
		end
	end
end

local function sessions_to_close(
	state: LifecycleState,
	sessions: { SessionSnapshot },
	panes: { PaneSnapshot }
): { number }
	local host_counts: { [number]: number } = {}
	for _, session in sessions do
		host_counts[session.host] = (host_counts[session.host] or 0) + 1
	end

	local parked_by_session: { [number]: number } = {}
	local unknown_parked = 0
	for _, pane in panes do
		if pane.parked == true then
			local owner = state.pane_sessions[pane.pane]
			if owner ~= nil then
				parked_by_session[owner] = (parked_by_session[owner] or 0) + 1
			else
				unknown_parked += 1
			end
		end
	end

	if unknown_parked > 0 then
		return {}
	end

	local to_close: { number } = {}
	for _, session in sessions do
		local remaining = host_counts[session.host] or 0
		if
			session.tabs == 0
			and not session.locked
			and state.populated[session.id] == true
			and remaining > 1
			and (parked_by_session[session.id] or 0) == 0
		then
			table.insert(to_close, session.id)
			host_counts[session.host] = remaining - 1
		end
	end

	return to_close
end

local function forget_session(state: LifecycleState, session_id: number)
	state.populated[session_id] = nil
	for pane_id, owner in state.pane_sessions do
		if owner == session_id then
			state.pane_sessions[pane_id] = nil
		end
	end
end

return {
	basename = basename,
	observe = observe,
	new_lifecycle_state = new_lifecycle_state,
	observe_layout = observe_layout,
	sessions_to_close = sessions_to_close,
	forget_session = forget_session,
}
