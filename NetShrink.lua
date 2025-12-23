local dataCompressor = {}
dataCompressor.__index = dataCompressor

--[[

Data Compressor Module
Forked from NetShrink v1.6.0

]]

-- FAST FLAGS
local isStudio = game:GetService("RunService"):IsStudio()
local debugMode = false and isStudio -- change this if you want, enables compression fail reports for strings
local ENABLE_DEBUG_PROFILING = false and isStudio

local EncodingService = game:GetService("EncodingService")
local Compression = require(script.Compression)
local Encode = require(script.Encode)
local Decode = require(script.Decode)

--[[

Optimization Constants

Most of these do nothing if supported by FASTCALL, 
but it still optimizes cases where FASTCALL fails for whatever reason, 
replacing a GETIMPORT instruction with a MOVE instruction.

]]

local pairs = pairs
local tostring = tostring
local table_insert = table.insert
local table_remove = table.remove
local math_ceil = math.ceil
local math_min = math.min
local math_floor = math.floor
local math_clamp = math.clamp
local bit_band = bit32.band
local bit_lshift = bit32.lshift
local bit_rshift = bit32.rshift
local bit_bxor = bit32.bxor
local buffer_copy = buffer.copy
local buffer_create = buffer.create
local buffer_readu8 = buffer.readu8
local buffer_writeu8 = buffer.writeu8
local buffer_readstring = buffer.readstring
local buffer_writestring = buffer.writestring
local buffer_len = buffer.len
local debug_profilebegin_cache = debug.profilebegin
local debug_profileend_cache = debug.profileend

local compressModeTargets = {
	"Deflate", 
	"Zlib", 
	"Zstd"
}

-- Possible Storage: 2 ^ DataTypeBits
-- 2, 4, 8, 16, 32, 64, 128, 256
-- Should not exceed 8
local DataTypeBits = 5

local function debugProfileBegin(str: string)
	if ENABLE_DEBUG_PROFILING then
		debug_profilebegin_cache(str)
	end
end

local function debugProfileEnd()
	if ENABLE_DEBUG_PROFILING then
		debug_profileend_cache()
	end
end

function dataCompressor.new()
	local self = setmetatable({
		Config = {
			AutoConversion = {
				Strings = {
					CompressMode = 0, 
					CompressLevel = 1
				}, 
				Preferf32 = false, 
				Use3bColors = true, 
				UseEulerCFrames = false, 
				IncludeIndexHoles = true, 
				IndexJumpLimit = 10
			}, 
			CompressMode = 3, 
			CompressLevel = 1,
		},
	}, dataCompressor)
	return self
end

-- Encrypts/decrypts your Data Compressor Module buffer through XOR shifting using random numbers with the key as a seed
function dataCompressor:Encrypt(input: buffer, key: number)
	debugProfileBegin("Data Compressor Module.Encrypt")
	local len = buffer_len(input)
	local rand = Random.new(key + len)
	for i = 1, len do
		buffer_writeu8(input, i - 1, bit_bxor(buffer_readu8(input, i - 1), rand:NextInteger(0, 255)))
	end
	debugProfileEnd()
	return input
end

