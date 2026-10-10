--!strict

local model = require("./lib/model")
local input = require("./lib/input")
local command = require("./lib/command")
local ui = tern.ui

type Action = model.Action
type Config = model.Config
type State = {
	token: string, pane: number, source_id: number?, source_cwd: string, config: Config, baseline: number,
	selected: string?, draft: Action?, delete_id: string?, is_new: boolean, dirty: boolean, search: string,
	status: string, error: string?, inspection: any, confirm_delete: boolean, confirm_discard: boolean,
	pending: string?, pending_preset: string?, field: string, cursor: number, anchor: number?, focus_ready: boolean,
	launch: string, input_error: string?, recording: boolean, recorded: { string }, action_search: string,
}
type Key = { name: string, text: string?, ctrl: boolean, alt: boolean, shift: boolean, meta: boolean }

local function text(state: State, name: string): string
	if name == "search" then return state.search end
	if name == "action_search" then return state.action_search end
	if name == "launch" then return state.launch end
	if name == "chord" and state.recording then return table.concat(state.recorded, ">") end
	if name == "launch_kind" then
		return if state.draft and state.draft.kind == "tern" then "tern" else "process"
	end
	local d = state.draft
	if d == nil then return "" end
	local value = (d :: any)[name]
	if type(value) == "boolean" then return if value then "true" else "false" end
	return if type(value) == "string" then value else ""
end
local function snapshot(state: State): any
	return { token = state.token, pane = state.pane, revision = state.baseline, selected = state.selected,
		action = state.draft, delete_id = state.delete_id, source = state.source_id, source_cwd = state.source_cwd,
		draft = state.draft, actions = state.config.actions, is_new = state.is_new, dirty = state.dirty,
		search = state.search, field = state.field, cursor = state.cursor, anchor = state.anchor, status = state.status,
		launch = state.launch, input_error = state.input_error }
end
local function persist(state: State): () tern.kv.set("draft:" .. state.token, snapshot(state)) end
local function focus(state: State, name: string, cx: BlockCx): ()
	state.field, state.cursor, state.anchor = name, input.units(text(state, name)), nil
	local root = "main.1.1." .. (if state.draft ~= nil and not state.confirm_discard then "body." else "")
	local id = root .. "wrap-" .. name .. ".field-" .. name
	if name == "search" then id = "main.1.0.0.search"
	elseif name == "chord" then id = root .. "shortcut.value.wrap-chord.field-chord"
	elseif name:sub(1, 7) == "choice-" then
		local field = name:sub(8)
		id = root .. "wrap-choice-" .. field .. ".options." .. field .. "-" .. text(state, field)
	elseif name == "button-new" then id = "main.1.0.0." .. name
	elseif name:sub(1, 14) == "button-select-" then id = "main.1.0.1.action-" .. name:sub(15)
	elseif name:sub(1, 14) == "button-preset-" then id = root .. "presets." .. name
	elseif name == "button-record" or name == "button-clear-chord" then id = root .. "shortcut.options." .. name
	elseif name == "button-discard-confirm" or name == "button-discard-cancel" then id = root .. "confirm-actions." .. name
	elseif name == "button-save" or name == "button-cancel" then id = (if state.draft ~= nil and not state.confirm_discard then "main.1.1.heading.form-actions." else root .. "form-actions.") .. name
	elseif name:sub(1, 14) == "button-native-" then id = root .. "catalog." .. name
	elseif name:sub(1, 7) == "button-" then id = root .. name end
	local ops: { any } = { { "reveal", id, "nearest" } }
	if name:sub(1, 7) ~= "button-" and name:sub(1, 7) ~= "choice-" then table.insert(ops, { "focus", id }) end
	cx:frame(ops)
end
local function set_field(state: State, name: string, value: string): ()
	if name == "search" then state.search = value; return end
	if name == "action_search" then state.action_search = value; return end
	local d = state.draft
	if d == nil then return end
	if name == "launch" then
		state.launch = value
		if d.shell then
			d.command, state.input_error = value, nil
		else
			local program, args, err = command.parse(value)
			state.input_error = err
			if program ~= nil and args ~= nil then d.program, d.args = program, tern.json.array(args) :: { string } end
		end
	elseif name == "shell" then
		d.shell = value == "true"
		set_field(state, "launch", state.launch)
	elseif name == "launch_kind" then
		d.kind = value
		state.inspection = nil
	elseif name == "mode" then d.mode = value; if value == "background" then d.reuse = false end
	elseif name == "enabled" or name == "focus" or name == "reuse" then (d :: any)[name] = value == "true"
	else (d :: any)[name] = value end
	if d.mode == "float" and d.corner == "fullscreen" then d.focus = true end
	state.dirty, state.error = true, nil
end
local function show_action(state: State, id: string): ()
	for _, a in state.config.actions do
		if a.id == id then
			state.selected, state.draft, state.delete_id = id, model.clone(a), nil
			state.is_new, state.dirty, state.error, state.inspection, state.confirm_delete = false, false, nil, nil, false
			state.field, state.cursor, state.anchor = "title", input.units(a.title), nil
			state.launch, state.input_error = if a.shell then a.command else command.format(a.program, a.args), nil
			state.recording, state.recorded = false, {}
			state.focus_ready = false
			return
		end
	end
