--!strict

local model = require("./lib/model")
local execute = require("./lib/execute")
type Config = model.Config
type Action = model.Action

type Transaction = {
	pane: number, token: string, before: { [string]: any }, applied: { [string]: any },
}
local pending: { [string]: Transaction } = {}
local serial = 0
local prefix = "shortcut-manager://"
local loaded_revision = model.load().revision

local function nonce(): string
	serial += 1
	return tostring(math.floor(tern.now() * 1000)) .. "-" .. tostring(math.random(10000000, 99999999)) .. "-" .. tostring(serial)
end

local function equal(a: any, b: any): boolean
	return tern.json.encode(a) == tern.json.encode(b)
end

local function respond(cx: WindowCx, pane: number, data: any)
	cx.session:event(pane, { ev = "action", act = "manager-response", value = tern.json.encode(data) })
end

local function owned_value(binding: model.Binding): any
	return if binding.action == "" then {} else binding.action
end

local function rollback(cx: WindowCx, transaction: Transaction)
	local current = cx.settings:keybinds()
	local changed: { [string]: boolean } = {}
	for key, value in transaction.applied do
		if not equal(value, transaction.before[key]) then changed[key] = true end
	end
	for key, value in transaction.before do
		if not equal(value, transaction.applied[key]) then changed[key] = true end
	end
	for key in changed do
		if equal(current[key], transaction.applied[key]) then current[key] = transaction.before[key] end
	end
	cx.settings:set("keybinds", current)
end

