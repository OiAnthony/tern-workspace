--!strict

tern.command({
	id = "hello",
	title = "Say hello",
	icon = "sparkle",
	run = function(cx)
		cx:toast("info", "Hello from " .. tern.plugin.name)
	end,
})
