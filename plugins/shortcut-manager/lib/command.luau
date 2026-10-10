--!strict

local command = {}

local function shell_mode_error(token: string): string
	return "检测到 Shell 语法 " .. token .. "；请选择命令解释中的「通过 Shell」"
end

function command.parse(text: string): (string?, { string }?, string?)
	local args: { string } = {}
	local token: { string } = {}
	local quote: string? = nil
	local token_started = false
	local index = 1
	local length = #text

	while index <= length do
		local char = text:sub(index, index)
		if quote == nil and char:match("%s") then
			if token_started then
				table.insert(args, table.concat(token))
				token = {}
				token_started = false
			end
			index += 1
		elseif quote == nil and (char == "|" or char == "&" or char == ";" or char == "<" or char == ">" or char == "`") then
			return nil, nil, shell_mode_error(char)
		elseif quote == nil and char == "$" and text:sub(index + 1, index + 1) == "(" then
			return nil, nil, shell_mode_error("$(…)")
		elseif char == "\\" and quote ~= "'" then
			if index == length then
				return nil, nil, "命令末尾的反斜杠没有转义对象"
			end
			token_started = true
			index += 1
			table.insert(token, text:sub(index, index))
			index += 1
		elseif char == "'" and (quote == nil or quote == "'") then
			quote = if quote == nil then "'" else nil
			token_started = true
			index += 1
		elseif char == '"' and (quote == nil or quote == '"') then
			quote = if quote == nil then '"' else nil
			token_started = true
			index += 1
		else
			token_started = true
			table.insert(token, char)
			index += 1
		end
	end

	if quote ~= nil then
		return nil, nil, "引号未闭合；请补上匹配的引号"
	end
	if token_started then
		table.insert(args, table.concat(token))
	end

	if #args == 0 then
		return "", {}, nil
	end
	local program = table.remove(args, 1)
	return program, args, nil
end

local function quote_posix(value: string): string
	if value ~= "" and value:match("^[%w_./:%-]+$") then return value end
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

function command.format(program: string, args: { string }): string
	if program == "" and #args == 0 then return "" end
	local parts = { quote_posix(program) }
	for _, arg in args do
		table.insert(parts, quote_posix(arg))
	end
	return table.concat(parts, " ")
end

return command