local hasLoadedEnum = false
-- Decodes a Data Compressor Module encoded buffer into the original variables
function dataCompressor:Decode(input: buffer, asTable, key)
	if key ~= nil and typeof(key) == "number" then
		-- Decrypt buffer with key
		input = self:Encrypt(input, key)
	end
	if not hasLoadedEnum then
		hasLoadedEnum = Decode.TryLoadEnumMap()
	end
	local st = buffer_readstring(input, 0, 4)
	assert(st == "NShd", "[Data Compressor Module] Cannot decode invalid buffer, expected 'NShd' header but got '"..st.."'")
	local offset = 5

	debugProfileBegin("Data Compressor Module.Decode")
	local compressMode = buffer_readu8(input, 4)
	if compressMode > 0 then
		local tgt = compressModeTargets[compressMode]
		debugProfileBegin("Decompress "..tgt)
		local len, steps = Decode.DecodeVarLength(input, 5)
		local dec
		if compressMode == 3 then
			local dataBuf = buffer_create(len)
			buffer_copy(dataBuf, 0, input, 5 + steps, len)
			dec = EncodingService:DecompressBuffer(dataBuf, Enum.CompressionAlgorithm.Zstd)
			len = buffer_len(dec)
			input = buffer_create(len)
			buffer_copy(input, 0, dec, 0, len)
		else
			local data = buffer_readstring(input, 5 + steps, len)
			dec = Compression[tgt].Decompress(data)
			len = #dec
			input = buffer_create(len)
			buffer_writestring(input, 0, dec, len)
		end
		offset = 0
		debugProfileEnd()
	end

	local dataTypesSize, read = Decode.DecodeVarLength(input, offset)
	offset += read
	local dataTypes = {}
	local bitBuffer = 0
	local bitsUsed = 0
	local byte
	for i = 1, dataTypesSize do
		while bitsUsed < DataTypeBits do
			byte = buffer_readu8(input, offset)
			offset += 1
			bitBuffer = bitBuffer + bit_lshift(byte, bitsUsed)
			bitsUsed += 8
		end
		local mask = bit_lshift(1, DataTypeBits) - 1
		local value = bit_band(bitBuffer, mask)
		table_insert(dataTypes, value)
		bitBuffer = bit_rshift(bitBuffer, DataTypeBits)
		bitsUsed -= DataTypeBits
	end
	local returns = {}
	local cur = returns
	local pos = 1
	local layers = {returns}
	local positions = {}
	local layer = 1
	local i = 1
	local dataTypeCount = #dataTypes
	local delayedNilWrites = {}
	local decodeRecursive
	decodeRecursive = function(insert)
		debugProfileBegin("decodeRecursive")
		local startLayer = layer
		while i <= dataTypeCount do
			local ty = dataTypes[i]
			if ty == 13 then
				positions[layer] = pos
				pos = 1
				layer += 1
				local new = {}
				table_insert(layers, new)
				cur = new
				i += 1
			elseif ty == 14 then
				layer -= 1
				pos = positions[layer]
				local ret = cur
				local n = layers[layer]
				table_remove(layers, layer + 1)
				cur = n
				i += 1
				if startLayer >= layer and not insert then
					layer = startLayer
					debugProfileEnd()
					return ret
				else
					n[pos] = ret
					pos += 1
				end
			elseif ty == 15 then
				local keys = {}
				local values = {}
				local tgt = keys
				local curPos = 1
				local delayedWrite = {}
				i += 1
				local swap = false
				while true do
					local ty2 = dataTypes[i]
					if ty2 == 14 then
						i += 1
						if swap then break else swap = true tgt = values curPos = 1 end
					else
						local a = decodeRecursive(false)
						if a == nil then
							table_insert(delayedWrite, {tgt, curPos})
						else
							tgt[curPos] = a
						end
						curPos += 1
					end
				end
				for _, v in delayedWrite do
					v[1][v[2]] = nil
				end
				local ret = {}
				for i = 1, math_min(#keys, #values) do
					local v1, v2 = keys[i], values[i]
					if v1 then
						if v2 == nil then
							table_insert(delayedNilWrites, {ret, v1})
						else
							ret[v1] = v2
						end
					end
				end
				if not insert then
					debugProfileEnd()
					return ret
				else
					cur[pos] = ret
					pos += 1
					--table_insert(cur, ret)
				end
			else
				local ret, r = Decode.ReadType(input, offset, ty)
				i += 1
				offset = r
				if startLayer >= layer and not insert then
					layer = startLayer
					debugProfileEnd()
					return ret
				else
					if ret ~= nil then
						cur[pos] = ret
					elseif ty == 16 then
						table_insert(delayedNilWrites, {cur, pos})
					end
					pos += 1
				end
			end
		end
		debugProfileEnd()
	end
	decodeRecursive(true)
	for _, v in delayedNilWrites do
		v[1][v[2]] = nil
	end
	debugProfileEnd()
	if asTable then
		return returns
	else
		return unpack(returns)
	end
end

local EncodeList

local max = 2 ^ DataTypeBits - 1

local function RecursiveEncode(input: {}, output, types, dictionary)
	debugProfileBegin("RecursiveEncode")
	local amt = #input
	local totals = 0
	if dictionary then
		local l1 = {}
		for i, _ in input do
			table_insert(l1, i)
		end
		totals += EncodeList(l1, output, types)
		table_insert(types, 14)
		totals += 1
	end
	totals += EncodeList(input, output, types)
	debugProfileEnd()
	return totals
end

EncodeList = function(input: {}, output, types)
	debugProfileBegin("EncodeList")
	local totals = 0
	for _, v in input do
		local t = typeof(v)
		assert(t == "table", "[Data Compressor Module] Invalid argument type for EncodeManual, expected table but got "..t)
		assert(v.DataType <= max, "[Data Compressor Module] Cannot encode DataType "..v.DataType)
		if v.DataType == 13 or v.DataType == 15 then
			table_insert(types, v.DataType)
			local a = RecursiveEncode(v.Value, output, types, v.DataType == 15)
			table_insert(types, 14)
			totals += a + 2
		else
			table_insert(types, v.DataType)
			local enc = Encode.Convert(v)
			table_insert(output, enc)
			totals += 1
		end
	end
	debugProfileEnd()
	return totals
end

function dataCompressor:IsDictionary(t: {})
	local ijl = self.Config.AutoConversion.IndexJumpLimit
	local shouldFill = self.Config.AutoConversion.IncludeIndexHoles
	local indexId = 1
	for i, _ in t do
		local notSequential = i ~= indexId
		if typeof(i) ~= "number" or i % 1 ~= 0 then
			return true
		elseif notSequential then
			if not shouldFill or i - indexId > ijl then -- This index jump is too large to be filled
				return true
			end
		end
		indexId += 1
	end
	return #t ~= table.maxn(t)
end

-- Encodes Data Compressor Module data types into a buffer and returns said buffer
function dataCompressor:EncodeManual(...)
	debugProfileBegin("Data Compressor Module.EncodeManual")
	local dataTypes = {}
	local encodedData = {}
	local dataTypesSize = RecursiveEncode({...}, encodedData, dataTypes)
	local varlen = Encode.EncodeVarLength(dataTypesSize)
	local vls = buffer_len(varlen)
	local offset = vls
	local dataTypesBuffer = buffer_create(vls + math_ceil(dataTypesSize * DataTypeBits / 8))
	buffer_copy(dataTypesBuffer, 0, varlen, 0, vls)
	local bitBuffer = 0
	local bitsUsed = 0
	for _, v in pairs(dataTypes) do
		bitBuffer += bit_lshift(v, bitsUsed)
		bitsUsed += DataTypeBits
		if bitsUsed >= 8 then
			buffer_writeu8(dataTypesBuffer, offset, bit_band(bitBuffer, 0xFF))
			bitBuffer = bit_rshift(bitBuffer, 8)
			bitsUsed -= 8
			offset += 1
		end
	end
	if bitsUsed > 0 then
		buffer_writeu8(dataTypesBuffer, offset, bitBuffer)
		offset += 1
	end
	local encodedDataSize = 0
	for _, v in pairs(encodedData) do
		encodedDataSize += buffer_len(v)
	end
	local finalBuffer = buffer_create(offset + encodedDataSize)
	buffer_copy(finalBuffer, 0, dataTypesBuffer, 0, offset)
	local finalOffset = offset
	for _, v in pairs(encodedData) do
		local s = buffer_len(v)
		buffer_copy(finalBuffer, finalOffset, v, 0, s)
		finalOffset += s
	end

	local cfg = self.Config
	local cm = cfg.CompressMode
	if cm > 0 then
		local cl = cfg.CompressLevel
		if cm == 3 then
			local lenBuffer = buffer_len(finalBuffer)
			local compBuffer = EncodingService:CompressBuffer(finalBuffer, Enum.CompressionAlgorithm.Zstd, cl)
			local complen = buffer_len(compBuffer)
			if complen < lenBuffer then
				local lenAsBytes = Encode.EncodeVarLength(complen)
				local lenbytecount = buffer_len(lenAsBytes)
				local finalBuffer2 = buffer_create(complen + 5 + lenbytecount)
				buffer_writestring(finalBuffer2, 0, "NShd", 4)
				buffer_writeu8(finalBuffer2, 4, cm)
				buffer_copy(finalBuffer2, 5, lenAsBytes, 0, lenbytecount)
				buffer_copy(finalBuffer2, 5 + lenbytecount, compBuffer, 0, complen)
				debugProfileEnd()
				return finalBuffer2
			end
		else
			local tgt = Compression[compressModeTargets[cm]]
			local lenBuffer = buffer_len(finalBuffer)
			local compString = tgt.Compress(buffer_readstring(finalBuffer, 0, lenBuffer), {level=cl, strategy = "fixed"})
			local complen = #compString
			if complen < lenBuffer then
				local lenAsBytes = Encode.EncodeVarLength(complen)
				local lenbytecount = buffer_len(lenAsBytes)
				local finalBuffer2 = buffer_create(complen+5+lenbytecount)
				buffer_writestring(finalBuffer2, 0, "NShd", 4)
				buffer_writeu8(finalBuffer2, 4, cm)
				buffer_copy(finalBuffer2, 5, lenAsBytes, 0, lenbytecount)
				buffer_writestring(finalBuffer2, 5 + lenbytecount, compString, complen)
				debugProfileEnd()
				return finalBuffer2
			end
		end
	end

	local lenBuffer = buffer_len(finalBuffer)
	local finalBuffer2 = buffer_create(lenBuffer + 5)
	buffer_writestring(finalBuffer2, 0, "NShd", 4)
	buffer_writeu8(finalBuffer2, 4, 0)
	buffer_copy(finalBuffer2, 5, finalBuffer, 0, lenBuffer)

	debugProfileEnd()
	return finalBuffer2
end

-- Data Types

--[[
CompressMode:
0 - Raw
1 - Deflate
2 - Zlib

CompressLevel: 0 - 9
]]
function dataCompressor:String(input: string, compressMode: number, compressLevel: number)
	if not compressMode then compressMode = 0 end
	if not compressLevel then compressLevel = 0 end
	if compressLevel < 0 or compressLevel > 9 then return error("[Data Compressor Module] Compression level not within range 0-9") end
	if compressMode < 0 or compressMode > 3 then return error("[Data Compressor Module] Compression mode not within range 0-3") end
	local compressed = compressMode > 0 and compressLevel > 0

	if compressed then
		local new
		local newSize
		if compressMode == 3 then
			new = EncodingService:CompressBuffer(buffer.fromstring(input), Enum.CompressionAlgorithm.Zstd, compressLevel)
			newSize = buffer_len(new)
		else
			new = Compression[compressModeTargets[compressMode]].Compress(input, {
				level = compressLevel, 
				strategy = "fixed"
			})
			newSize = #new
		end
		if newSize < #input then
			input = new
		else
			if debugMode then
				print("[Data Compressor Module] Could not compress string! Gained " .. (#new-#input) .. " bytes.")
			end
			compressed = false
		end
	end

	return {
		DataType = 0, 
		CompressMode = (if compressed then compressMode else 0), 
		Data = input
	}
end

--[[
Create a Data Compressor Module data type for a collection of up to 5 booleans.
Size: 1 byte.
]]
function dataCompressor:Boolean5(...)
	local tbl = {...}
	local len = #tbl
	if len > 5 then return error("[Data Compressor Module] BooleanTables cannot hold more than 5 booleans") end
	if len == 0 then return error("[Data Compressor Module] BooleanTables cannot be empty") end
	local out = bit_lshift(len-1, 5)
	for i = 1, len do
		local val = tbl[i]
		if val then
			out += bit_lshift(1, 5 - i)
		end
	end
	return {
		DataType = 1, 
		Value = out
	}
end

--[[
Create a Data Compressor Module data type for an unsigned 8-bit integer.
Does not support decimals and ranges outside 0-255
Size: 1 byte.
]]
function dataCompressor:UInt8(num: number)
	if num < 0 then return error("[Data Compressor Module] Number for UInt8 cannot be less than 0") end
	if num > 255 then return error("[Data Compressor Module] Number for UInt8 cannot be greater than 255") end
	return {
		DataType = 2, 
		Value = num
	}
end

--[[
Create a Data Compressor Module data type for an unsigned 16-bit integer.
Does not support decimals and ranges outside 0-65535
Size: 2 bytes.
]]
function dataCompressor:UInt16(num: number)
	if num < 0 then return error("[Data Compressor Module] Number for UInt16 cannot be less than 0") end
	if num > 65535 then return error("[Data Compressor Module] Number for UInt16 cannot be greater than 65535") end
	return {
		DataType = 3, 
		Value = num
	}
end

--[[
Create a Data Compressor Module data type for an unsigned 32-bit integer.
Does not support decimals and ranges outside 0-4294967295
Size: 4 bytes.
]]
function dataCompressor:UInt32(num: number)
	if num < 0 then return error("[Data Compressor Module] Number for UInt32 cannot be less than 0") end
	if num > 4294967295 then return error("[Data Compressor Module] Number for UInt32 cannot be greater than 4294967295") end
	return {
		DataType = 4, 
		Value = num
	}
end

--[[
Create a Data Compressor Module data type for a 32-bit floating point number.
Roblox numbers use Doubles, so you may lose precision with this.
Size: 4 bytes.
]]
function dataCompressor:Single(num: number)
	return {
		DataType = 5, 
		Value = num
	}
end

--[[
Create a Data Compressor Module data type for a 64-bit floating point number.
Size: 8 bytes.
]]
function dataCompressor:Double(num: number)
	return {
		DataType = 6, 
		Value = num
	}
end

--[[
Create a Data Compressor Module data type for a Vector2.
Size: 8 bytes as float, 16 bytes as double.
]]
function dataCompressor:Vector2(input: Vector2, float: boolean)
	if not float then float = false end
	return {
		DataType = 7, 
		comp = float, 
		Data = {input.X, input.Y}
	}
end

--[[
Create a Data Compressor Module data type for a Vector2int16.
Size: 4 bytes.
]]
function dataCompressor:Vector2int16(input: Vector2int16)
	return {
		DataType = 18, 
		Data = {input.X, input.Y}
	}
end

--[[
Create a Data Compressor Module data type for a Vector3.
Size: 12 bytes as float, 24 bytes as double.
]]
function dataCompressor:Vector3(input: Vector3, float: boolean)
	if not float then float = false end
	return {
		DataType = 8, 
		comp = float, 
		Data = {input.X, input.Y, input.Z}
	}
end

--[[
Create a Data Compressor Module data type for a Vector3int16.
Size: 6 bytes.
]]
function dataCompressor:Vector3int16(input: Vector3int16)
	return {
		DataType = 19, 
		Data = {input.X, input.Y, input.Z}
	}
end

--[[
Create a Data Compressor Module data type for a CFrame.
Size: 24 bytes
]]
function dataCompressor:CFrame(input: CFrame)
	return {
		DataType = 9, 
		Data = {input:GetComponents()}
	}
end

--[[
Create a Data Compressor Module data type for a CFrame.
This variant only encodes XYZ coordinates and EulerAngles to reduce the size.
Size: 24 bytes as float, 48 bytes as double.
]]
function dataCompressor:CFrameEuler(input: CFrame, float: boolean)
	if not float then float = false end
	local rx, ry, rz = input:ToEulerAnglesXYZ()
	return {
		DataType = 10, 
		comp = float, 
		Data = {input.X, input.Y, input.Z, rx, ry, rz}
	}
end

local colorClassIndexes = { -- screw you BrickColor for having lowercase indexes >:(
	BrickColor = {"r", "g", "b"}, 
	Color3 = {"R", "G", "B"}
}

--[[
Create a Data Compressor Module data type for a Color3/BrickColor.
Size: 14 bytes as float, 26 bytes as double.
]]
function dataCompressor:Color3(input, float: boolean)
	if not float then float = false end
	local t = typeof(input)
	local idx = colorClassIndexes[t]
	return {
		DataType = 11, 
		comp = float, 
		Brick = t ~= "Color3", 
		Data = {input[idx[1]], input[idx[2]], input[idx[3]]}
	}
end

local function toByte(num)
	return math_clamp(math_floor(num * 255), 0, 255)
end

--[[
Create a Data Compressor Module data type for a Color3/BrickColor.
This variant loses some precision by converting each color channel to a single byte.
Size: 3 bytes.
]]
function dataCompressor:Color3b(input)
	local t = typeof(input)
	local idx = colorClassIndexes[t]
	return {
		DataType = 12, 
		Brick = t ~= "Color3", 
		R = toByte(input[idx[1]]), 
		G = toByte(input[idx[2]]), 
		B = toByte(input[idx[3]])
	}
end


--[[
Create a Data Compressor Module data type for a table.
This function accepts Data Compressor Module data types as entries
]]
function dataCompressor:Table(...)
	local t = {}
	for _, v in pairs({...}) do
		table.insert(t, v)
	end
	return {
		DataType = 13, 
		Value = t
	}
end

--[[
Create a Data Compressor Module data type for a dictionary. (table with keys)
This function accepts a dictionary, keys and values should be Data Compressor Module data types
If any value is incorrect it will be removed
]]
function dataCompressor:Dictionary(v: {})
	local t = {}
	for i, v in pairs(v) do
		local t1, t2 = typeof(i), typeof(v)
		if t1 == "table" and t2 == "table" and i.DataType and v.DataType then
			t[i] = v
		else
			warn("[Data Compressor Module] Ignoring non-datatype dictionary key: "..i)
			continue
		end
	end
	return {
		DataType = 15, 
		Value = t
	}
end

--[[
Create a Data Compressor Module data type for a nil value.
Size: 0 bytes.
]]
function dataCompressor:Nil()
	return { DataType = 16 }
end

--[[
Create a Data Compressor Module data type for a ColorSequence
Size: 3 bytes + (7/11/16/32 bytes per keypoint depending on settings).
]]
function dataCompressor:ColorSequence(input: ColorSequence, float: boolean, byte: boolean)
	return { DataType = 17, comp1 = float, comp2 = byte, Value = input }
end

local enumMapReverse: {[Enum]: number} = {} -- enum -> number
for i, v in Enum:GetEnums() do
	enumMapReverse[v] = i
end

--[[
Create a Netshrink data type for an EnumItem
Size: 3 bytes
]]
function dataCompressor:EnumItem(input: EnumItem)
	local enumIdx: number = enumMapReverse[input.EnumType] -- uint16
	local value: number = input.Value -- byte

	return { 
		DataType = 20, 
		Data = {value, enumIdx}
	}
end

--[[
Create a Netshrink data type for an UDim2
Size: 16 bytes.
]]
function dataCompressor:UDim2(input: UDim2)
	return {
		DataType = 21, 
		Data = {input.X.Scale, input.X.Offset, input.Y.Scale, input.Y.Offset}
	}
end

--[[
Create a Netshrink data type for a UDim
Size: 8 bytes.
]]
function dataCompressor:UDim(input: UDim)
	return {
		DataType = 22, 
		Data = {input.Scale, input.Offset}
	}
end

--[[
Create a Netshrink data type for a NumberSequence
Size: 2+(keypoints * 4) bytes as float, 2+(keypoints * 8) bytes as double.
]]
function dataCompressor:NumberSequence(input: UDim, float: boolean)
	return { DataType = 23, comp1 = float, Value = input }
end

--[[
Create a Netshrink data type for a NumberRange
Size: 8 bytes as float, 16 bytes as double.
]]
function dataCompressor:NumberRange(input: UDim, float: boolean)
	return { DataType = 24, comp1 = float, Value = input }
end

local function Boolean5Compatible(v: {})
	local len = #v
	if len <= 1 or len > 5 then return false end
	for i = 1, len do
		local a = v[i]
		if typeof(a) ~= "boolean" then return false end
	end
	return true
end

local conversionMapping
conversionMapping = {
	number = function(self, v: number)
		local decimal = v % 1 ~= 0
		if decimal or v < 0 or v > 4294967295 then
			local f32 = self.Config.AutoConversion.Preferf32
			return self[if f32 then "Single" else "Double"](self, v)
		end
		if v <= 255 then return self:UInt8(v) end
		if v <= 65535 then return self:UInt16(v) end
		return self:UInt32(v)
	end,
	string = function(self, v: string)
		local stringConfig = self.Config.AutoConversion.Strings
		return self:String(v, stringConfig.CompressMode, stringConfig.CompressLevel)
	end, 
	table = function(self, v: {})
		if Boolean5Compatible(v) then
			return self:Boolean5(unpack(v))
		end
		local stuff = {}
		local is_dict = self:IsDictionary(v)
		if not is_dict then -- Encode as table
			for i = 1, #v do
				local ent = v[i]
				local t = typeof(ent)
				local converter = conversionMapping[t]
				if not converter then
					warn("[Data Compressor Module] Unsupported variable type: "..t)
					continue
				end
				local result = converter(self, ent)
				if result then
					table_insert(stuff, result)
				end
			end
			return self:Table(unpack(stuff))		
		end
		-- Encode as dictionary
		for i, v in v do
			local t1, t2 = typeof(i), typeof(v)
			local c1, c2 = conversionMapping[t1], conversionMapping[t2]
			if not c1 then warn("[Data Compressor Module] Unsupported variable type: "..t1) continue end
			if not c2 then warn("[Data Compressor Module] Unsupported variable type: "..t2) continue end
			local r1, r2 = c1(self, i), c2(self, v)
			if r1 and r2 then stuff[r1] = r2 end
		end
		return self:Dictionary(stuff)
	end, 
	boolean = function(self, v: boolean)
		return self:Boolean5(v)
	end, 
	Vector2 = function(self, v: Vector2)
		return self:Vector2(v, self.Config.AutoConversion.Preferf32)
	end, 
	Vector3 = function(self, v: Vector3)
		return self:Vector3(v, self.Config.AutoConversion.Preferf32)
	end, 
	CFrame = function(self, v: CFrame)
		local ac = self.Config.AutoConversion
		return self[if ac.UseEulerCFrames then "CFrameEuler" else "CFrame"](self, v, ac.Preferf32)
	end, 
	Color3 = function(self, v)
		local ac = self.Config.AutoConversion
		if ac.Use3bColors then
			return self:Color3b(v)
		end
		return self:Color3(v, ac.Preferf32)
	end, 
	BrickColor = function(self, v: BrickColor)
		return conversionMapping.Color3(self, v) -- xd
	end, 
	['nil'] = function(self, v: nil)
		return self:Nil()
	end, 
	ColorSequence = function(self, v: ColorSequence)
		local ac = self.Config.AutoConversion
		return self:ColorSequence(v, ac.Preferf32, ac.Use3bColors)
	end, 
	Vector2int16 = function(self, v: Vector2int16)
		return self:Vector2int16(v)
	end, 
	Vector3int16 = function(self, v: Vector3int16)
		return self:Vector3int16(v)
	end, 
	EnumItem = function(self, v: EnumItem)
		return self:EnumItem(v)
	end, 
	UDim2 = function(self, v: UDim2)
		return self:UDim2(v)
	end, 
	UDim = function(self, v: UDim)
		return self:UDim(v)
	end, 
	NumberSequence = function(self, v: NumberSequence)
		return self:NumberSequence(v, self.Config.AutoConversion.Preferf32)
	end, 
	NumberRange = function(self, v: NumberSequence)
		return self:NumberRange(v, self.Config.AutoConversion.Preferf32)
	end, 
}

--[[
Variant of Data Compressor Module.Encode that requires arguments to be within a table
Should help with cases where you might exceed a register limit when unpacking.
Automatically converts variables in the table to Data Compressor Module data types then encodes it to a buffer.
]]
function dataCompressor:EncodeT(t: {})
	debugProfileBegin("Data Compressor Module.EncodeT")
	local dataTypes = {}
	local n = (t :: any).n or #(t :: {})
	debugProfileBegin("Auto-convert variables")
	for i = 1, n do
		local v = t[i] -- fixes missing nil entries
		local t = typeof(v)
		local converter = conversionMapping[t]
		if not converter then
			warn("[Data Compressor Module] Unsupported variable type: "..t)
			continue
		end
		local result = converter(self, v)
		if result then
			table_insert(dataTypes, result)
		end
	end
	debugProfileEnd()
	debugProfileBegin("Encode to buffer")
	local ret = self:EncodeManual(unpack(dataTypes))
	debugProfileEnd()
	debugProfileEnd()
	return ret
end

-- Automatically convert variables to Data Compressor Module data types and encode it to a buffer
function dataCompressor:Encode(...)
	return self:EncodeT(table.pack(...))
end

Decode.Init()
return dataCompressor
