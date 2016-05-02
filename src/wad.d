module wad;

import std.algorithm;
import std.bitmanip;
import std.file: readFile = read, writeFile = write;
import std.range;
import std.string;
import std.traits;

private static immutable magicNumber = "WAD3";
private enum textureNameLength = 16;
private enum mipLevels = 4;
private enum paletteLength = 3 * 256;
private enum typeMiptex = 67;

struct WadFile
{
    private ubyte[] data;
    Header header;
    DirectoryEntry[] files;
    PackedTexture[] newTextures;
    
    this(string filename)
    {
        data = cast(ubyte[])readFile(filename);
        header = data.unpack!Header;
        
        if(header.magicNumber != magicNumber)
            throw new Exception("Invalid wad");
        
        files.reserve(header.fileCount);
    
        foreach(fileNum; 0 .. header.fileCount)
        {
            size_t index = header.fileOffset + fileNum * packedSize!DirectoryEntry;
            DirectoryEntry file = unpack!DirectoryEntry(data[index .. $]);
            
            if(file.compressed)
                throw new Exception("File %s is compressed (unsupported)".format(file.name.ptr.fromStringz));
            
            files ~= file;
        }
    }
    
    DirectoryEntry findFile(string name)
    {
        auto found = files.find!(x => x.name.ptr.fromStringz == name);
        
        if(found.empty)
            throw new Exception("No such file: " ~ name);
        
        return found.front;
    }
    
    Texture readTexture(DirectoryEntry file)
    {
        Texture result;
        auto texture = unpack!TextureLump(data[file.offset .. $]);
        result.width = texture.width;
        result.height = texture.height;
        auto filename = file.name.ptr.fromStringz;
        auto imageLength = texture.width * texture.height;
        auto smallestMipmapLength = (texture.width / 8) * (texture.height / 8);
        auto imageStart = file.offset + texture.offsets[0];
        auto paletteStart = file.offset + texture.offsets[3] + smallestMipmapLength + 2;
        auto image = data[imageStart .. imageStart + imageLength];
        auto palette = data[paletteStart .. paletteStart + paletteLength]
            .chunks(3)
            .map!(
                c => c
                    .chain([cast(ubyte)255])
                    .retro
                    .array
                    .peek!uint
            )
            .array
        ;
        uint[] output;
        output.length = imageLength;
        
        if(filename.startsWith("{")) //has transparency
            palette[$ - 1] &= 0x00FFFFFF;
        
        foreach(index, colorIndex; image)
            output[index] = palette[colorIndex];
        
        result.pixels = cast(ubyte[])output;
        
        return result;
    }
    
    void add(Texture texture, string name)
    {
        if(name.length > textureNameLength - 1) //includes terminator
            throw new Exception("Can't add texture `%s`: name is more than 15 chars".format(name));
        
        PackedTexture result;
        result.width = texture.width;
        result.height = texture.height;
        result.name = name;
        uint[] pixels = cast(uint[])texture.pixels;
        uint[] uniqueColors = pixels
            .dup
            .sort!()
            .uniq
            .array
        ;
        bool hasAlpha = name.startsWith("{");
        
        if(uniqueColors.length > 256)
            throw new Exception("Texture `%s` has too many colors (%s)".format(name, uniqueColors.length)); //TODO: quantization
        
        uniqueColors.length = 256;
        
        if(hasAlpha) //ensure alpha color is at the end of the palette
        {
            auto alphaColorIndex = uniqueColors.countUntil(0x00FF0000);
            
            if(alphaColorIndex == -1)
                throw new Exception("Transparent texture doesn't actually have any transparent color!?");
            
            swap(uniqueColors[alphaColorIndex], uniqueColors[$ - 1]);
        }
        
        result.palette = uniqueColors
            .map!(c => c.nativeToLittleEndian.dup.take(3))
            .join
        ;
        ubyte[] masterImage;
        masterImage.length = texture.width * texture.height;
        
        foreach(index; 0 .. masterImage.length)
            masterImage[index] = cast(ubyte)uniqueColors.countUntil(pixels[index]);
        
        result.mipmaps[0] = masterImage;
        
        foreach(mipLevel; 1 .. mipLevels)
        {
            auto mipDenom = 2 ^^ mipLevel;
            uint width = texture.width / mipDenom;
            uint height = texture.height / mipDenom;
            ubyte[] mipmap;
            mipmap.length = width * height;
            
            foreach(index; 0 .. mipmap.length)
            {
                uint x = index % width;
                uint y = index / width;
                uint masterX = x * texture.width / width;
                uint masterY = y * texture.height / height;
                mipmap[index] = masterImage[masterY * texture.width + masterX];
            }
            
            result.mipmaps[mipLevel] = mipmap;
        }
        
        newTextures ~= result;
    }
    
