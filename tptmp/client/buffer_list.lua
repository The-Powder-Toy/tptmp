local buffer_list_i = {}
local buffer_list_m = { __index = buffer_list_i }

function buffer_list_i:push(data)
	local count = #data
	local want = count
	if self.limit then
		want = math.min(want, self.limit - self:pending())
	end
	if want > 0 then
		local buf = {
			data = data,
			curr = 0,
			last = want,
			prev = self.last_.prev,
			next = self.last_,
		}
		self.last_.prev.next = buf
		self.last_.prev = buf
		self.pushed_ = self.pushed_ + want
	end
	return want, count
end

function buffer_list_i:next()
	local buf = self.first_.next
	if buf == self.last_ then
		return
	end
	return buf.data, buf.curr + 1, buf.last
end

function buffer_list_i:pop(count)
	local buf = self.first_.next
	assert(buf ~= self.last_)
	assert(buf.last - buf.curr >= count)
	buf.curr = buf.curr + count
	if buf.curr == buf.last then
		buf.prev.next = buf.next
		buf.next.prev = buf.prev
	end
	self.popped_ = self.popped_ + count
end

function buffer_list_i:pushed()
	return self.pushed_
end

function buffer_list_i:popped()
	return self.popped_
end

function buffer_list_i:pending()
	return self.pushed_ - self.popped_
end

function buffer_list_i:get(count)
	assert(count <= self.pushed_ - self.popped_)
	local collect = {}
	while count > 0 do
		local data, first, last = self:next()
		local want = math.min(count, last - first + 1)
		local want_last = first - 1 + want
		table.insert(collect, first == 1 and want_last == #data and data or data:sub(first, want_last))
		self:pop(want)
		count = count - want
	end
	return table.concat(collect)
end

local function new(params)
	local bl = setmetatable({
		first_ = {},
		last_ = {},
		limit = params.limit,
		pushed_ = 0,
		popped_ = 0,
	}, buffer_list_m)
	bl.first_.next = bl.last_
	bl.last_.prev = bl.first_
	return bl
end

return {
	new = new,
}