end
local function new_action(state: State, preset: string?): ()
	local a = model.new_action(preset)
	if preset == nil then a.title = "" end
	while true do
		local used = false
		for _, old in state.config.actions do if old.id == a.id then used = true; break end end
		if not used then break end
		a.id = "action-" .. tostring(math.random(10000000, 99999999))
	end
	state.draft, state.selected, state.delete_id, state.is_new, state.dirty = a, nil, nil, true, true
	state.error, state.status, state.inspection, state.confirm_delete = nil, "", nil, false
	state.launch, state.input_error = if a.shell then a.command else command.format(a.program, a.args), nil
	state.recording, state.recorded = false, {}
	state.focus_ready = false
	state.field, state.cursor, state.anchor = "title", input.units(a.title), nil
end
local function button(label: string, action: string, class: string?, active: boolean?): any
	local base = class or "sm-button"
	if active then base ..= " keyboard" end
	return ui.el("button", { key = "button-" .. action:gsub("=", "-"), class = base, text = label, actions = { click = action } })
end
local function link(label: string, href: string, class: string?, active: boolean?): any
	local operation = href:match("^shortcut%-manager://[%w%-]+/(.+)$") or "open"
	local key = "button-" .. (if operation == "inspect-actions" then "inspect" elseif operation == "replace-save" then "replace" elseif operation:sub(1, 14) == "choose-action/" then "native-" .. operation:sub(15) else operation)
	return ui.el("button", { key = key, class = (class or "sm-button") .. (if active then " keyboard" else ""), text = label, href = href, actions = { click = "open" } })
end
local function text_field(state: State, name: string, label: string, multiline: boolean?, placeholder: string?): any
	local props: { [string]: any } = { key = "field-" .. name, role = "shortcut-manager.field." .. name,
		text = text(state, name), cursor = if state.field == name then state.cursor else input.units(text(state, name)),
		anchor = if state.field == name then state.anchor else nil, placeholder = placeholder or "", aria = label }
	if multiline then props.maxLines = 5 end
	return ui.el("div", { class = "sm-field", key = "wrap-" .. name }, { ui.el("div", { class = "sm-label", text = label }), ui.node(if multiline then "editor" else "input", props) })
end
local function choice_label(name: string, value: string): string
	local labels = {
		enabled = { ["true"] = "启用", ["false"] = "停用" },
		launch_kind = { process = "运行命令", tern = "Tern 动作" },
		shell = { ["false"] = "直接执行", ["true"] = "通过 Shell" },
		mode = { background = "后台进程", pane = "分屏终端", tab = "新标签页", float = "浮动终端" },
		cwd_mode = { source = "跟随当前目录", fixed = "指定目录" }, focus = { ["true"] = "切换到终端", ["false"] = "保持当前焦点" },
		reuse = { ["true"] = "复用已有终端", ["false"] = "每次新建终端" }, direction = { right = "右侧", down = "下方", left = "左侧", up = "上方" },
		corner = { tl = "左上", tr = "右上", bl = "左下", br = "右下", fullscreen = "全屏" },
	}
	return if labels[name] and labels[name][value] then labels[name][value] else value
end
local function choices(state: State, name: string, label: string, values: { string }): any
	local options = {}
	for _, value in values do
		local selected, active = text(state, name) == value, state.field == "choice-" .. name
		local class = if active and selected then "sm-option keyboard" else "sm-option"
		if selected then class ..= " selected" end
		table.insert(options, ui.el("button", { key = name .. "-" .. value, class = class, text = choice_label(name, value),
			actions = { click = "set=" .. name .. "|" .. value }, attrs = { ["aria-pressed"] = selected } }))
	end
	return ui.el("div", { key = "wrap-choice-" .. name, class = "sm-control" }, { ui.el("div", { class = "sm-label", text = label }), ui.el("div", { key = "options", class = "sm-options" }, options) })
end
local function keycaps(chord: string): any
	local caps = {}
	for index, step in string.split(chord, ">") do
		if index > 1 then table.insert(caps, ui.el("span", { class = "sm-separator", text = "然后" })) end
		for _, part in string.split(step, "+") do
			local label = ({ ctrl = "Ctrl", alt = "Option", shift = "Shift", cmd = "⌘", space = "Space" })[part] or part:upper()
			table.insert(caps, ui.el("span", { class = "sm-keycap", text = label }))
		end
	end
	return ui.el("div", { class = "sm-keycaps" }, caps)
end
local function presets(state: State): any
	local items = {}
	for _, p in { { "vscode", "VS Code" }, { "zed", "Zed" }, { "idea", "IDEA" }, { "lazygit", "Lazygit" }, { "lazydocker", "Lazydocker" } } do
		table.insert(items, button(p[2], "preset=" .. p[1], "sm-preset", state.field == "button-preset-" .. p[1]))
	end
	return ui.el("div", { key = "presets", class = "sm-presets" }, items)
