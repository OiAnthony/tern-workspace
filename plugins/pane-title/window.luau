--!strict

local sheet = tern.fs.read("styles.css")
if tern.kv.get("enabled") ~= false then tern.css("title-layout", sheet) end

tern.command({
	id = "toggle", title = "Pane Title: Toggle", icon = "text",
	run = function()
		local enabled = tern.kv.get("enabled") == false
		tern.kv.set("enabled", enabled)
		tern.css("title-layout", if enabled then sheet else "")
	end,
})
