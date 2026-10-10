--!strict

export type Action = {
	id: string, title: string, enabled: boolean, chord: string,
	kind: string, program: string, args: { string }, shell: boolean, command: string,
	mode: string, cwd_mode: string, cwd: string, direction: "right" | "down" | "left" | "up", corner: "tl" | "tr" | "bl" | "br" | "fullscreen",
	focus: boolean, reuse: boolean, tern_action: string,
}
export type Binding = { action: string, previous: any, had_previous: boolean }
export type Config = { revision: number, actions: { Action }, bindings: { [string]: Binding } }

local model = {}

function model.clone(value: any): any
	return tern.json.decode(tern.json.encode(value))
end

function model.action_name(id: string): string
	return "plugin.shortcut-manager." .. id
end

function model.new_action(preset: string?): Action
	local action: Action = {
		id = "action-" .. tostring(math.random(10000000, 99999999)),
		title = "新建动作", enabled = true, chord = "", kind = "process",
		program = "", args = {}, shell = false, command = "", mode = "background",
		cwd_mode = "source", cwd = "", direction = "right", corner = "br",
		focus = true, reuse = false, tern_action = "",
	}
	if preset == "vscode" or preset == "zed" or preset == "idea" then
		action.id = preset
		action.program = if preset == "vscode" then "code" else preset
		action.title = "用 " .. (if preset == "vscode" then "VS Code" elseif preset == "zed" then "Zed" else "IDEA") .. " 打开目录"
		action.args = { "." }
		action.chord = if preset == "vscode" then "ctrl+b>c" elseif preset == "zed" then "ctrl+b>z" else "ctrl+b>i"
	elseif preset == "lazygit" or preset == "lazydocker" then
		action.id = preset
		action.title = if preset == "lazygit" then "Lazygit" else "Lazydocker"
		action.program = preset
		action.mode = if preset == "lazygit" then "tab" else "float"
		action.chord = if preset == "lazygit" then "ctrl+b>l" else "ctrl+b>d"
		action.reuse = true
	end
	return action
end

function model.defaults(): Config
	return {
		revision = 0,
		actions = { model.new_action("vscode"), model.new_action("zed"), model.new_action("idea"), model.new_action("lazygit"), model.new_action("lazydocker") },
		bindings = {},
	}
end

local modifiers = { ctrl = "ctrl", alt = "alt", opt = "alt", shift = "shift", cmd = "cmd", super = "cmd" }
local modifier_order = { "ctrl", "alt", "shift", "cmd" }
local named_keys: { [string]: boolean } = {}
for _, name in { "enter", "return", "tab", "backspace", "escape", "esc", "space", "up", "down", "left", "right", "home", "end", "pageup", "pagedown", "page_up", "page_down", "insert", "delete", "caps_lock", "menu", "print_screen", "pause", "scroll_lock" } do
	named_keys[name] = true
end
for n = 1, 35 do named_keys["f" .. tostring(n)] = true end

