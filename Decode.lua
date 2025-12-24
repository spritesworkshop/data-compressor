local decodeModule = {}

local table_insert = table.insert
local bit32_band = bit32.band
local bit32_lshift = bit32.lshift
local bit32_rshift = bit32.rshift
local buffer_readu8 = buffer.readu8
local buffer_readu16 = buffer.readu16
local buffer_readi16 = buffer.readi16
local buffer_readu32 = buffer.readu32
local buffer_readf32 = buffer.readf32
local buffer_readf64 = buffer.readf64
local buffer_readstring = buffer.readstring
local buffer_copy = buffer.copy
local buffer_create = buffer.create

local Vector2_new = Vector2.new
local Vector3_new = Vector3.new
local BrickColor_new = BrickColor.new
local Color3_new = Color3.new
local Color3_fromRGB = Color3.fromRGB
local CFrame_new = CFrame.new
local CFrame_fromEulerAnglesXYZ = CFrame.fromEulerAnglesXYZ
local UDim2_new = UDim2.new
local UDnew_new = UDim.new

local EncodingService = game: GetService("EncodingService")
local Compression = require(script.Parent.Compression)

local compressModeTargets = {
	"Deflate", 
	"Zlib", 
	"ZlibNative"
}

-- local enumMap: {[Enum]: number} = {} --> number  - > enum
local enumMap = nil
local enumMapFallback = {}
for i, v in Enum: GetEnums() do
	enumMapFallback[i] = v
end

decodeModule.TryLoadEnumMap = function()
	if enumMap == nil then
		local enumStrMap = script: FindFirstChild("EnumStringMap")
		if not enumStrMap then return false end

		enumMap = {}
		for _, str in enumStrMap.Value: split(" / ") do
			local contents = str: split(" - ")
			local isValid = pcall(function() assert(Enum[contents[2]]) end)

			enumMap[tonumber(contents[1])] = (isValid and Enum[contents[2]] or "SERVER_ONLY_ENUM")
		end
	else
		return true
	end
end

