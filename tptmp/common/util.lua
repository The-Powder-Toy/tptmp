local function version_less(lhs, rhs)
	for i = 1, math.max(#lhs, #rhs) do
		local left = lhs[i] or 0
		local right = rhs[i] or 0
		if left < right then
			return true
		end
		if left > right then
			return false
		end
	end
	return false
end

local function version_equal(lhs, rhs)
	for i = 1, math.max(#lhs, #rhs) do
		local left = lhs[i] or 0
		local right = rhs[i] or 0
		if left ~= right then
			return false
		end
	end
	return true
end

return {
	version_less = version_less,
	version_equal = version_equal,
}
