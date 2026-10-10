--!strict

local M = {}
type Key = { name: string, text: string?, ctrl: boolean, alt: boolean, shift: boolean, meta: boolean }
type Point = { byte: number, units: number, cp: number }

local function points(text: string): { Point }
	local out: { Point } = {}
	local i = 1
	while i <= #text do
		local b = string.byte(text, i)
		local n = if b < 0x80 then 1 elseif b < 0xE0 then 2 elseif b < 0xF0 then 3 else 4
		local cp = if n == 1 then b elseif n == 2 then (b - 0xC0) * 64 + string.byte(text, i + 1) - 0x80
			elseif n == 3 then (b - 0xE0) * 4096 + (string.byte(text, i + 1) - 0x80) * 64 + string.byte(text, i + 2) - 0x80
			else (b - 0xF0) * 262144 + (string.byte(text, i + 1) - 0x80) * 4096 + (string.byte(text, i + 2) - 0x80) * 64 + string.byte(text, i + 3) - 0x80
		table.insert(out, { byte = i, units = if cp > 0xFFFF then 2 else 1, cp = cp })
		i += n
	end
	return out
end

local function length(text: string): number
	local n = 0
	for _, p in points(text) do n += p.units end
	return n
end

local function byte_at(text: string, offset: number): number
	local units = 0
	for _, p in points(text) do
		if units >= offset or units + p.units > offset then return p.byte end
		units += p.units
	end
	return #text + 1
end

local function slice(text: string, first: number, last: number): string
	return string.sub(text, byte_at(text, first), byte_at(text, last) - 1)
end

local function clamp(text: string, offset: number): number
	offset = math.max(0, math.min(length(text), offset))
	local units = 0
	for _, p in points(text) do
		if units + p.units > offset then return units end
		units += p.units
	end
	return units
end

local function word(cp: number): boolean
	return (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) or cp == 95
end

local function word_move(text: string, cursor: number, dir: number): number
	local ps = points(text)
	local offset, i = 0, 1
	while i <= #ps and offset < cursor do offset += ps[i].units; i += 1 end
	if dir < 0 then
		while i > 1 and not word(ps[i - 1].cp) do i -= 1 end
		while i > 1 and word(ps[i - 1].cp) do i -= 1 end
		offset = 0
		for j = 1, i - 1 do offset += ps[j].units end
		return offset
	end
	while i <= #ps and word(ps[i].cp) do i += 1 end
	while i <= #ps and not word(ps[i].cp) do i += 1 end
	offset = 0
	for j = 1, i - 1 do offset += ps[j].units end
	return offset
end

function M.units(text: string): number
	return length(text)
end

function M.apply(text: string, cursor: number, anchor: number?, key: Key, multiline: boolean): (string, number, number?, boolean)
	cursor = clamp(text, cursor)
	if anchor ~= nil then anchor = clamp(text, anchor) end
	local lo, hi = cursor, cursor
	if anchor ~= nil then lo, hi = math.min(cursor, anchor), math.max(cursor, anchor) end
	local name = key.name
	local function move(pos: number): (string, number, number?, boolean)
		if key.shift then
			if anchor == nil then anchor = cursor end
		else anchor = nil end
		cursor = clamp(text, pos)
		if anchor == cursor then anchor = nil end
		return text, cursor, anchor, true
	end
	if (key.ctrl or key.meta) and (name == "a" or name == "A") then return text, length(text), 0, true end
local function codepoint_move(text: string, cursor: number, direction: number): number
	local offset = 0
	for _, p in points(text) do
		local next_offset = offset + p.units
		if direction < 0 and next_offset >= cursor then return offset end
		if direction > 0 and offset >= cursor then return next_offset end
		offset = next_offset
	end
	return offset
end

if name == "left" or name == "right" then
	local dir = if name == "left" then -1 else 1
	if anchor ~= nil and not key.shift then return text, if dir < 0 then lo else hi, nil, true end
	return move(if key.alt or key.ctrl or key.meta then word_move(text, cursor, dir) else codepoint_move(text, cursor, dir))
	end
	if name == "home" or name == "end" then
		local start, finish = 0, length(text)
		local prefix = slice(text, 0, cursor)
		local nl = string.match(prefix, ".*()\n")
		if nl then start = length(string.sub(prefix, 1, nl)) end
		if multiline then
			local suffix = slice(text, cursor, length(text))
			local next_nl = string.find(suffix, "\n", 1, true)
			if next_nl then finish = cursor + length(string.sub(suffix, 1, next_nl - 1)) end
		end
		return move(if name == "home" then start else finish)
	end
	if name == "backspace" or name == "delete" then
		if lo == hi then
			if name == "backspace" then
				if cursor == 0 then return text, cursor, anchor, false end
				local u = 0
				for _, p in points(text) do
					if u + p.units >= cursor then lo = u; break end
					u += p.units
				end
				hi = cursor
			else
				if cursor >= length(text) then return text, cursor, anchor, false end
				lo = cursor
				local u = 0
				for _, p in points(text) do
					if u >= cursor then hi = u + p.units; break end
					u += p.units
				end
			end
		end
		text = slice(text, 0, lo) .. slice(text, hi, length(text))
		return text, lo, nil, true
	end
	local insertion = key.text or ""
	if name == "enter" then
		if not multiline then return text, cursor, anchor, false end
		insertion = "\n"
	elseif name == "paste" then
		if not multiline then insertion = string.gsub(insertion, "[\r\n]+", " ") end
	elseif insertion == "" or key.ctrl or key.meta then return text, cursor, anchor, false end
	if insertion == "" then return text, cursor, anchor, false end
	text = slice(text, 0, lo) .. insertion .. slice(text, hi, length(text))
	return text, lo + length(insertion), nil, true
end

return M