decodeModule.Init = function()
	if game: GetService("RunService"): IsServer() then
		-- > we also store a stringvalue for the client to use, because the client and server have different enums
		local strMap: string = "" 
		enumMap = {}
		for i, v in Enum: GetEnums() do
			strMap ..= `{i} - {v} / `
			enumMap[i] = v
		end
		strMap = strMap: sub(1, #strMap - 1) -- remove last  / 

		if script: FindFirstChild("EnumStringMap") then return end
		local obj = Instance.new("StringValue")
		obj.Value = strMap
		obj.Name = "EnumStringMap"

		obj.Parent = script
		return
	end

	decodeModule.TryLoadEnumMap()
end

decodeModule.DecodeVarLength = function(input: buffer, offset: number)
	if not offset then offset = 0 end
	local data, shift = 0, 1
	local loop = 0
	while true do
		local x = buffer_readu8(input, loop + offset)
		data += bit32_band(x, 0x7F) * shift
		loop += 1
		if bit32_band(x, 0x80) ~= 0 then
			break
		end
		shift = bit32_lshift(shift, 7)
		data += shift
	end
	return data, loop
end

local functions = {
	function(input: buffer, offset: number) -- String
		local len, amt = decodeModule.DecodeVarLength(input, offset)
		offset += amt
		local mode = buffer_readu8(input, offset)
		offset += 1

		local str
		if mode > 0 then
			if mode == 3 then
				local strBuf = buffer_create(len)
				buffer_copy(strBuf, 0, input, offset, len)
				str = buffer.tostring(EncodingService: DecompressBuffer(strBuf, Enum.CompressionAlgorithm.Zstd))
			else
				str = buffer_readstring(input, offset, len)
				str = Compression[compressModeTargets[mode]].Decompress(str)
			end
		else
			str = buffer_readstring(input, offset, len)
		end
		offset += len
		return str, offset
	end, 
	function(input: buffer, offset: number) -- Boolean5
		local byte = buffer_readu8(input, offset)
		offset += 1
		local amt = bit32_rshift(bit32_band(byte, 224), 5) + 1
		local bools = {}
		for i = 1, amt do
			local bool = bit32_band(bit32_rshift(byte, 5 - i), 1)
			table_insert(bools, bool == 1)
		end
		if amt == 1 then bools = unpack(bools) end
		return bools, offset
	end, 
	function(input: buffer, offset: number) -- UInt8
		local byte = buffer_readu8(input, offset)
		offset += 1
		return byte, offset
	end, 
	function(input: buffer, offset: number) -- UInt16
		local val = buffer_readu16(input, offset)
		offset += 2
		return val, offset
	end, 
	function(input: buffer, offset: number) -- UInt32
		local val = buffer_readu32(input, offset)
		offset += 4
		return val, offset
	end, 
	function(input: buffer, offset: number) -- float
		local val = buffer_readf32(input, offset)
		offset += 4
		return val, offset
	end, 
	function(input: buffer, offset: number) -- double
		local val = buffer_readf64(input, offset)
		offset += 8
		return val, offset
	end, 
	function(input: buffer, offset: number) -- Vector2
		local comp = buffer_readu8(input, offset)
		local func, mult
		if comp == 1 then
			func = buffer_readf32
			mult = 1
		else
			func = buffer_readf64
			mult = 2
		end
		offset += 1
		local X = func(input, offset)
		local Y = func(input, offset + 4 * mult)
		offset += 8 * mult
		return Vector2_new(X, Y), offset
	end, 
	function(input: buffer, offset: number) -- Vector3
		local comp = buffer_readu8(input, offset)
		local func, mult
		if comp == 1 then
			func = buffer_readf32
			mult = 1
		else
			func = buffer_readf64
			mult = 2
		end
		offset += 1
		local X = func(input, offset)
		local Y = func(input, offset + 4 * mult)
		local Z = func(input, offset + 8 * mult)
		offset += 12 * mult
		return Vector3_new(X, Y, Z), offset
	end, 

	function(input: buffer, offset: number) -- CFrame
		-- > roblox always stores cframes as 3 f32s for position and 9 i16s for rotation matrices
		-- > since the rotation vectors are always perpendicular we can only save two
		-- > and reconstruct the other when decoding from cross product

		local x, y, z = buffer_readf32(input, offset), buffer_readf32(input, offset + 4), buffer_readf32(input, offset + 8)

		local r00, r01, r02 = 
			buffer_readi16(input, offset + 12) / 32767, 
		buffer_readi16(input, offset + 14) / 32767, 
		buffer_readi16(input, offset + 16) / 32767

		local r10, r11, r12 = 
			buffer_readi16(input, offset + 18) / 32767, 
		buffer_readi16(input, offset + 20) / 32767, 
		buffer_readi16(input, offset + 22) / 32767

		offset += 24

		local r2 = Vector3.new(r00, r01, r02): Cross(Vector3.new(r10, r11, r12))

		return CFrame_new(x, y, z, r00, r01, r02, r10, r11, r12, r2.X, r2.Y, r2.Z), offset
	end, 

	function(input: buffer, offset: number) -- CFrameEuler
		local comp = buffer_readu8(input, offset)
		local func, mult
		if comp == 1 then
			func = buffer_readf32
			mult = 1
		else
			func = buffer_readf64
			mult = 2
		end
		offset += 1
		local X = func(input, offset)
		local Y = func(input, offset + 4 * mult)
		local Z = func(input, offset + 8 * mult)
		local rX = func(input, offset + 12 * mult)
		local rY = func(input, offset + 16 * mult)
		local rZ = func(input, offset + 20 * mult)
		offset += 24 * mult
		return (CFrame_fromEulerAnglesXYZ(rX, rY, rZ) + Vector3_new(X, Y, Z)), offset
	end, 
	function(input: buffer, offset: number) -- Color3
		local brick = buffer_readu8(input, offset)
		local comp = buffer_readu8(input, offset + 1)
		local func, mult
		if comp == 1 then
			func = buffer_readf32
			mult = 1
		else
			func = buffer_readf64
			mult = 2
		end
		offset += 2
		local R = func(input, offset)
		local G = func(input, offset + 4 * mult)
		local B = func(input, offset + 8 * mult)
		offset += 12 * mult
		if brick == 1 then
			return BrickColor_new(R, G, B), offset
		else
			return Color3_new(R, G, B), offset
		end
	end, 
	function(input: buffer, offset: number) -- Color3b
		local brick = buffer_readu8(input, offset)
		local R = buffer_readu8(input, offset + 1)
		local G = buffer_readu8(input, offset + 2)
		local B = buffer_readu8(input, offset + 3)
		offset += 4
		if brick == 1 then
			return BrickColor_new(R / 255, G / 255, B / 255), offset
		else
			return Color3_fromRGB(R, G, B), offset
		end
	end, 
	nil, -- DO NOT USE: Handled elsewhere, begin marker for tables.
	nil, -- DO NOT USE: End marker for tables.
	nil, -- DO NOT USE: Handled elsewhere, begin marker for dictionaries.
	function(input: buffer, offset: number) -- nil
		return nil, offset
	end, 
	function(input: buffer, offset: number) -- ColorSequence
		local count, off = decodeModule.DecodeVarLength(input, offset)
		offset += off
		local float = buffer_readu8(input, offset) == 1 offset += 1
		local bytes = buffer_readu8(input, offset) == 1 offset += 1
		local times = {}
		local keypoints = {}
		local func, add
		if float then func, add = buffer_readf32, 4 else func, add = buffer_readf64, 8 end
		for i = 1, count do
			table_insert(times, func(input, offset))
			offset += add
		end
		for i = 1, count do
			local col
			if bytes then
				local r = buffer_readu8(input, offset) offset += 1
				local g = buffer_readu8(input, offset) offset += 1
				local b = buffer_readu8(input, offset) offset += 1
				col = Color3_fromRGB(r, g, b)
			else
				local r = func(input, offset) offset += add
				local g = func(input, offset) offset += add
				local b = func(input, offset) offset += add
				col = Color3_new(r, g, b)
			end
			table_insert(keypoints, ColorSequenceKeypoint.new(times[i], col))
		end
		return ColorSequence.new(keypoints), offset
	end, 
	function(input: buffer, offset: number) -- Vector2int16
		local X = buffer_readu16(input, offset) offset += 2
		local Y = buffer_readu16(input, offset) offset += 2
		return Vector2int16.new(X - 32768, Y - 32768), offset
	end, 
	function(input: buffer, offset: number) -- Vector3int16
		local X = buffer_readu16(input, offset) offset += 2
		local Y = buffer_readu16(input, offset) offset += 2
		local Z = buffer_readu16(input, offset) offset += 2
		return Vector3int16.new(X - 32768, Y - 32768, Z - 32768), offset
	end, 
	function(input: buffer, offset: number) -- EnumItem
		local value = buffer_readu8(input, offset) 
		offset += 1

		local enumIdx = buffer_readu16(input, offset)
		offset += 2

		return (enumMap or enumMapFallback)[enumIdx]: FromValue(value), offset
	end, 
	function(input: buffer, offset: number) -- UDim2
		local Xscale = buffer_readf32(input, offset)
		local Xoffset = buffer_readf32(input, offset + 4)
		local Yscale = buffer_readf32(input, offset + 8)
		local Yoffset = buffer_readf32(input, offset + 12)

		offset += 16
		return UDim2_new(Xscale, Xoffset, Yscale, Yoffset), offset
	end, 
	function(input: buffer, offset: number) -- UDim
		local scale = buffer_readf32(input, offset)
		local _offset = buffer_readf32(input, offset + 4)

		offset += 8
		return UDnew_new(scale, _offset), offset
	end, 
	function(input: buffer, offset: number) -- NumberSequence
		local count, off = decodeModule.DecodeVarLength(input, offset)
		offset += off
		local float = buffer_readu8(input, offset) == 1 offset += 1
		local times = {}
		local keypoints = {}
		local func, add
		if float then func, add = buffer_readf32, 4 else func, add = buffer_readf64, 8 end
		for i = 1, count do
			table_insert(times, func(input, offset))
			offset += add
		end
		for i = 1, count do
			local value = func(input, offset) offset += add
			local envelope = func(input, offset) offset += add
			table_insert(keypoints, NumberSequenceKeypoint.new(times[i], value, envelope))
		end
		return NumberSequence.new(keypoints), offset
	end, 
	function(input: buffer, offset: number) -- NumberRange
		local float = buffer_readu8(input, offset) == 1 offset += 1
		local func, add
		if float then func, add = buffer_readf32, 4 else func, add = buffer_readf64, 8 end
		local min = func(input, offset) offset += add
		local max = func(input, offset) offset += add
		return NumberRange.new(min, max), offset
	end, 
}

decodeModule.ReadType = function(input: buffer, offset: number, type: number)
	return functions[type + 1](input, offset)
end

return decodeModule