end
local function feedback(state: State, items: { any })
	if state.status ~= "" then table.insert(items, ui.el("div", { class = "sm-status", text = state.status, attrs = { role = "status" } })) end
	if state.error then table.insert(items, ui.el("div", { class = "sm-error", text = state.error, attrs = { role = "alert" } })) end
	if state.confirm_discard then
		table.insert(items, ui.el("div", { class = "sm-warning", text = "有未保存的修改。切换会丢弃当前草稿，是否继续？", attrs = { role = "alert" } }))
		table.insert(items, ui.el("div", { key = "confirm-actions", class = "sm-form-actions" }, {
			button("丢弃并继续", "discard-confirm", "sm-button danger", state.field == "button-discard-confirm"),
			button("继续编辑", "discard-cancel", nil, state.field == "button-discard-cancel"),
		}))
	end
end
local function preview(state: State, d: Action): any
	local launch = if d.kind == "tern" then d.tern_action elseif d.shell then d.command else state.launch
	local cwd = if d.cwd_mode == "fixed" then d.cwd else state.source_cwd
	local description = if d.kind == "tern" then "运行 Tern 原生动作" else choice_label("mode", d.mode) .. " · " .. (if cwd == "" then "没有目标目录" else cwd)
	if d.kind == "process" then description ..= " · " .. choice_label("shell", tostring(d.shell)) end
	if d.kind == "process" and d.mode ~= "background" then description ..= " · " .. choice_label("focus", tostring(d.focus)) .. " · " .. choice_label("reuse", tostring(d.reuse)) end
	local content = { ui.el("div", { class = "sm-label", text = "执行预览 · 不会自动运行" }),
		ui.el("div", { class = "sm-preview-command", text = if launch == "" then "填写命令后，这里显示执行内容" else launch }),
		ui.el("div", { class = "sm-muted", text = description }) }
	if not d.enabled then table.insert(content, ui.el("div", { class = "sm-warning", text = "已停用：保存后不注册快捷键与命令面板动作。" })) end
	if d.kind == "process" and (d.mode == "pane" or d.mode == "float") then
		local panes = { ui.el("div", { class = "sm-mini-pane", text = "当前面板" }), ui.el("div", { class = "sm-mini-pane target", text = if d.mode == "pane" then choice_label("direction", d.direction) .. "新终端" else choice_label("corner", d.corner) .. "浮窗" }) }
		if d.mode == "float" and d.corner == "fullscreen" then table.remove(panes, 1) end
		if d.mode == "pane" and (d.direction == "left" or d.direction == "up") then panes[1], panes[2] = panes[2], panes[1] end
		table.insert(content, ui.el("div", { class = "sm-layout-preview " .. (if d.mode == "pane" and (d.direction == "up" or d.direction == "down") then "vertical" elseif d.mode == "float" then "float-" .. d.corner else "horizontal") }, panes))
	end
	return ui.el("div", { class = "sm-preview" }, content)