    void write(string filename)
    {
        auto buffer = appender!(ubyte[]);
        auto files = appender!(DirectoryEntry[]);
        auto header = Header(magicNumber[0 .. 4], newTextures.length, -1);
        size_t bufferIndex = packedSize!Header;
        
        foreach(texture; newTextures)
        {
            TextureLump lump;
            lump.name[0 .. texture.name.length] = texture.name.toLower;
            lump.width = texture.width;
            lump.height = texture.height;
            
            foreach(mipLevel; 0 .. mipLevels)
                lump.offsets[mipLevel] =
                    packedSize!TextureLump +
                    texture.mipmaps[0 .. mipLevel]
                        .map!(x => x.length)
                        .sum
                ;
            
            DirectoryEntry file;
            file.offset = bufferIndex;
            file.type = typeMiptex;
            file.compressed = false;
            file.name[0 .. texture.name.length] = texture.name.toUpper;
            
            buffer.put(lump.pack);
            
            bufferIndex += packedSize!TextureLump;
            
            foreach(mipLevel; 0 .. mipLevels)
            {
                auto mipmap = texture.mipmaps[mipLevel];
                bufferIndex += mipmap.length;
                
                buffer.put(mipmap);
            }
            
            buffer.put(cast(ubyte[])[0, 0]); //padding
            buffer.put(texture.palette[0 .. $]);
            
            bufferIndex += 2 + paletteLength;
            file.diskSize = file.fullSize = bufferIndex - file.offset;
            
            files.put(file);
        }
        
        header.fileOffset = bufferIndex;
        
        foreach(file; files.data)
            buffer.put(file.pack);
        
        auto finalBuffer = appender!(ubyte[]);
        
        finalBuffer.put(header.pack);
        finalBuffer.put(buffer.data);
        writeFile(filename, finalBuffer.data);
    }
}

struct Header
{
    char[4] magicNumber;
    int fileCount;
    int fileOffset;
}

struct DirectoryEntry
{
    int offset;
    int diskSize;
    int fullSize;
    byte type;
    bool compressed;
    short unused;
    char[textureNameLength] name = 0;
}

struct TextureLump
{
    char[textureNameLength] name = 0;
    uint width;
    uint height;
    uint[mipLevels] offsets;
}

struct PackedTexture
{
    uint width;
    uint height;
    string name;
    ubyte[][mipLevels] mipmaps;
    ubyte[paletteLength] palette;
}

struct Texture
{
    uint width;
    uint height;
    ubyte[] pixels;
}

private Type unpack(Type)(const(ubyte[]) data)
{
    Type result;
    size_t index;
    
    foreach(fieldName; __traits(allMembers, Type))
    {
        alias FieldType = typeof(mixin("Type." ~ fieldName));
        
        static if(isStaticArray!FieldType)
        {
            alias ElementType = typeof(mixin("result." ~ fieldName)[0]);
            mixin("result." ~ fieldName) = cast(ElementType[])data[index .. index + FieldType.length * ElementType.sizeof];
            index += FieldType.length;
        }
        else
        {
            mixin("result." ~ fieldName) = data[index .. $].peek!(FieldType, Endian.littleEndian);
            index += FieldType.sizeof;
        }
    }
    
    return result;
}

private ubyte[] pack(Type)(Type data)
{
    ubyte[] result;
    result.length = packedSize!Type;
    size_t index;
    
    foreach(fieldName; __traits(allMembers, Type))
    {
        alias FieldType = typeof(mixin("Type." ~ fieldName));
        
        static if(isStaticArray!FieldType)
            foreach(item; mixin("data." ~ fieldName))
            {
                result[index .. index + item.sizeof] = nativeToLittleEndian(item);
                index += item.sizeof;
            }
        else
        {
            result[index .. index + FieldType.sizeof] = nativeToLittleEndian(mixin("data." ~ fieldName));
            index += FieldType.sizeof;
        }
    }
    
    return result;
}

private size_t packedSize(Type)()
{
    size_t result;
    
    foreach(fieldName; __traits(allMembers, Type))
        result += mixin("Type." ~ fieldName).sizeof;
    
    return result;
}