function model.chord(text: string): (string?, string?)
	local value = text:lower():gsub("%s+", "")
	if value == "" then return "", nil end
	local result = {}
	for _, step in string.split(value, ">") do
		if step == "" then return nil, "快捷键序列不能包含空步骤" end
		local parts = string.split(step, "+")
		local key = parts[#parts]
		local mods: { [string]: boolean } = {}
		for i = 1, #parts - 1 do
			local name = modifiers[parts[i]]
			if name == nil or mods[name] then return nil, "无效或重复的快捷键修饰键" end
			mods[name] = true
		end
		if key == "esc" then key = "escape" elseif key == "return" then key = "enter" end
		if key == "pageup" then key = "page_up" elseif key == "pagedown" then key = "page_down" end
		if not (utf8.len(key) == 1 or named_keys[key] or modifiers[key]) then return nil, "无效按键：" .. key end
		if modifiers[key] then
			if #parts ~= 1 or not value:find(">", 1, true) then return nil, "单独修饰键仅支持按键序列" end
			key = modifiers[key]
		end
		local spell = {}
		for _, name in modifier_order do if mods[name] then table.insert(spell, name) end end
		table.insert(spell, key)
		table.insert(result, table.concat(spell, "+"))
	end
	return table.concat(result, ">"), nil
end

local function choice(value: string, choices: { string }): boolean
	return table.find(choices, value) ~= nil
end

function model.validate(raw: any): (Action?, string?)
	if type(raw) ~= "table" then return nil, "动作必须是对象" end
	for _, key in { "id", "title", "chord", "kind", "program", "command", "mode", "cwd_mode", "cwd", "direction", "corner", "tern_action" } do
		if type(raw[key]) ~= "string" then return nil, "字段必须是文本：" .. key end
		if raw[key]:find("\0", 1, true) then return nil, "字段不能包含 NUL：" .. key end
	end
	for _, key in { "enabled", "shell", "focus", "reuse" } do
		if type(raw[key]) ~= "boolean" then return nil, "字段必须是布尔值：" .. key end
	end
	if not raw.id:match("^[a-z][a-z0-9%-]*$") or #raw.id > 32 or raw.id == "manage" or raw.id:match("^manager%-") then return nil, "动作 ID 必须以小写字母开头，最长 32 字符；manage 和 manager- 前缀保留给管理命令" end
	if raw.title:match("^%s*$") then return nil, "请填写动作名称" end
	if not choice(raw.kind, { "process", "tern" }) or not choice(raw.mode, { "background", "pane", "tab", "float" })
		or not choice(raw.cwd_mode, { "source", "fixed" }) or not choice(raw.direction, { "right", "down", "left", "up" })
		or not choice(raw.corner, { "tl", "tr", "bl", "br", "fullscreen" }) then return nil, "动作选项无效" end
	if type(raw.args) ~= "table" then return nil, "参数必须是列表" end
	for index, argument in raw.args do
		if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #raw.args or type(argument) ~= "string" or argument:find("\0", 1, true) then
			return nil, "参数必须是连续的文本列表，不能包含 NUL"
		end
	end
	if raw.kind == "tern" then
		if raw.tern_action:match("^%s*$") then return nil, "请选择 Tern 动作" end
		if raw.tern_action:match("^plugin%.shortcut%-manager%.") then return nil, "不能调用本插件动作，以免递归执行" end
	elseif raw.shell then
		if raw.command:match("^%s*$") then return nil, "请填写 shell 命令" end
	elseif raw.program:match("^%s*$") then return nil, "请填写程序" end
	if raw.kind == "process" and raw.cwd_mode == "fixed" and raw.cwd:sub(1, 1) ~= "/" then return nil, "固定目录必须是绝对路径" end
	if raw.kind == "process" and raw.mode == "background" and raw.reuse then return nil, "后台进程没有可复用终端；请选择 pane、tab 或浮窗" end
	if raw.kind == "process" and raw.mode == "float" and raw.corner == "fullscreen" and not raw.focus then return nil, "全屏浮窗必须切换到终端；离开焦点后会恢复普通浮窗" end
	local chord, err = model.chord(raw.chord)
	if chord == nil then return nil, err end
	local action: Action = model.clone(raw)
	action.chord = chord
	return action, nil
end

function model.validate_config(raw: any): (Config?, string?)
	if type(raw) ~= "table" or type(raw.revision) ~= "number" or raw.revision < 0 or raw.revision % 1 ~= 0 or type(raw.actions) ~= "table" or type(raw.bindings) ~= "table" then
		return nil, "快捷动作配置格式无效"
	end
	local config: Config = { revision = raw.revision, actions = {}, bindings = model.clone(raw.bindings) }
	local ids: { [string]: boolean } = {}
	local chords: { [string]: boolean } = {}
	for _, raw_action in raw.actions do
		local action, err = model.validate(raw_action)
		if action == nil then return nil, err end
		if ids[action.id] then return nil, "重复动作 ID：" .. action.id end
		ids[action.id] = true
		if action.enabled and action.chord ~= "" then
			for chord in chords do
				if chord == action.chord or chord:sub(1, #action.chord + 1) == action.chord .. ">" or action.chord:sub(1, #chord + 1) == chord .. ">" then
					return nil, "本插件快捷键或序列前缀冲突：" .. action.chord .. " / " .. chord
				end
			end
			chords[action.chord] = true
		end
		table.insert(config.actions, action)
	end
	for key, binding in config.bindings do
		if type(key) ~= "string" or type(binding) ~= "table" or type(binding.action) ~= "string" or type(binding.had_previous) ~= "boolean" then return nil, "快捷键归属记录无效" end
	end
	return config, nil
end

function model.load(): Config
	local raw = tern.kv.get("config")
	if raw == nil then return model.defaults() end
	local config, err = model.validate_config(raw)
	if config == nil then error(err or "快捷动作配置无效") end
	return config
end

return model
