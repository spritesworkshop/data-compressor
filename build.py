import os
import sys

def read_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write_file(path, data):
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)

current_dir = os.path.dirname(os.path.abspath(__file__))

netShrink_source   = read_file(os.path.join(current_dir, "NetShrink.lua"))
compression_source = read_file(os.path.join(current_dir, "Compression.lua"))
decode_source      = read_file(os.path.join(current_dir, "Decode.lua"))
encode_source      = read_file(os.path.join(current_dir, "Encode.lua"))

# xml source
a = """<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
	<Meta name="ExplicitAutoJoints">true</Meta>
	<External>null</External>
	<External>nil</External>
	<Item class="ModuleScript" referent="RBXCF9A5091F9304DA1967DA407EE4E9DD7">
		<Properties>
			<Content name="LinkedSource"><null></null></Content>
			<ProtectedString name="Source"><![CDATA["""
b = """]]></ProtectedString>
			<string name="ScriptGuid">{811C51CF-A729-449F-AF3D-49CFE1D59C1E}</string>
			<BinaryString name="AttributesSerialize"></BinaryString>
			<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>
			<bool name="DefinesCapabilities">false</bool>
			<string name="Name">"""
c = """</string>
			<int64 name="SourceAssetId">-1</int64>
			<BinaryString name="Tags"></BinaryString>
		</Properties>
		<Item class="ModuleScript" referent="RBX67148BA2C72C42B48CC7C6F742EF4E15">
			<Properties>
				<Content name="LinkedSource"><null></null></Content>
				<ProtectedString name="Source"><![CDATA["""
d = """]]></ProtectedString>
				<string name="ScriptGuid">{74984691-70D0-42B0-818C-7588B08C92EE}</string>
				<BinaryString name="AttributesSerialize"></BinaryString>
				<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>
				<bool name="DefinesCapabilities">false</bool>
				<string name="Name">Compression</string>
				<int64 name="SourceAssetId">-1</int64>
				<BinaryString name="Tags"></BinaryString>
			</Properties>
		</Item>
		<Item class="ModuleScript" referent="RBX06C6093F93AD48028BFF0445BC25EACA">
			<Properties>
				<Content name="LinkedSource"><null></null></Content>
				<ProtectedString name="Source"><![CDATA["""
e = """]]></ProtectedString>
				<string name="ScriptGuid">{3D83CB4F-02AA-4BC5-AEE4-17BA40F5F471}</string>
				<BinaryString name="AttributesSerialize"></BinaryString>
				<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>
				<bool name="DefinesCapabilities">false</bool>
				<string name="Name">Decode</string>
				<int64 name="SourceAssetId">-1</int64>
				<BinaryString name="Tags"></BinaryString>
			</Properties>
		</Item>
		<Item class="ModuleScript" referent="RBX39B8037F67F64A0885BE2BAA9DD59CAB">
			<Properties>
				<Content name="LinkedSource"><null></null></Content>
				<ProtectedString name="Source"><![CDATA["""
f = """]]></ProtectedString>
				<string name="ScriptGuid">{3C215ACC-D38D-490B-A659-A74693B63087}</string>
				<BinaryString name="AttributesSerialize"></BinaryString>
				<SecurityCapabilities name="Capabilities">0</SecurityCapabilities>
				<bool name="DefinesCapabilities">false</bool>
				<string name="Name">Encode</string>
				<int64 name="SourceAssetId">-1</int64>
				<BinaryString name="Tags"></BinaryString>
			</Properties>
		</Item>
	</Item>
</roblox>"""

def write_package(name: str | None = None):
    if not name:
        name = "NetShrink"

    content = (
        a
        + netShrink_source
        + b
        + name
        + c
        + compression_source
        + d
        + decode_source
        + e
        + encode_source
        + f
    )

    write_file(f"{name}.rbxmx", content)

def main(name: str):
    write_package(name)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "NetShrink")