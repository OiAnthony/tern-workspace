--!strict

export type Record = {
	auto_name: string?,
	manual: boolean,
	pending_name: string?,
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

return {
	basename = basename,
	observe = observe,
}
