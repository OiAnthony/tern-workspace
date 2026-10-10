--!strict

local model = require("./model")

local execute = {}

local function trim(value: string): string
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function quote_posix(value: string): string
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function posix_shell(): string?
	if tern.runtime.os ~= "macos" and tern.runtime.os ~= "linux" then
		return nil
	end
	local shell = tern.getenv("SHELL")
	if shell == nil then
		return nil
	end
	local basename = shell:match("([^/]+)$")
	if basename == "sh" or basename == "bash" or basename == "zsh" or basename == "dash" or basename == "ksh" then
		return shell
	end
	return nil
end

local function shell_command(action: model.Action): (string?, string?)
	if posix_shell() == nil then
		return nil, "Configured shell is unsupported; use sh, bash, zsh, dash, or ksh"
	end
	if action.shell then
		if action.command == "" then
			return nil, "Shell command is empty"
		end
		if action.command:find("%z") ~= nil then
			return nil, "Shell command contains a NUL byte"
		end
		return action.command, nil
	end

	if action.program == "" then
		return nil, "Program is empty"
	end
	if action.program:find("%z") ~= nil then
		return nil, "Program contains a NUL byte"
	end
	local parts = { quote_posix(action.program) }
	for _, arg in action.args do
		if arg:find("%z") ~= nil then
			return nil, "Argument contains a NUL byte"
		end
		table.insert(parts, quote_posix(arg))
	end
	return "exec " .. table.concat(parts, " "), nil
end

local function source(cx: WindowCx, source_id: number?): (PaneInfo?, string?)
	local id = source_id or cx.session:focused()
	if id == nil then
		return nil, "No source pane is available"
	end
	local pane = cx.session:pane(id)
	if pane == nil then
		return nil, "Source pane no longer exists"
	end
	return pane, nil
end

local function local_host(cx: WindowCx, source_id: number): (string?, string?)
	local ok, host = pcall(function()
		return cx.hosts:current()
	end)
	if not ok or host == nil then
		return nil, "Could not determine the current host"
	end
	if host.kind ~= "local" then
		return nil, "Shortcut Manager supports local hosts only"
	end
	local listed_ok, hosts = pcall(function()
		return cx.hosts:list()
	end)
	if not listed_ok then
		return nil, "Could not verify source pane host membership"
	end
	for _, listed_host in hosts do
		if listed_host.id == host.id and listed_host.kind == "local" then
			for _, pane_id in listed_host.panes do
				if pane_id == source_id then
					return tostring(host.id) .. ":" .. host.name, nil
				end
			end
		end
	end
	return nil, "Source pane is not on the current local host"
end

local function valid_directory(path: string): boolean
	if path == "" then
		return false
	end
	local ok = pcall(function()
		tern.fs.list(path)
	end)
	return ok
end

local function resolve_cwd(action: model.Action, source_pane: PaneInfo?): (string?, string?)
	local cwd = if action.cwd_mode == "fixed" then action.cwd else (if source_pane then source_pane.cwd else nil)
	if cwd == nil or cwd == "" then
		return nil, if action.cwd_mode == "fixed" then "Fixed working directory is empty" else "Source pane has no working directory"
	end
	if not valid_directory(cwd) then
		return nil, "Working directory does not exist: " .. cwd
	end
	return cwd, nil
end

local function instance_directory(action_id: string): string
	return tern.plugin.data .. "/instances/" .. action_id
end

local function instance_path(action_id: string, pane: number): string
	return instance_directory(action_id) .. "/" .. tostring(pane) .. ".json"
end

local function load_instances(action_id: string, host: string, cwd: string): { { pane: number, program: string? } }
	local records: { { pane: number, program: string? } } = {}
	local ok, names = pcall(function()
		return tern.fs.list(instance_directory(action_id))
	end)
	if not ok then
		return records
	end
	for _, name in names do
		if name:match("^%d+%.json$") ~= nil then
			local read_ok, text = pcall(function()
				return tern.fs.read(instance_directory(action_id) .. "/" .. name, 65536)
			end)
			if read_ok then
				local decode_ok, record = pcall(function()
					return tern.json.decode(text)
				end)
				if decode_ok and type(record) == "table" and record.action == action_id and record.host == host and record.cwd == cwd and type(record.pane) == "number" then
					table.insert(records, { pane = record.pane, program = if type(record.program) == "string" then record.program else nil })
				end
			end
		end
	end
	return records