local function conflict(a: string, b: string): boolean
	return a == b or a:sub(1, #b + 1) == b .. ">" or b:sub(1, #a + 1) == a .. ">"
end

local function setting_key(map: { [string]: any }, normalized: string): string?
	for key in map do
		local parsed = model.chord(key)
		if parsed == normalized then return key end
	end
	return nil
end

local function save(cx: WindowCx, pane: number, token: string, draft: any, replace: boolean)
	for _, transaction in pending do
		if transaction.pane == pane then respond(cx, pane, { status = "saving" }); return end
	end
	local current = model.load()
	if draft.revision ~= current.revision then
		respond(cx, pane, { status = "error", error = "配置已在另一面板修改。请重新加载后再编辑。" })
		return
	end
	local next_config: Config = model.clone(current)
	local found = false
	if type(draft.delete_id) == "string" then
		for index = #next_config.actions, 1, -1 do
			if next_config.actions[index].id == draft.delete_id then table.remove(next_config.actions, index); found = true end
		end
		if not found then respond(cx, pane, { status = "error", error = "待删除动作已不存在" }); return end
	else
		local action, err = model.validate(draft.action)
		if action == nil then respond(cx, pane, { status = "error", error = err }); return end
		if not draft.is_new and action.id ~= draft.selected then
			respond(cx, pane, { status = "error", error = "已保存动作的稳定 ID 不能修改；请新建动作。" })
			return
		end
		for index, old in next_config.actions do
			if old.id == action.id then
				if draft.is_new then respond(cx, pane, { status = "error", error = "动作 ID 已存在：" .. action.id }); return end
				next_config.actions[index] = action; found = true; break
			end
		end
		if not found then table.insert(next_config.actions, action) end
	end
	next_config.bindings = {}
	local validated, validation_error = model.validate_config(next_config)
	if validated == nil then respond(cx, pane, { status = "error", error = validation_error }); return end
	next_config = validated
	local before = cx.settings:keybinds()
	local overrides = model.clone(before)
	for key, binding in current.bindings do
		if equal(overrides[key], owned_value(binding)) then
			overrides[key] = if binding.had_previous then binding.previous else nil
		end
	end
	-- Read the native effective map after restoring owned overrides, so hidden defaults are checked too.
	cx.settings:set("keybinds", overrides)
	local base = cx.actions:keys()
	local restored = model.clone(overrides)
	local conflicts: { string } = {}
	local suppressed: { [string]: boolean } = {}
	for _, action in next_config.actions do
		if not action.enabled or action.chord == "" then continue end
		for spell, actions in base do
			local normalized = model.chord(spell)
			if normalized == nil or not conflict(action.chord, normalized) then continue end
			local external = false
			for _, name in actions do
				if not name:match("^plugin%.shortcut%-manager%.") or (setting_key(restored, normalized) ~= nil and name ~= model.action_name(action.id)) then external = true end
			end
			if external then
				table.insert(conflicts, action.chord .. " 与 " .. spell .. "（" .. table.concat(actions, ", ") .. "）冲突")
				if replace and not suppressed[spell] then
					local key = setting_key(overrides, normalized) or spell
					next_config.bindings[key] = { action = "", previous = model.clone(overrides[key]), had_previous = overrides[key] ~= nil }
					overrides[key] = {}
					suppressed[spell] = true
				end
			end
		end
	end
	if #conflicts > 0 and not replace then
		cx.settings:set("keybinds", before)
		respond(cx, pane, { status = "conflict", error = table.concat(conflicts, "\n") })
		return
	end
	for _, action in next_config.actions do
		if action.enabled and action.chord ~= "" then
			local key = setting_key(overrides, action.chord) or action.chord
			local name = model.action_name(action.id)
			if next_config.bindings[key] ~= nil then
				next_config.bindings[key].action = name
			else
				next_config.bindings[key] = { action = name, previous = model.clone(overrides[key]), had_previous = overrides[key] ~= nil }
			end
			overrides[key] = name
		end
	end
	local ok, err = pcall(function() cx.settings:set("keybinds", overrides) end)
	if not ok then
		cx.settings:set("keybinds", before)
		respond(cx, pane, { status = "error", error = tostring(err) })
		return
	end
	local id = nonce()
	pending[id] = { pane = pane, token = token, before = before, applied = overrides }
	respond(cx, pane, { status = "saving" })
	cx.session:event(pane, {
		ev = "action", act = "manager-commit",
		value = tern.json.encode({ token = token, expected_revision = current.revision, config = next_config, transaction = id }),
	})
end

local function ack(cx: WindowCx, token: string, transaction_id: string)
	local transaction = pending[transaction_id]
	if transaction == nil then
		if model.load().revision ~= loaded_revision then cx:command("reload_plugins") end
		return
	end
	if transaction.token ~= token then return end
	local outcome = tern.kv.get("ack:" .. transaction_id)
	if type(outcome) ~= "table" then return end
	pending[transaction_id] = nil
	if not outcome.ok then
		rollback(cx, transaction)
		respond(cx, transaction.pane, { status = "error", error = outcome.error or "保存失败", transaction = transaction_id })
		return
	end
	respond(cx, transaction.pane, { status = "saved", config = outcome.config, transaction = transaction_id })
	-- Apply the native reload at the handler boundary, without an asynchronous CLI gap.
	cx:command("reload_plugins")
end

local function route(link: LinkRequest, cx: WindowCx): RouteDecision?
	if link.url:sub(1, #prefix) ~= prefix then return nil end
	local token, operation, rest = link.url:match("^shortcut%-manager://([%w%-]+)/([%w%-]+)(.*)$")
	if token == nil then return { handled = true } end
	local suffix = rest or ""
	if operation == "ack" then
		local transaction = suffix:match("^/([%w%-]+)$")
		if transaction then ack(cx, token, transaction) end
		return { handled = true }
	end
	local pane = if link.pane ~= nil then cx.session:pane(link.pane) else nil
	local draft = tern.kv.get("draft:" .. token)
	if pane == nil or pane.kind ~= "plugin" or pane.block ~= "shortcut-manager.manager" then
		cx:toast("error", "Shortcut Manager 请求必须来自管理面板")
		return { handled = true }
	end
	if type(draft) ~= "table" or draft.token ~= token or draft.pane ~= pane.pane then
		cx:toast("error", "Shortcut Manager 面板请求已失效")
		return { handled = true }
	end
	local changing = operation == "save" or operation == "replace-save" or operation == "replace"
	if (changing or operation == "try") and draft.delete_id == nil and type(draft.action) == "table"
		and draft.action.kind == "process" and not draft.action.shell and type(draft.input_error) == "string" then
		respond(cx, pane.pane, { status = "error", error = draft.input_error })
		return { handled = true }
	end
	local before = if changing then cx.settings:keybinds() else nil
	local ok, err = pcall(function(): boolean
		if operation == "save" or operation == "replace-save" or operation == "replace" then
			save(cx, pane.pane, token, draft, operation ~= "save")
		elseif operation == "try" then
			local action, validation_error = model.validate(draft.action)
			if action == nil then respond(cx, pane.pane, { status = "error", error = validation_error }); return false end
			local launched, message = execute.run(action, cx, draft.source)
			respond(cx, pane.pane, { status = if launched then "inspection" else "error", message = if launched then message else nil, error = if launched then nil else message })
		elseif operation == "inspect-actions" then
			local actions = {}
			for _, action in cx.actions:list() do
				if not action.id:match("^plugin%.shortcut%-manager%.") then
					table.insert(actions, { id = action.id, title = action.label, group = action.group, keys = action.keys, available = action.available })
				end
			end
			respond(cx, pane.pane, { status = "inspection", actions = actions, keys = cx.actions:keys() })
		elseif operation == "check-key" then
			respond(cx, pane.pane, { status = "inspection", keys = cx.actions:keys() })
		elseif operation == "choose-action" then
			local id = suffix:match("^/(.+)$")
			if id == nil then error("未选择 Tern 动作") end
			local selected = cx.actions:describe(id)
			if selected.id:match("^plugin%.shortcut%-manager%.") then error("不能调用本插件动作") end
			respond(cx, pane.pane, { status = "selected-action", action = selected.id })
		end
		return true
	end)
	if not ok then
		if before ~= nil then cx.settings:set("keybinds", before) end
		respond(cx, pane.pane, { status = "error", error = tostring(err) })
	end
	return { handled = true }
end
tern.route.link(route)

local function manager_request(cx: WindowCx, operation: string): boolean
	local id = cx.session:focused()
	local pane = if id ~= nil then cx.session:pane(id) else nil
	if pane == nil or pane.kind ~= "plugin" or pane.block ~= "shortcut-manager.manager" then return false end
	local token = tern.kv.get("panel:" .. tostring(pane.pane))
	if type(token) ~= "string" then cx:toast("error", "管理面板尚未就绪"); return true end
	route({ pane = pane.pane, url = prefix .. token .. "/" .. operation, mods = { cmd = false, alt = false, shift = false, ctrl = false } }, cx)
	return true
end

tern.override("save", function(cx) return manager_request(cx, "save") end)

for _, definition in { { "manager-save", "保存并应用当前草稿", "save" }, { "manager-try", "试运行当前草稿", "try" }, { "manager-inspect", "选择 Tern 动作", "inspect-actions" }, { "manager-check", "查看有效快捷键", "check-key" } } do
	local operation = definition[3]
	tern.command({
		id = definition[1], title = "Shortcut Manager: " .. definition[2], icon = "keyboard",
		keys = if operation == "save" then { "ctrl+alt+shift+s" } else nil,
		available = function(cx)
			local id = cx.session:focused()
			local pane = if id ~= nil then cx.session:pane(id) else nil
			return pane ~= nil and pane.kind == "plugin" and pane.block == "shortcut-manager.manager"
		end,
		run = function(cx) manager_request(cx, operation) end,
	})
end

tern.command({
	id = "manage", title = "Shortcut Manager: 管理快捷动作", icon = "keyboard",
	run = function(cx)
		if cx.hosts:current().kind ~= "local" then cx:toast("error", "请在本机 session 中打开管理面板"); return end
		local source = cx.session:focused()
		local origin = if source ~= nil then cx.session:pane(source) else nil
		for _, pane in cx.session:panes() do
			if pane.kind == "plugin" and pane.block == "shortcut-manager.manager" then
				if origin ~= nil and origin.pane ~= pane.pane then
					respond(cx, pane.pane, { status = "source", source = origin.pane, source_cwd = origin.cwd or "" })
				end
				cx.layout:focus(pane.pane)
				return
			end
		end
		local manager = cx:new_block("shortcut-manager.manager", { nonce(), tostring(source or 0), if origin ~= nil then origin.cwd or "" else "" }, "beside")
		if manager == nil then cx:toast("error", "Shortcut Manager Host-side 未加载") end
	end,
})

local config = model.load()
for _, saved in config.actions do
	if not saved.enabled then continue end
	local action: Action = saved
	tern.command({
		id = action.id, title = action.title, icon = "terminal", group = "Shortcut Manager",
		keys = if action.chord ~= "" then { action.chord } else nil,
		run = function(cx)
			local current: Action? = nil
			for _, candidate in model.load().actions do
				if candidate.id == action.id and candidate.enabled then current = candidate; break end
			end
			if current == nil then cx:toast("error", "动作已删除或停用"); return end
			local ok, message = execute.run(current, cx)
			if not ok then cx:toast("error", current.title, message) end
		end,
	})
end
