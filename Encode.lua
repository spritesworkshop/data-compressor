local encodeModule = {}

local pairs = pairs
local table_insert = table.insert
local bit32_band = bit32.band
local bit32_rshift = bit32.rshift
local bit32_bor = bit32.bor
local buffer_create = buffer.create
local buffer_writeu8 = buffer.writeu8
local buffer_writeu16 = buffer.writeu16
local buffer_writei16 = buffer.writei16
local buffer_writeu32 = buffer.writeu32
local buffer_writef32 = buffer.writef32
local buffer_writef64 = buffer.writef64
local buffer_writestring = buffer.writestring
local buffer_len = buffer.len
local buffer_copy = buffer.copy
local math_floor = math.floor
local math_clamp = math.clamp

local tbfFunctions = {
	function(input)
		local dat = input.Data
		local size = #dat
		local buf = buffer_create(size)
		buffer_writestring(buf, 0, dat, size)
		return buf
	end, 
}

local function ToBuffer(input)
	return tbfFunctions[input.DataType + 1](input)
end

local function toI16(num: number)
	return math.floor(num * 32767 + 0.5)
end

local function BufByte(input)
	local buf = buffer_create(1)
	buffer_writeu8(buf, 0, input)
	return buf
end

local function MergeBuffers(...)
	local offset = 0
	local totalSize = 0
	local list = {...}
	for _, v in pairs(list) do
		totalSize += buffer_len(v)
	end
	local buf = buffer_create(totalSize)
	for _, v in pairs(list) do
		local size = buffer_len(v)
		buffer_copy(buf, offset, v, 0, size)
		offset += size
	end
	return buf
end

