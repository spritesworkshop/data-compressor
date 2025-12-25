# DCM
DCM, short for Data Compression Module, is a Roblox module that compresses various data types into a buffer for easy storage, compression and encryption. Forked off of [NetShrink](https://github.com/EmK530/NetShrink/) by EmK530.
exact same thing but i changed how it worked and a couple things

## Credits
DEFLATE/Zlib module not created by me, [see the original asset here](https://create.roblox.com/store/asset/5649237524)

## How to use
Either download the rbxmx from the [Releases](https://github.com/spritesworkshop/data-compressor/releases) section, or set it up yourself.<br>
You can build the project by running `build.py` file with Python. You can optionally set the output file name by providing it as an argument:<br>
```bash
python build.py Compressor
```
Alternatively, you can set it up yourself with the 4 source scripts.<br>
NetShrink is the main script you will be requiring. The three other scripts should be children of the DCM module as demonstrated.<br>
<img src="https://i.imgur.com/GJjvz2y.png"><br>

## Initalizing DCM
DCM compared to NetShrink now uses a class based system. To create a new instance:
```lua
local NetShrink = require(Path.To.NetShrink)
local compressor = NetShrink.new()
```

From there, you can set the config for the compressor through its instance.

## Encoding data for transmission
To encode data into a buffer, you call the `compressor:Encode()` function which takes a variable number of arguments.<br>
If you want to encode a table of arguments to avoid register limits, DCM offers a variant called `compressor:EncodeT()`<br>
These arguments you send will be the variables you compress into the buffer for transmission.<br>
Here is a code example of how you encode data:
```lua
local encoded = compressor:Encode(
	123,
	{["test1"] = "test2"},
	0.5
)
print("Successfully encoded to "..buffer.len(encoded).." bytes.")
```
<br>
<b>To reduce data usage, see the section "<a href="https://github.com//DCM#Optimizing-data-usage">Optimizing data usage</a>"</b><br>
<b>To optimize performance, see the section "<a href="https://github.com//DCM#Optimizing-performance">Optimizing performance</a>"</b>

## Encrypting data
Once you've ran `compressor:Encode()` and gotten your buffer, you can also choose to encrypt it using `compressor:Encrypt()`<br>
This function takes two arguments, the buffer and a numeric key to use for encryption and it will return the encrypted buffer.<br>
The encryption works by using the number as a seed to randomly XOR shift every single byte.<br>
To decrypt you have two options, either use `compressor:Encrypt()` again with the same key, or see the section "[Decoding data](https://github.com//DCM#Decoding-data)"

## Decoding data
To decode data from a buffer, call the `compressor:Decode()` function.<br>
This function takes a `buffer` as an input but also optionally a `boolean` and a `number`.<br>
The buffer is of course what's being decoded but if you send `true` as the second argument,<br>
the function returns the decoded variables in a table instead of multiple return values.<br>
If a third argument is given (must be `number`) then it will decrypt the input buffer with the argument as the key, before decoding.<br>
This argument must be used if you are decoding an encrypted buffer and the key must match what was used during encoding.

If we are trying to decode our example transmission, here's a simple example:
```lua
print(compressor:Decode(encoded, true)) -- prints a table
print(compressor:Decode(encoded)) -- prints: 123 {...} 0.5
```
If `encoded` was encrypted, adding the key used during encoding as the third argument to Decode will make sure the buffer is read correctly.

## Optimizing performance
Compression is an expensive part of compressor:<br>
If you need to perform a lot of encode/decode operations for cases like Multiplayer, it is recommended to disable compression.<br>
To do this, you mainly want to set `compressor.Config.CompressMode` to 0 to not pass the output through EncodingService.<br>
This increases the output size, so check the section "<a href="https://github.com/spritesworkshop/data-compressor#Optimizing-data-usage">Optimizing data usage</a>" to find ways to counter that.

## Optimizing data usage
Now that DCM's recommended encoding method is to handle type conversion automatically,<br>
there are some configs offered to control how aggressive the compression should be for auto conversion.<br>
These settings are accessible through `compressor.Config.AutoConversion` and here are all the currently available settings:<br>
#### Strings.CompressMode
Controls the compression method that is attempted on all converted strings. Unnecessary and not recommended for performance.<br>
**Default value: 0 (None)**

#### Strings.CompressLevel
Controls the compression level that is used with the compression method, ignored if CompressMode is 0.<br>
**Default value: 1**

#### Preferf32
Compresses all floating point numbers as 32-bit, not 64-bit, cutting data size and precision in half. Applies to:<br>
- Decimal Numbers
- Vector2/Vector3
- CFrame
- Color3 (if Use3bColors is false)

**Default value: false**

#### Use3bColors
Compresses every Color3 channel as a UInt8 instead of a floating point number, reducing size from 12/24 bytes to 3 bytes.<br>
**Default value: true**

#### UseEulerCFrames
Compresses CFrames with only XYZ coordinates and euler angles.<br>
<b>Do not enable, compressed size is worse on v1.5.2, improvements coming soon.</b><br>
**Default value: false**

#### IncludeIndexHoles
This setting influences detection between tables and dictionaries, if a table like `{true, nil, false}` is passed,<br>
it notices an index jump from 1 to 3 but encodes the missing index as nil if the table is not detected as a dictionary.<br>
**Default value: true**

#### IndexJumpLimit
This setting only matters if IncludeIndexHoles is true, this limits the max allowed index jump from nil values when checking<br>
if a table is a dictionary for safety reasons. If you have way too many nil values separating non-nil values in a table try increasing this value to preserve them.<br>
**Default value: 10**
<hr>

There are also settings available for how the entire buffer gets compressed, accessible in `compressor.Config`:

#### CompressMode
The compression method that will be used on the final buffer output to reduce size. Not recommended for performance.<br>
**Default value: 3 (EncodingService Zstd)**<br>
Supported values: 0: `None`, 1: `DEFLATE`, 2: `Zlib`, 3: `EncodingService Zstd` (EncodingService should be faster as it is native)

#### CompressLevel
The compression level that will be used by the compression method, ignored if CompressMode is 0.<br>
**Default value: 1**

#### DebugProfiling
Adds debug profiling for encode/decode processes to measure execution time in the Micro Profiler.<br>
**Default value: false**

## What's with these type functions?
Before DCM updated to v1.3, you would have to convert your variables to DCM data types manually.<br>
This is handled automatically now, but you also have the choice to do the conversion yourself with `compressor:EncodeManual`<br>
Here's a code example of encoding with EncodeManual, and below you will find [Documentation](https://github.com/spritesworkshop/data-compressor#Documentation) of all types you can encode.<br>
```lua
local encoded = compressor:EncodeManual(
	compressor:UInt8(127),
	compressor:UInt16(65533),
	compressor:UInt32(4294967295),
	compressor:Table(compressor:Single(0.5)),
	compressor:Dictionary({[compressor:String("test", 0, 0)] = compressor:Boolean5(true)})
)
```

## Documentation
Below is a list of all supported data types and their respective functions and documentation.
- [String](https://github.com/spritesworkshop/data-compressor#string)
- [Boolean5](https://github.com/spritesworkshop/data-compressor#boolean5)
- [UInt8](https://github.com/spritesworkshop/data-compressor#uint8)
- [UInt16](https://github.com/spritesworkshop/data-compressor#uint16)
- [UInt32](https://github.com/spritesworkshop/data-compressor#uint32)
- [Single](https://github.com/spritesworkshop/data-compressor#single)
- [Double](https://github.com/spritesworkshop/data-compressor#double)
- [Vector2](https://github.com/spritesworkshop/data-compressor#vector2)
- [Vector2int16](https://github.com/spritesworkshop/data-compressor#vector2int16)
- [Vector3](https://github.com/spritesworkshop/data-compressor#vector3)
- [Vector3int16](https://github.com/spritesworkshop/data-compressor#vector3int16)
- [CFrame](https://github.com/spritesworkshop/data-compressor#cframe)
- [CFrameEuler](https://github.com/spritesworkshop/data-compressor#cframeeuler)
- [Color3](https://github.com/spritesworkshop/data-compressor#color3)
- [Color3b](https://github.com/spritesworkshop/data-compressor#color3b)
- [ColorSequence](https://github.com/spritesworkshop/data-compressor#colorsequence)
- [Table](https://github.com/spritesworkshop/data-compressor#table)
- [Dictionary](https://github.com/spritesworkshop/data-compressor#dictionary)
- [Nil](https://github.com/spritesworkshop/data-compressor#nil)
- [EnumItem](https://github.com/spritesworkshop/data-compressor#EnumItem)
- [UDim](https://github.com/spritesworkshop/data-compressor#UDim)
- [UDim2](https://github.com/spritesworkshop/data-compressor#UDim2)
- [NumberSequence](https://github.com/spritesworkshop/data-compressor#NumberSequence)
- [NumberRange](https://github.com/spritesworkshop/data-compressor#NumberRange)
<hr>

### String
Stores a string with optional compression methods.<br>
Arguments: `input: string`, `compressMode: number`, `compressLevel: number`<br>
`compressMode`: Controls what compression method to use, (0: `None`, 1: `DEFLATE`, 2: `Zlib`, 3: `EncodingService Zstd`)<br>
`compressLevel`: Controls the compression level, higher takes longer to process, range: 0-9<br>
Example: `compressor:String("aaaaaaaaaaaaa", 1, 9)`
<hr>

### Boolean5
Stores up to 5 booleans into one byte.<br>
Arguments: `...`, only booleans can be sent, exceeding 5 arguments or sending none causes an error.<br>
If more than one boolean is encoded, it decodes as a table of booleans.<br>
Example: `compressor:Boolean5(true, true, false, false, true)`
<hr>

### UInt8
Stores a number from 0-255 into one byte.<br>
Arguments: `num: number`, any number out of range will cause an error<br>
Example: `compressor:UInt8(127)`
<hr>

### UInt16
Stores a number from 0-65535 into one byte.<br>
Arguments: `num: number`, any number out of range will cause an error<br>
Example: `compressor:UInt16(32767)`
<hr>

### UInt32
Stores a number from 0-4294967295 into one byte.<br>
Arguments: `num: number`, any number out of range will cause an error<br>
Example: `compressor:UInt32(2147483647)`
<hr>

### Single
Stores a number as a 4-byte single-precision floating point. This risks losing some precision over normal number variables.<br>
Arguments: `num: number`<br>
Example: `compressor:Single(34578547893347589)` (this loses precision and becomes 34578547624378370)
<hr>

### Double
Stores a number as a 8-byte double-precision floating point. The standard number variable data type.<br>
Arguments: `num: number`<br>
Example: `compressor:Double(34578547893347589)`
<hr>

### Vector2
Stores a Vector2 with an option to use single-precision to reduce size by half.<br>
Sizes: `Single-precision: 8 bytes`, `Double-precision: 16 bytes.`<br>
Arguments: `input: Vector2`, `float: boolean`, setting `float` to true will encode the Vector2 as single-precision, sacrificing precision for size.<br>
Example: `compressor:Vector2(Vector2.new(384956, 29538), true)`, this encodes as single-precision.
<hr>

### Vector2int16
Stores a Vector2int16 into 4 bytes.<br>
Arguments: `input: Vector2int16`<br>
Example: `compressor:Vector2int16(Vector2int16.new(32767, -32768))`
<hr>

### Vector3
Stores a Vector3 with an option to use single-precision to reduce size by half.<br>
Sizes: `Single-precision: 12 bytes`, `Double-precision: 24 bytes.`<br>
Arguments: `input: Vector3`, `float: boolean`, setting `float` to true will encode the Vector3 as single-precision, sacrificing precision for size.<br>
Example: `compressor:Vector3(Vector3.new(384956, 29538, 347835), true)`, this encodes as single-precision.
<hr>

### Vector3int16
Stores a Vector3int16 into 6 bytes.<br>
Arguments: `input: Vector3int16`<br>
Example: `compressor:Vector3int16(Vector3int16.new(32767, -32768, 16384))`
<hr>

### CFrame
Stores a CFrame into 24 bytes.<br>
Arguments: `input: CFrame`<br>
Example: `compressor:CFrame(workspace.SpawnLocation.CFrame)`
<hr>

### CFrameEuler
Stores a CFrame with an option to use single-precision to reduce size by half.<br>
This variant only stores XYZ coordinates and XYZ EulerAngles from the `ToEulerAnglesXYZ` function to save space.<br>
Sizes: `Single-precision: 24 bytes`, `Double-precision: 48 bytes.`<br>
Arguments: `input: CFrame`, `float: boolean`, setting `float` to true will encode the CFrame as single-precision, sacrificing precision for size.<br>
Example: `compressor:CFrameEuler(workspace.SpawnLocation.CFrame, true)`, this encodes as single-precision.
<hr>

### Color3
Stores a Color3/BrickColor with an option to use single-precision to reduce size by half.<br>
Sizes: `Single-precision: 14 bytes`, `Double-precision: 26 bytes.`<br>
Arguments: `input: Color3/BrickColor`, `float: boolean`, setting `float` to true will encode the color as single-precision, sacrificing precision for size.<br>
Example: `compressor:Color3(Color3.fromRGB(255, 127, 64), true)`, this encodes a Color3 as single-precision.<br>
Example #2: `compressor:Color3(BrickColor.new("Bright red"))`, this encodes a BrickColor as double-precision.
<hr>

### Color3b
Stores a Color3/BrickColor as a 3-byte RGB value from 0-255. Any number outside this range will be clamped.<br>
Arguments: `input: Color3/BrickColor`<br>
Example: `compressor:Color3b(Color3.fromRGB(255, 127, 64))` or `compressor:Color3b(BrickColor.new("Bright red"))`
<hr>

### ColorSequence
Stores a ColorSequence with two options, "float" for encoding all decimal numbers as single-precision and "byte" for using 3-byte colors.<br>
Sizes: `3 bytes` + `7/11/16/32 bytes`, size varies with input settings.<br>
Arguments: `input: ColorSequence`, `float: boolean`, `byte: boolean`<br>
Example: `compressor:ColorSequence(ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 255))}), true, true)`
<hr>

### Table
Accepts a variable number of data type arguments and instructs DCM to encode them into a table.<br>
Tables can be placed within eachother endlessly. Cost per table is 1.25 bytes.<br>
Arguments: `...`<br>
Example: `compressor:Table(compressor:UInt8(127), compressor:UInt16(32767))`
<hr>

### Dictionary
Accepts a table with DCM DataType keys & values and encodes as a dictionary.<br>
Like with tables, you can have dictionaries in dictionaries. Cost per dictionary is 1.875 bytes.<br>
Arguments: `input: {}`<br>
Example: `compressor:Dictionary({[compressor:String("testKey", 0, 0)] = compressor:UInt8(123)})`
<hr>

### Nil
Stores a nil value, that's about it.<br>
Example: `compressor:Nil()`
<hr>

### EnumItem
Stores an EnumItem as one 1-byte value and one 2-byte value.<br>
Arguments: `input: EnumItem`<br/>
Example: `compressor:EnumItem(Enum.EasingDirection.Out)`
<hr>

### UDim
Stores a UDim with Scale and Offset as 8 bytes.<br>
UDims are hardcoded as single-precision so double-precision is not available for this DataType.<br>
Arguments: `input: UDim`<br>
Example: `compressor:UDim(UDim.new(120, 346))`
<hr>

### UDim2
Stores a UDim2 with Scale and Offset as 16 bytes.<br>
UDim2s are hardcoded as single-precision so double-precision is not available for this DataType.<br>
Arguments: `input: UDim2`<br>
Example: `compressor:UDim2(UDim2.new(120, 346, 81, 299))`
<hr>

### NumberSequence
Stores a NumberSequence with an option to use single-precision to reduce size by half.<br>
Size: 2+(keypoints * 4) bytes as single-precision, 2+(keypoints * 8) bytes as double-precision.
Arguments: `input: NumberSequence, float: boolean`<br>
Example: `compressor:NumberSequence(NumberSequence.new(0, 10), true)`
<hr>

### NumberRange
Stores a NumberRange with an option to use single-precision to reduce size by half.<br>
Size: 8 bytes as single-precision, 16 bytes as double-precision.
Arguments: `input: NumberRange, float: boolean`<br>
Example: `compressor:NumberRange(NumberRange.new(3, 5), true)`
<hr>
