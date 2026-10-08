--!strict

local function focused_pane(cx: WindowCx): PaneInfo?
	local id = cx.session:focused()
	if id == nil then
		return nil
	end
	return cx.session:pane(id)
end

local function trim(value: string): string
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function web_url(remote: string): string?
	local url = trim(remote)
	url = url:gsub("%.git/?$", "")
	url = url:gsub("/+$", "")

	if url:match("^https?://") then
		return url
	end

	local host, path = url:match("^ssh://[^/]+@([^/]+)/(.+)$")
	if host ~= nil and path ~= nil then
		return "https://" .. host .. "/" .. path
	end

	host, path = url:match("^[^@]+@([^:]+):(.+)$")
	if host ~= nil and path ~= nil then
		return "https://" .. host .. "/" .. path
	end

	host, path = url:match("^git://([^/]+)/(.+)$")
	if host ~= nil and path ~= nil then
		return "https://" .. host .. "/" .. path
	end

	return nil
end

local is_repository = false
local repository_generation = 0

local function refresh_repository(cx: WindowCx?)
	repository_generation += 1
	local generation = repository_generation
	is_repository = false
	if cx == nil then
		return
	end
	local pane = focused_pane(cx)
	if pane == nil or pane.cwd == nil or pane.cwd == "" then
		return
	end
	cx.git:repo(pane.pane):next(function(repo, err)
		if generation == repository_generation then
			is_repository = repo ~= nil and err == nil
		end
	end)
end

tern.timer(0, refresh_repository)
tern.on("focus", function(_, cx)
	refresh_repository(cx)
end)
tern.on("pane_closed", function(_, cx)
	refresh_repository(cx)
end)
tern.on("cwd", function(_, cx)
	refresh_repository(cx)
end)
tern.on("command_finished", function(_, cx)
	refresh_repository(cx)
end)

local browser_key = "browser"

tern.command({
	id = "toggle-browser",
	title = "Git Open: Toggle Browser",
	icon = "link",
	group = "Git",
	run = function(cx)
		local use_system = tern.kv.get(browser_key) ~= "system"
		tern.kv.set(browser_key, if use_system then "system" else "builtin")
		cx:toast("info", if use_system then "Git Open: System default browser" else "Git Open: Built-in browser")
	end,
})

tern.command({
	id = "open",
	title = "Git Open: Open in GitHub",
	icon = "link",
	group = "Git",
	available = function()
		return is_repository
	end,
	run = function(cx)
		local pane = focused_pane(cx)
		if pane == nil or pane.cwd == nil or pane.cwd == "" then
			cx:toast("error", "No focused repository")
			return
		end

		tern.process.run({ "git", "remote", "get-url", "origin" }, { cwd = pane.cwd, timeout_ms = 2000 }, function(result, callback_cx)
			if callback_cx == nil then
				return
			end
			if result.status ~= 0 then
				callback_cx:toast("error", "No Git remote named origin", trim(result.stderr))
				return
			end

			local url = web_url(result.stdout)
			if url == nil then
				callback_cx:toast("error", "Unsupported Git remote URL", trim(result.stdout))
				return
			end

			if tern.kv.get(browser_key) ~= "system" then
				callback_cx:open(url)
				return
			end

			local opener = if tern.runtime.os == "macos" then "open"
				elseif tern.runtime.os == "linux" then "xdg-open"
				elseif tern.runtime.os == "windows" then "explorer.exe"
				else nil
			if opener == nil then
				callback_cx:toast("error", "System browser is unavailable on this platform")
				return
			end
			tern.process.run({ opener, url }, { timeout_ms = 5000 }, function(open_result, open_cx)
				if open_result.status ~= 0 and open_cx ~= nil then
					open_cx:toast("error", "Could not open system browser", trim(open_result.stderr))
				end
			end)
		end)
	end,
})
