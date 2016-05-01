#!/usr/bin/env rdmd
module wad;

import std.algorithm;
import std.array;
import std.bitmanip;
import std.conv;
import std.getopt;
import std.path;
import std.range;
import std.stdio;
import std.string;
import std.traits;
import std.file: mkdir, exists, readFile = read;

import imageformats;

static immutable magicNumber = "WAD3";
enum textureNameLength = 16;
enum mipLevels = 4;
enum paletteLength = 3 * 256;

struct WadFile
{
    private ubyte[] data;
    Header header;
    DirectoryEntry[] files;
    TextureMipmaps[] newTextures;
    
    this(string filename)
    {
        data = cast(ubyte[])readFile("halflife.wad");
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
        auto filename = file.name.to!string.stripRight('\0');
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
    
    void add(Texture texture)
    {
        TextureMipmaps result;
        uint[] pixels = cast(uint[])texture.pixels;
        uint[] uniqueColors = pixels
            .sort!()
            .uniq
            .array
        ;
        
        if(uniqueColors.length > 256)
            throw new Exception("Image has too many colors"); //TODO: quantization
        
        auto palette = uniqueColors
            .map!(c => c.nativeToLittleEndian.dup.take(3))
            .join
        ;
        result.palette = palette.chain(repeat(cast(ubyte)0, paletteLength - palette.length)).array;
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
        //TODO
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
    char[textureNameLength] name;
}

struct TextureLump
{
    char[textureNameLength] name;
    uint width;
    uint height;
    uint[mipLevels] offsets;
}

struct TextureMipmaps
{
    ubyte[][mipLevels] mipmaps;
    ubyte[paletteLength] palette;
}

struct Texture
{
    uint width;
    uint height;
    ubyte[] pixels;
}

void main()
{
    auto wadName = "halflife";
    auto textures = ["{FENCE", "+0RECHARGE"];
    auto wad = WadFile("%s.wad".format(wadName));
    
    if(!wadName.exists)
        mkdir(wadName);
    
    foreach(filename; textures)
    {
        auto texture = wad.readTexture(wad.findFile(filename));
        
        write_image("%s/%s.png".format(wadName, filename), texture.width, texture.height, texture.pixels, ColFmt.RGBA);
    }
    
    wad = WadFile.init;
    
    foreach(filename; textures)
    {
        auto img = read_image("%s/%s.png".format(wadName, filename), ColFmt.RGBA);
        auto texture = Texture(img.w, img.h, img.pixels);
        
        wad.add(texture);
    }
    
    wad.write("test.wad");
}

Type unpack(Type)(const(ubyte[]) data)
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

size_t packedSize(Type)()
{
    size_t result;
    
    foreach(fieldName; __traits(allMembers, Type))
        result += mixin("Type." ~ fieldName).sizeof;
    
    return result;
}