end

local function save_instance(action_id: string, host: string, cwd: string, pane: number, program: string?): (boolean, string?)
	local ok, err = pcall(function()
		tern.fs.mkdir(instance_directory(action_id))
		tern.fs.write(instance_path(action_id, pane), tern.json.encode({ version = 1, action = action_id, host = host, cwd = cwd, pane = pane, program = program }))
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

local function reusable_pane(cx: WindowCx, id: number, cwd: string, expected_program: string?): (PaneInfo?, string?)
	local pane = cx.session:pane(id)
	if pane == nil then
		return nil, "Reusable pane was closed"
	end
	if pane.kind ~= "terminal" and pane.kind ~= "agent" then
		return nil, "Reusable pane is no longer a terminal"
	end
	if pane.exited ~= nil then
		return nil, "Reusable pane's shell exited"
	end
	if expected_program ~= nil and pane.program ~= expected_program then
		return nil, "Reusable pane program changed"
	end
	if pane.cwd ~= nil and pane.cwd ~= "" and pane.cwd ~= cwd then
		return nil, "Reusable pane working directory changed"
	end
	return pane, nil
end

local function notify_completion(cx: WindowCx, result: ProcessResult, action_title: string)
	if result.status == 0 and not result.timed_out then
		cx:toast("success", action_title .. " completed")
		return
	end
	local details = trim(result.stderr)
	if details == "" then
		details = trim(result.stdout)
	end
	if result.timed_out then
		details = if details == "" then "Process timed out" else "Process timed out: " .. details
	else
		details = if details == "" then "Exit status " .. tostring(result.status) else "Exit status " .. tostring(result.status) .. ": " .. details
	end
	cx:toast("error", action_title .. " failed", details)
end

local function launch_background(action: model.Action, cwd: string): (boolean, string)
	local argv: { string }
	if action.shell then
		local shell = posix_shell()
		if shell == nil then
			return false, "Configured shell is unsupported; use sh, bash, zsh, dash, or ksh"
		end
		if action.command == "" then
			return false, "Shell command is empty"
		end
		if action.command:find("%z") ~= nil then
			return false, "Shell command contains a NUL byte"
		end
		argv = { shell, "-lc", action.command }
	else
		if action.program == "" then
			return false, "Program is empty"
		end
		argv = { action.program }
		for _, arg in action.args do
			if arg:find("%z") ~= nil then
				return false, "Argument contains a NUL byte"
			end
			table.insert(argv, arg)
		end
		-- GUI launches inherit a minimal PATH; resolve bare names in the user's login shell.
		-- Positional parameters preserve argv without interpreting user input as shell syntax.
		if not action.program:find("/", 1, true) then
			local shell = posix_shell()
			if shell == nil then
				return false, "Configured shell is unsupported; use sh, bash, zsh, dash, or ksh"
			end
			local resolved: { string } = { shell, "-lc", 'exec "$@"', "shortcut-manager" }
			for _, arg in argv do table.insert(resolved, arg) end
			argv = resolved
		end
	end

	local ok, err = pcall(function()
		tern.process.run(argv, { cwd = cwd }, function(result, callback_cx)
			if callback_cx ~= nil then
				notify_completion(callback_cx, result, action.title)
			end
		end)
	end)
	if not ok then
		return false, "Could not start process: " .. tostring(err)
	end
	return true, "Started in background"
end

local function launch_terminal(action: model.Action, cx: WindowCx, source_id: number, cwd: string, host: string): (boolean, string)
	local command, command_error = shell_command(action)
	if command == nil then
		return false, command_error or "Invalid command"
	end

	if action.reuse then
		for _, record in load_instances(action.id, host, cwd) do
			local existing = reusable_pane(cx, record.pane, cwd, record.program)
			if existing ~= nil then
				if action.focus then
					local focused, focus_error = pcall(function() cx.layout:focus(record.pane) end)
					if not focused then return false, "Could not focus reusable pane: " .. tostring(focus_error) end
				end
				return true, "Reused existing pane"
			end
		end
	end

	local reveal = { focus = action.focus }
	local launch = { cwd = cwd, command = command }
	local pane_id: number? = nil
	local ok, result = pcall(function()
		if action.mode == "tab" then
			pane_id = cx.layout:new_tab(launch, reveal)
		else
			pane_id = cx.layout:split(source_id, action.direction, launch, reveal)
		end
	end)
	if not ok then
		return false, "Could not launch terminal: " .. tostring(result)
	end
	if pane_id == nil then
		return false, "Tern did not create a terminal pane"
	end
	local pane_info = cx.session:pane(pane_id)
	local startup_error = if pane_info then pane_info.error else nil
	local persisted, persist_error = true, nil
	if action.reuse then
		persisted, persist_error = save_instance(action.id, host, cwd, pane_id, if pane_info then pane_info.program else nil)
	end
	if action.mode == "float" then
		local float_ok, float_result, float_err = pcall(function()
			return cx.layout:float(pane_id :: number, source_id, action.corner, reveal)
		end)
		if not float_ok or float_result ~= true then
			local reason = if not float_ok then tostring(float_result) else (float_err or "Tern could not float the pane")
			local message = "Terminal launched in split, but floating failed: " .. reason
			if not persisted then
				message ..= "; could not persist reusable pane: " .. tostring(persist_error)
			end
			if startup_error ~= nil then
				message ..= "; terminal startup error: " .. startup_error
			end
			cx:toast("error", action.title, message)
			return true, message
		end
		if action.focus then
			local focused, focus_error = pcall(function() cx.layout:focus(pane_id :: number) end)
			if not focused then
				local message = "Floating terminal launched, but focus failed: " .. tostring(focus_error)
				cx:toast("error", action.title, message)
				return true, message
			end
		end
	end
	if not persisted then
		local message = "Launched, but reusable pane could not be persisted: " .. tostring(persist_error)
		if startup_error ~= nil then
			message ..= "; terminal startup error: " .. startup_error
		end
		cx:toast("error", action.title, message)
		return true, message
	end
	local message = if action.mode == "tab" then "Launched in new tab" elseif action.mode == "float" then "Launched in floating pane" else "Launched in split pane"
	if startup_error ~= nil then
		message ..= "; terminal startup error: " .. startup_error
		cx:toast("error", action.title, message)
	end
	return true, message
end

function execute.source(cx: WindowCx, id: number?): (PaneInfo?, string?)
	return source(cx, id)
end

function execute.run(action: model.Action, cx: WindowCx, source_id: number?): (boolean, string)
	if action.kind == "tern" then
		if action.tern_action == "" then
			return false, "Native Tern action is empty"
		end
		local ok, err = pcall(function()
			cx:action(action.tern_action)
		end)
		if not ok then
			return false, "Could not dispatch native action: " .. tostring(err)
		end
		return true, "Dispatched native action"
	end

	local source_pane, source_error = source(cx, source_id)
	if source_error ~= nil then
		return false, source_error
	end
	if source_pane == nil then
		return false, "No source pane is available"
	end
	local host, host_error = local_host(cx, source_pane.pane)
	if host == nil then
		return false, host_error or "Shortcut Manager supports local hosts only"
	end
	local cwd, cwd_error = resolve_cwd(action, source_pane)
	if cwd == nil then
		return false, cwd_error or "Working directory is invalid"
	end
	if action.mode == "background" then
		if action.reuse then
			return false, "Background actions cannot reuse a pane"
		end
		return launch_background(action, cwd)
	end
	return launch_terminal(action, cx, source_pane.pane, cwd, host)
end

return execute