encodeModule.EncodeVarLength = function(input: number)
	local bytes = {}
	while true do
		local x = bit32_band(input, 0x7F)
		input = bit32_rshift(input, 7)
		if input == 0 then
			table_insert(bytes, bit32_bor(0x80, x))
			break
		end
		table_insert(bytes, x)
		input -= 1
	end
	local buf = buffer_create(#bytes)
	for i, v in pairs(bytes) do
		buffer_writeu8(buf, i - 1, v)
	end
	return buf
end

local function OutlineMoment(v)
	local buf
	local func
	local off
	local dat = v.Data
	if v.comp then
		buf = buffer_create(#dat * 4 + 1)
		func = buffer_writef32
		off = 4
	else
		buf = buffer_create(#dat * 8 + 1)
		func = buffer_writef64
		off = 8
	end
	buffer_writeu8(buf, 0, (if v.comp then 1 else 0))
	for i, d in pairs(dat) do
		func(buf, (i - 1) * off + 1, d)
	end
	return buf
end

local function toByte(num)
	return math_clamp(math_floor(num * 255), 0, 255)
end

local functions
functions = {
	function(v) -- String
		local varlen = encodeModule.EncodeVarLength(v.CompressMode == 3 and buffer.len(v.Data) or #v.Data)
		local buf = MergeBuffers(varlen, BufByte(v.CompressMode), (v.CompressMode == 3 and v.Data or ToBuffer(v)))
		return buf
	end, 
	function(v) -- Boolean5
		local buf = buffer_create(1)
		buffer_writeu8(buf, 0, v.Value)
		return buf
	end, 
	function(v) -- UInt8
		local buf = buffer_create(1)
		buffer_writeu8(buf, 0, v.Value)
		return buf
	end, 
	function(v) -- UInt16
		local buf = buffer_create(2)
		buffer_writeu16(buf, 0, v.Value)
		return buf
	end, 
	function(v) -- UInt32
		local buf = buffer_create(4)
		buffer_writeu32(buf, 0, v.Value)
		return buf
	end, 
	function(v) -- float
		local buf = buffer_create(4)
		buffer_writef32(buf, 0, v.Value)
		return buf
	end, 
	function(v) -- double
		local buf = buffer_create(8)
		buffer_writef64(buf, 0, v.Value)
		return buf
	end, 
	function(v) -- Vector2
		return OutlineMoment(v)
	end, 
	function(v) -- Vector3
		return OutlineMoment(v)
	end, 

	function(v) -- CFrame
		--> roblox always stores cframes as 3 f32s for position and 9 i16s for rotation matrices
		--> since the rotation vectors are always perpendicular we can only save two
		--> and reconstruct the other when decoding from cross product

		local x, y, z, r00, r01, r02, r10, r11, r12, _, _, _ = unpack(v.Data)

		local buf = buffer_create(24)
		--> position
		buffer_writef32(buf, 0, x); buffer_writef32(buf, 4, y); buffer_writef32(buf, 8, z)

		--> rotation vector 1
		buffer_writei16(buf, 12, toI16(r00)); buffer_writei16(buf, 14, toI16(r01)); buffer_writei16(buf, 16, toI16(r02))

		--> rotation vector 2
		buffer_writei16(buf, 18, toI16(r10)); buffer_writei16(buf, 20, toI16(r11)); buffer_writei16(buf, 22, toI16(r12))

		return buf
	end, 

	function(v) -- CFrameEuler
		return OutlineMoment(v)
	end, 
	function(v,  ident) -- Color3
		local buf
		local func
		local off
		local dat = v.Data
		if v.comp then
			buf = buffer_create(#dat * 4 + 2)
			func = buffer_writef32
			off = 4
		else
			buf = buffer_create(#dat * 8 + 2)
			func = buffer_writef64
			off = 8
		end
		local o = 1
		if ident == false then
			o = 0
		else
			buffer_writeu8(buf, 0, (if v.Brick then 1 else 0))
		end
		buffer_writeu8(buf, o, (if v.comp then 1 else 0))
		for i, d in pairs(dat) do
			func(buf, (i - 1) * off + (o + 1), d)
		end
		return buf
	end, 
	function(v, ident) -- Color3b
		local buf = buffer_create(4)
		local o = 1
		if ident == false then
			o = 0
		else
			buffer_writeu8(buf, 0, (if v.Brick then 1 else 0))
		end
		buffer_writeu8(buf, o, v.R)
		buffer_writeu8(buf, o + 1, v.G)
		buffer_writeu8(buf, o + 2, v.B)
		return buf
	end, 
	function(v) -- Table
		local objs = {}
		local total = 0
		for _, a in pairs(v.Value) do
			local buf = functions[a.DataType + 1](a)
			total += buffer_len(buf)
			table_insert(objs, buf)
		end
		local out = buffer_create(total)
		total = 0
		for _, v in pairs(objs) do
			local len = buffer_len(v)
			buffer_copy(out, total, v, 0, len)
			total += len
		end
		return out
	end, 
	nil, -- DO NOT USE: End marker for tables.
	nil, -- DO NOT USE: Handled elsewhere, begin marker for dictionaries.
	function(v) -- nil
		return buffer_create(0)
	end, 
	function(v) -- ColorSequence
		local func
		local off
		local dat = v.Data
		local kp = v.Value.Keypoints
		local count = #kp
		if v.comp1 then
			func = buffer_writef32
			off = 4
		else
			func = buffer_writef64
			off = 8
		end
		local sz = (if v.comp2 then 3 else off * 3) * count + 2
		local varlen = encodeModule.EncodeVarLength(count)
		local lensz = buffer_len(varlen)
		local buf = buffer_create(count * off + sz + lensz)
		buffer_copy(buf, 0, varlen, 0, lensz)
		buffer_writeu8(buf, lensz, (if v.comp1 then 1 else 0))
		buffer_writeu8(buf, lensz + 1, (if v.comp2 then 1 else 0))
		local pos = lensz + 2
		for _, k in kp do
			func(buf, pos, k.Time)
			pos += off
		end
		for _, k in kp do
			local c = k.Value
			if v.comp2 then
				buffer_writeu8(buf, pos, toByte(c.R))
				buffer_writeu8(buf, pos + 1, toByte(c.G))
				buffer_writeu8(buf, pos + 2, toByte(c.B))
				pos += 3
			else
				-- looks dumb but should technically be faster
				func(buf, pos, c.R)
				pos += off
				func(buf, pos, c.G)
				pos += off
				func(buf, pos, c.B)
				pos += off
			end
		end
		return buf
	end, 
	function(v) -- Vector2int16
		local buf = buffer_create(4)
		buffer_writeu16(buf, 0, v.Data[1] + 32768)
		buffer_writeu16(buf, 2, v.Data[2] + 32768)
		return buf
	end, 
	function(v) -- Vector3int16
		local buf = buffer_create(6)
		buffer_writeu16(buf, 0, v.Data[1] + 32768)
		buffer_writeu16(buf, 2, v.Data[2] + 32768)
		buffer_writeu16(buf, 4, v.Data[3] + 32768)
		return buf
	end, 
	function(v) -- EnumItem
		local buf = buffer_create(4)
		buffer_writeu16(buf, 0, v.Data[1]) -- value
		buffer_writeu16(buf, 2, v.Data[2]) -- enum index
		return buf
	end, 
	function(v) -- UDim2
		local dat = v.Data
		local buf = buffer_create(#dat * 4)
		for i, d in pairs(dat) do
			buffer_writef32(buf, (i - 1) * 4, d)
		end
		return buf
	end, 
	function(v) -- UDim
		local dat = v.Data
		local buf = buffer_create(#dat * 4)
		for i, d in pairs(dat) do
			buffer_writef32(buf, (i - 1) * 4, d)
		end
		return buf
	end, 
	function(v) -- NumberSequence
		local func
		local off
		local dat = v.Data
		local kp = v.Value.Keypoints
		local count = #kp
		if v.comp1 then
			func = buffer_writef32
			off = 4
		else
			func = buffer_writef64
			off = 8
		end
		local varlen = encodeModule.EncodeVarLength(count)
		local lensz = buffer_len(varlen)
		local buf = buffer_create((count * off * 3) + lensz + 1)
		buffer_copy(buf, 0, varlen, 0, lensz)
		buffer_writeu8(buf, lensz, (if v.comp1 then 1 else 0))
		local pos = lensz + 1
		for _, k in kp do
			func(buf, pos, k.Time)
			pos += off
		end
		for _, k in kp do
			func(buf, pos, k.Value)
			pos += off
			func(buf, pos, k.Envelope)
			pos += off
		end
		return buf
	end, 
	function(v) -- NumberRange
		local func
		local off
		local data = v.Value
		if v.comp1 then
			func = buffer_writef32
			off = 4
		else
			func = buffer_writef64
			off = 8
		end
		local buf = buffer_create(off * 2 + 1)
		buffer_writeu8(buf, 0, (if v.comp1 then 1 else 0))
		func(buf, 1, data.Min)
		func(buf, off + 1, data.Max)
		return buf
	end, 
}

encodeModule.Convert = function(v)
	return functions[v.DataType + 1](v)
end

return encodeModule