end
local function editor(state: State): any
	local d, href = state.draft, "shortcut-manager://" .. state.token .. "/"
	local items = {}
	if state.confirm_discard then
		feedback(state, items)
		return ui.el("div", { class = "sm-editor" }, items)
	end
	if d == nil then
		if state.dirty then
			table.insert(items, ui.el("div", { class = "sm-empty", text = "已标记删除。保存后才会移除动作与快捷键。" }))
			table.insert(items, ui.el("div", { key = "form-actions", class = "sm-form-actions" }, { link("保存删除", href .. "save", "sm-button primary", state.field == "button-save"), button("取消删除", "cancel", nil, state.field == "button-cancel") }))
		else
			table.insert(items, ui.el("div", { class = "sm-empty-title", text = "把常用操作，变成一个快捷键" }))
			table.insert(items, ui.el("div", { class = "sm-empty", text = "选择左侧动作开始编辑，或从常用工具快速创建。名称、快捷键、命令即可完成配置。" }))
			table.insert(items, presets(state))
		end
		feedback(state, items)
		if state.error then table.insert(items, button("重新加载并丢弃草稿", "reload", nil, state.field == "button-reload")) end
		return ui.el("div", { class = "sm-editor" }, items)
	end
	table.insert(items, text_field(state, "title", "名称", false, "例如：打开项目编辑器"))
	table.insert(items, choices(state, "enabled", "动作状态", { "true", "false" }))
	local shortcut = { ui.el("div", { key = "value", class = "sm-shortcut-value" }, {
		text_field(state, "chord", "快捷键", false, if state.recording then "现在按下快捷键…" else "ctrl+b>g · > 表示依次按键"),
	}),
		ui.el("div", { key = "options", class = "sm-options" }, {
			button(if state.recording then "完成录制" else "录制按键", if state.recording then "record-done" else "record", "sm-button", state.field == "button-record"),
			button(if state.recording then "取消录制" else "清除绑定", if state.recording then "record-cancel" else "clear-chord", nil, state.field == "button-clear-chord"),
		}) }
	if state.recording then table.insert(items, ui.el("div", { class = "sm-warning", text = "依次按键可录制序列。Enter 完成，Esc 取消。系统或 Tern 保留的按键可在快捷键输入框手填。" })) end
	table.insert(items, ui.el("div", { key = "shortcut", class = "sm-shortcut" }, shortcut))
	table.insert(items, choices(state, "launch_kind", "动作类型", { "process", "tern" }))
	if d.kind == "process" then
		table.insert(items, text_field(state, "launch", "运行命令", true, "例如 code . 或 git status --short"))
		table.insert(items, choices(state, "shell", "命令解释", { "false", "true" }))
		table.insert(items, ui.el("div", { class = if d.shell then "sm-warning" elseif state.input_error then "sm-error" else "sm-muted",
			text = if d.shell then "通过登录 Shell 执行，支持变量、管道与重定向。仅使用可信命令。" else state.input_error or "直接传入程序和参数；路径含空格时加引号。需要变量、管道或重定向时，选择通过 Shell。" }))
	else
		table.insert(items, link("浏览 Tern 动作", href .. "inspect-actions", nil, state.field == "button-inspect"))
		if type(state.inspection) == "table" and state.inspection.actions ~= nil then table.insert(items, text_field(state, "action_search", "搜索 Tern 动作", false, "名称或 ID")) end
		local catalog = {}
		for _, value in if type(state.inspection) == "table" then state.inspection.actions or {} else {} do
			local id = tostring(value.id or "")
			if state.action_search ~= "" and not (tostring(value.title or "") .. " " .. id):lower():find(state.action_search:lower(), 1, true) then continue end
			table.insert(catalog, link(tostring(value.title or id) .. (if value.available == false then " · 当前不可用" else ""), href .. "choose-action/" .. id, "sm-link", state.field == "button-native-" .. id))
		end
		if type(state.inspection) == "table" and state.inspection.actions ~= nil then
			table.insert(items, ui.el("div", { key = "catalog", class = "sm-catalog" }, if #catalog == 0 then { ui.el("div", { class = "sm-muted", text = "没有匹配的动作。试试其他名称或 ID。" }) } else catalog))
		end
		table.insert(items, text_field(state, "tern_action", "手动 Tern 动作 ID", false, "例如 new_tab"))
	end
	table.insert(items, ui.el("div", { key = "advanced-divider", class = "sm-divider", text = "高级参数", attrs = { role = "separator" } }))
	if d.kind == "process" then
		table.insert(items, choices(state, "mode", "在哪里运行", { "background", "pane", "tab", "float" }))
		if d.mode == "pane" then table.insert(items, choices(state, "direction", "分屏方向", { "left", "right", "up", "down" })) end
		if d.mode == "float" then
			table.insert(items, choices(state, "corner", "浮窗位置", { "tl", "tr", "bl", "br", "fullscreen" }))
			if d.corner == "fullscreen" then table.insert(items, ui.el("div", { class = "sm-muted", text = "填满浮窗所在区域，不进入系统全屏。全屏时切换到终端；离开焦点后恢复普通浮窗。" })) end
		end
		if d.mode ~= "background" then
			table.insert(items, choices(state, "focus", "启动后", if d.mode == "float" and d.corner == "fullscreen" then { "true" } else { "true", "false" }))
			table.insert(items, choices(state, "reuse", "重复触发时", { "true", "false" }))
		end
		table.insert(items, choices(state, "cwd_mode", "工作目录", { "source", "fixed" }))
		if d.cwd_mode == "fixed" then table.insert(items, text_field(state, "cwd", "目录绝对路径", false, "/Users/me/project")) end
	end
	table.insert(items, ui.el("div", { class = "sm-muted", text = "内部 ID：" .. d.id .. " · 自动生成，保存后保持不变" }))
	table.insert(items, preview(state, d))
	table.insert(items, link("试运行", href .. "try", "sm-button sm-fit", state.field == "button-try"))
	if not state.is_new then table.insert(items, button(if state.confirm_delete then "确认删除" else "删除动作", "delete", "sm-button danger sm-fit", state.field == "button-delete")) end
	feedback(state, items)
	if state.confirm_delete then table.insert(items, ui.el("div", { class = "sm-warning", text = "再次确认才标记删除，随后保存才会生效。不终止已启动程序。" })) end
	if state.error and type(state.inspection) == "table" and state.inspection.status == "conflict" then table.insert(items, link("确认替换冲突快捷键并保存", href .. "replace-save", "sm-button danger", state.field == "button-replace")) end
	if state.error then table.insert(items, button("重新加载并丢弃草稿", "reload", nil, state.field == "button-reload")) end
	if type(state.inspection) == "table" and state.inspection.keys ~= nil and state.inspection.actions == nil then
		local keys = {}; for binding in state.inspection.keys do table.insert(keys, binding) end; table.sort(keys)
		for _, binding in keys do table.insert(items, ui.el("div", { class = "sm-inspection" }, { keycaps(binding), ui.el("div", { class = "sm-muted", text = table.concat(state.inspection.keys[binding], ", ") }) })) end
	end
	return ui.el("div", { class = "sm-editor" }, {
		ui.el("div", { key = "heading", class = "sm-editor-heading" }, {
			ui.el("div", { text = (if state.is_new then "新建快捷动作" else "编辑快捷动作") .. " · " .. (if state.dirty then "未保存" else "已保存") }),
			ui.el("div", { key = "form-actions", class = "sm-form-actions" }, {
				button("取消", "cancel", nil, state.field == "button-cancel"),
				link("保存", href .. "save", "sm-button primary", state.field == "button-save"),
			}),
		}),
		ui.el("div", { key = "body", class = "sm-editor-body" }, items),
	})
end
local function list_panel(state: State): any
	local entries, query = {}, string.lower(state.search)
	for _, a in state.config.actions do
		local q = string.lower(a.title .. " " .. a.id .. " " .. a.chord)
		if query == "" or string.find(q, query, 1, true) then
			local selected, active = a.id == state.selected, state.field == "button-select-" .. a.id
			local class = if selected then "sm-action selected" else "sm-action"
			if active then class ..= " keyboard" end
			table.insert(entries, ui.el("button", { key = "action-" .. a.id, class = class,
				actions = { click = "select=" .. a.id }, attrs = { ["aria-pressed"] = selected } }, {
				ui.el("div", { class = "sm-action-title", text = a.title }),
				ui.el("div", { class = "sm-action-meta", text = (if a.enabled then "启用" else "停用") .. " · " .. (if a.chord == "" then "未绑定" else a.chord) }),
			}))
		end
	end
	return ui.el("div", { class = "sm-list" }, { ui.el("div", { class = "sm-toolbar" }, {
		ui.node("input", { key = "search", text = state.search, cursor = if state.field == "search" then state.cursor else input.units(state.search), placeholder = "搜索快捷动作", aria = "搜索快捷动作" }),
		button("+ 新建", "new", "sm-button primary", state.field == "button-new"),
	}), ui.el("div", { class = "sm-actions" }, if #entries == 0 then { ui.el("div", { class = "sm-empty", text = "没有匹配的动作。试试其他名称或快捷键。" }) } else entries) })
end
local function view(state: State, cx: BlockCx): BlockView
	if not state.confirm_discard and not state.focus_ready and state.draft ~= nil then
		state.focus_ready = true
		focus(state, "title", cx)
	end
	return { main = ui.col({ ui.el("div", { class = "sm-header" }, {
		ui.el("div", { class = "sm-title", text = "快捷动作管理器" }),
		ui.el("div", { class = "sm-meta", text = tostring(#state.config.actions) .. " 个动作 · 名称、按键、命令" }) }),
		ui.el("div", { class = "sm-layout" }, { list_panel(state), editor(state) }) }) }
end
local function init(cx: BlockCx, args: { string }, saved: any): State
	local token = args[1] or ""; local snap = tern.kv.get("draft:" .. token)
	tern.kv.set("panel:" .. tostring(cx.pane), token)
	if type(saved) == "table" and saved.token == token and type(saved.snapshot) == "table" then snap = saved.snapshot end
	local config = model.load()
	if type(snap) == "table" and snap.revision == config.revision and type(snap.actions) == "table" then config.actions = snap.actions end
	local selected = if type(snap) == "table" and type(snap.selected) == "string" then snap.selected else nil
	local draft = if type(snap) == "table" and type(snap.draft) == "table" then snap.draft else nil
	if draft == nil and selected then for _, a in config.actions do if a.id == selected then draft = model.clone(a); break end end end
	return { token = token, pane = cx.pane, source_id = if type(snap) == "table" and type(snap.source) == "number" then snap.source elseif args[2] then tonumber(args[2]) else nil,
		source_cwd = if type(snap) == "table" and type(snap.source_cwd) == "string" then snap.source_cwd else args[3] or "", config = config,
		baseline = if type(snap) == "table" and type(snap.revision) == "number" then snap.revision else config.revision, selected = selected, draft = draft,
		delete_id = if type(snap) == "table" and type(snap.delete_id) == "string" then snap.delete_id else nil,
		is_new = type(snap) == "table" and snap.is_new == true, dirty = type(snap) == "table" and snap.dirty == true,
		search = if type(snap) == "table" and type(snap.search) == "string" then snap.search else "", status = if type(snap) == "table" and type(snap.status) == "string" then snap.status else "", error = nil,
		inspection = nil, confirm_delete = false, confirm_discard = false, pending = nil, pending_preset = nil,
		field = if type(snap) == "table" and type(snap.field) == "string" then snap.field else "title",
		cursor = if type(snap) == "table" and type(snap.cursor) == "number" then snap.cursor else 0,
		anchor = if type(snap) == "table" and type(snap.anchor) == "number" then snap.anchor else nil, focus_ready = false,
		launch = if type(snap) == "table" and type(snap.launch) == "string" then snap.launch elseif draft then (if draft.shell then draft.command else command.format(draft.program, draft.args)) else "",
		input_error = if type(snap) == "table" and type(snap.input_error) == "string" then snap.input_error else nil,
		recording = false, recorded = {}, action_search = "" }
end
local function delete_action(state: State): ()
	if state.draft == nil or state.is_new or state.selected == nil then return end
	if not state.confirm_delete then state.confirm_delete = true; state.status = "再次点击确认删除。"; return end
	local id, actions = state.selected, {}
	for _, a in state.config.actions do if a.id ~= id then table.insert(actions, a) end end
	state.config.actions = actions; state.delete_id, state.draft, state.selected, state.dirty, state.confirm_delete = id, nil, nil, true, false
	state.status = "已标记删除；保存后生效。"
end
local function invoke(state: State, name: string): ()
	if name == "delete" then delete_action(state)
	elseif name == "record" then
		if state.draft then state.recording, state.recorded, state.field = true, {}, "button-record" end
	elseif name == "record-done" then
		if state.recording and #state.recorded > 0 then set_field(state, "chord", table.concat(state.recorded, ">")) end
		state.recording = false
	elseif name == "record-cancel" then state.recording, state.recorded = false, {}
	elseif name == "clear-chord" then set_field(state, "chord", "")
	elseif name == "cancel" then
		if state.draft == nil and state.dirty then state.config = model.load(); state.baseline = state.config.revision end
		state.delete_id = nil
		if state.is_new then state.draft, state.selected, state.is_new = nil, nil, false elseif state.selected then for _, a in state.config.actions do if a.id == state.selected then state.draft = model.clone(a); break end end end
		state.dirty, state.error, state.status, state.confirm_delete = false, nil, "已放弃本地修改。", false
		state.launch = if state.draft then (if state.draft.shell then state.draft.command else command.format(state.draft.program, state.draft.args)) else ""
		state.input_error, state.recording = nil, false
		state.field, state.focus_ready = "title", false
	elseif name == "reload" then
		state.config = model.load(); state.baseline = state.config.revision
		state.selected, state.draft, state.delete_id, state.is_new, state.dirty = nil, nil, nil, false, false
		state.error, state.inspection, state.status = nil, nil, "已重新加载配置。"
		state.recording, state.input_error = false, nil
	end
end
local function order(state: State): { string }
	local names = { "search", "button-new" }
	for _, a in state.config.actions do
		local q = string.lower(a.title .. " " .. a.id .. " " .. a.chord)
		if state.search == "" or string.find(q, string.lower(state.search), 1, true) then table.insert(names, "button-select-" .. a.id) end
	end
	local d = state.draft
	if state.confirm_discard then return { "button-discard-cancel", "button-discard-confirm" } end
	if d == nil then
		if state.dirty then table.insert(names, "button-save"); table.insert(names, "button-cancel")
		else for _, preset in { "vscode", "zed", "idea", "lazygit", "lazydocker" } do table.insert(names, "button-preset-" .. preset) end end
	else
		for _, name in { "button-cancel", "button-save" } do table.insert(names, name) end
		for _, name in { "title", "choice-enabled", "chord", "button-record", "button-clear-chord", "choice-launch_kind" } do table.insert(names, name) end
		if d.kind == "process" then table.insert(names, "launch"); table.insert(names, "choice-shell")
		else
			table.insert(names, "button-inspect")
			if type(state.inspection) == "table" and state.inspection.actions ~= nil then
				table.insert(names, "action_search")
				for _, a in state.inspection.actions do
					if state.action_search == "" or (tostring(a.title or "") .. " " .. a.id):lower():find(state.action_search:lower(), 1, true) then table.insert(names, "button-native-" .. a.id) end
				end
			end
			table.insert(names, "tern_action")
		end
		if d.kind == "process" then
			table.insert(names, "choice-mode")
			if d.mode == "pane" then table.insert(names, "choice-direction") end
			if d.mode == "float" then table.insert(names, "choice-corner") end
			if d.mode ~= "background" then table.insert(names, "choice-focus"); table.insert(names, "choice-reuse") end
			table.insert(names, "choice-cwd_mode"); if d.cwd_mode == "fixed" then table.insert(names, "cwd") end
		end
		table.insert(names, "button-try")
		if not state.is_new then table.insert(names, "button-delete") end
		if state.error and type(state.inspection) == "table" and state.inspection.status == "conflict" then table.insert(names, "button-replace") end
	end
	if state.error then table.insert(names, "button-reload") end
	return names
end
local function discard(state: State, pending: string?, preset: string?): ()
	state.confirm_discard, state.pending, state.pending_preset = true, pending, preset
	state.recording, state.field, state.status = false, "button-discard-cancel", ""
end
local function continue_pending(state: State): ()
	local pending, preset = state.pending, state.pending_preset
	state.confirm_discard, state.pending, state.pending_preset = false, nil, nil
	if state.draft == nil and state.dirty then state.config = model.load(); state.baseline = state.config.revision end
	state.delete_id = nil
	if state.is_new then state.draft, state.selected, state.is_new = nil, nil, false elseif state.selected then for _, a in state.config.actions do if a.id == state.selected then state.draft = model.clone(a); break end end end
	state.launch = if state.draft then (if state.draft.shell then state.draft.command else command.format(state.draft.program, state.draft.args)) else ""
	state.input_error, state.recording = nil, false
	state.dirty = false
	if pending == "new" then new_action(state, nil) elseif pending == "preset" then new_action(state, preset) elseif pending then show_action(state, pending) end
	state.status = ""
end
local function key(state: State, k: Key, cx: BlockCx): boolean?
	if state.recording then
		if k.name == "escape" then invoke(state, "record-cancel"); return true end
		if k.name == "enter" and not (k.ctrl or k.alt or k.shift or k.meta) then invoke(state, "record-done"); return true end
		if k.name == "paste" or k.name == "ctrl" or k.name == "alt" or k.name == "shift" or k.name == "cmd" then return true end
		local parts = {}
		if k.ctrl then table.insert(parts, "ctrl") end
		if k.alt then table.insert(parts, "alt") end
		if k.shift then table.insert(parts, "shift") end
		if k.meta then table.insert(parts, "cmd") end
		table.insert(parts, k.name:lower())
		local chord, err = model.chord(table.concat(parts, "+"))
		if chord then table.insert(state.recorded, chord) else state.error = err end
		return true
	end
	if state.confirm_discard and k.name == "escape" then state.confirm_discard, state.pending, state.pending_preset, state.status = false, nil, nil, ""; state.focus_ready = false; return true end
	if k.name == "escape" then if state.dirty then discard(state, nil, nil) else state.draft, state.selected, state.is_new = nil, nil, false end; return true end
	if (k.ctrl or k.meta) and k.name == "s" then state.status = "保存请按 Ctrl+Alt+Shift+S，或点击保存。"; return true end
	if k.name == "tab" then
		local names = order(state)
		local at = table.find(names, state.field) or 0
		at = ((at - 1 + (if k.shift then -1 else 1)) % #names) + 1
		focus(state, names[at], cx)
		return true
	end
	if string.sub(state.field, 1, 7) == "button-" then
		if k.name ~= "enter" and k.name ~= "space" then return false end
		local action = string.sub(state.field, 8)
		if action == "new" then if state.dirty then discard(state, "new", nil) else new_action(state, nil) end
		elseif string.sub(action, 1, 7) == "preset-" then local preset = string.sub(action, 8); if state.dirty then discard(state, "preset", preset) else new_action(state, preset) end
		elseif string.sub(action, 1, 7) == "select-" then local id = string.sub(action, 8); if id == state.selected then return true end; if state.dirty then discard(state, id, nil) else show_action(state, id) end
		elseif action == "discard-confirm" then continue_pending(state)
		elseif action == "discard-cancel" then state.confirm_discard, state.pending, state.pending_preset, state.status = false, nil, nil, ""; state.focus_ready = false
		elseif action == "save" or action == "inspect" or action == "try" or action == "replace" then
			persist(state)
			cx:open("shortcut-manager://" .. state.token .. "/" .. (if action == "inspect" then "inspect-actions" elseif action == "replace" then "replace-save" else action))
		elseif action:sub(1, 7) == "native-" then persist(state); cx:open("shortcut-manager://" .. state.token .. "/choose-action/" .. action:sub(8))
		else invoke(state, action) end
		return true
	end
	if string.sub(state.field, 1, 7) == "choice-" then
		local name = string.sub(state.field, 8)
		local values = if name == "launch_kind" then { "process", "tern" } elseif name == "focus" and state.draft and state.draft.mode == "float" and state.draft.corner == "fullscreen" then { "true" }
			elseif name == "shell" then { "false", "true" }
			elseif name == "enabled" or name == "focus" or name == "reuse" then { "true", "false" }
			elseif name == "mode" then { "background", "pane", "tab", "float" } elseif name == "cwd_mode" then { "source", "fixed" }
			elseif name == "direction" then { "left", "right", "up", "down" } else { "tl", "tr", "bl", "br", "fullscreen" }
		local at = table.find(values, text(state, name)) or 1
		if k.name == "left" or k.name == "up" or k.name == "right" or k.name == "down" or k.name == "enter" or k.name == "space" then local step = if k.name == "left" or k.name == "up" then -1 else 1; at = ((at - 1 + step) % #values) + 1; set_field(state, name, values[at]); return true end
		return false
	end
	local previous = text(state, state.field)
	local updated, cursor, anchor, handled = input.apply(previous, state.cursor, state.anchor, k, state.field == "launch")
	if not handled then return false end
	state.cursor, state.anchor = cursor, anchor
	if updated ~= previous then set_field(state, state.field, updated) end
	return true
end
local function commit_event(state: State, ev: UiEvent, cx: BlockCx): ()
	if ev.ev ~= "action" or ev.act ~= "manager-commit" then return end
	local decoded, request = pcall(tern.json.decode, tostring(ev.value or "{}")); if not decoded or type(request) ~= "table" or request.token ~= state.token then return end
	local tx = tostring(request.transaction or "")
	local loaded, fresh = pcall(model.load)
	local function ack(outcome: any)
		pcall(tern.kv.set, "ack:" .. tx, outcome); cx:open("shortcut-manager://" .. state.token .. "/ack/" .. tx)
	end
	if not loaded then ack({ ok = false, error = tostring(fresh), config = { revision = state.baseline, actions = {}, bindings = {} } }); return end
	if fresh.revision ~= request.expected_revision then ack({ ok = false, error = "配置已在其他面板更新，请重新加载后再保存。", config = fresh }); return end
	local valid, config, err = pcall(model.validate_config, request.config)
	if not valid or config == nil then ack({ ok = false, error = tostring(if valid then err else config), config = fresh }); return end
	if config.revision ~= fresh.revision then ack({ ok = false, error = "版本不匹配；没有写入配置。", config = fresh }); return end
	config.revision = fresh.revision + 1
	local written, write_error = pcall(function() tern.kv.set("config", config); return true end)
	if not written then ack({ ok = false, error = tostring(write_error), config = fresh }); return end
	state.config, state.baseline, state.dirty = config, config.revision, false
	state.is_new, state.delete_id = false, nil
	if state.draft ~= nil then state.selected = state.draft.id end
	state.status = "已保存，正在应用快捷键…"
	ack({ ok = true, config = config })
end
local function event(state: State, ev: UiEvent, cx: BlockCx): ()
	if ev.act == "manager-commit" then commit_event(state, ev, cx); return end
	if ev.ev == "focus" then
		local id = tostring(ev.id or "")
		local name = string.match(id, "field%-([%w_]+)$")
		if name == nil and string.sub(id, -6) == ".search" then name = "search" end
		if name then state.field, state.cursor, state.anchor = name, input.units(text(state, name)), nil; cx:frame({ { "focus", id } }) end
		return
	end
	if ev.ev ~= "action" then return end
	if ev.act == "manager-response" then
		local decoded, response = pcall(tern.json.decode, tostring(ev.value or "{}")); if not decoded or type(response) ~= "table" then state.error = "管理器响应无效。"; return end
		if response.transaction then pcall(tern.kv.set, "ack:" .. tostring(response.transaction), nil) end
		if response.status == "saved" and type(response.config) == "table" then
			local wanted = if state.draft then state.draft.id else state.selected
			state.config = response.config :: Config; state.baseline, state.dirty, state.is_new, state.delete_id, state.error = state.config.revision, false, false, nil, nil
			state.confirm_discard, state.pending, state.pending_preset = false, nil, nil
			if wanted then show_action(state, wanted) else state.draft, state.selected = nil, nil end
			state.status = "已保存并应用。"
		elseif response.status == "source" then state.source_id = if type(response.source) == "number" then response.source else nil; state.source_cwd = if type(response.source_cwd) == "string" then response.source_cwd else ""
		elseif response.status == "selected-action" then
			if state.draft then
				state.draft.tern_action = tostring(response.action or "")
				state.dirty, state.field, state.inspection, state.action_search = true, "button-inspect", nil, ""
			end
		elseif response.status == "inspection" then
			state.inspection = response
			state.error = if type(response.error) == "string" then response.error else nil
			state.status = if response.actions ~= nil then "可用 Tern 动作" elseif type(response.message) == "string" then "上次试运行已触发：" .. response.message else "动作信息已加载"
		elseif response.status == "conflict" then state.error, state.status, state.inspection = response.error or "快捷键冲突。", "确认替换后将覆盖错误信息列出的冲突快捷键。", response
		elseif response.status == "saving" then state.status = "正在应用快捷键设置…"
		elseif response.status == "error" then state.error, state.status = response.error or "保存失败。", "" end
		return
	end
	local act, value = tostring(ev.act or ""), tostring(ev.value or "")
	if state.confirm_discard then
		if act == "discard-confirm" then continue_pending(state)
		elseif act == "discard-cancel" then state.confirm_discard, state.pending, state.pending_preset, state.status = false, nil, nil, ""; state.focus_ready = false end
		return
	end
	if act == "select" then if value == state.selected then return end; if state.dirty then discard(state, value, nil) else show_action(state, value) end
	elseif act == "new" then if state.dirty then discard(state, "new", nil) else new_action(state, nil) end
	elseif act == "preset" then if state.dirty then discard(state, "preset", value) else new_action(state, value) end
	elseif act == "cancel" or act == "delete" or act == "reload" or act == "record" or act == "record-done" or act == "record-cancel" or act == "clear-chord" then invoke(state, act)
	elseif act == "set" then local name, value2 = string.match(value, "^([^|]+)|(.+)$"); if name and value2 then set_field(state, name, value2); state.field = "choice-" .. name end end
end
local manager: BlockDef<State> = { init = init, view = view, title = function() return "快捷动作管理器" end, key = key, event = event,
	save = function(state) persist(state); return { token = state.token, snapshot = snapshot(state) } end }
tern.block.define("manager", manager)
