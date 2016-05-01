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

struct WadFile
{
    private ubyte[] data;
    Header header;
    DirectoryEntry[] files;
    
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
            files ~= unpack!DirectoryEntry(data[index .. $]);
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
        enum paletteLength = 3 * 256;
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

struct Texture
{
    uint width;
    uint height;
    ubyte[] pixels;
}

void main()
{
    auto wad = WadFile("halflife.wad");
    
    if(!"halflife".exists)
        mkdir("halflife");
    
    auto filename = "{FENCE";
    auto texture = wad.readTexture(wad.findFile(filename));
    
    write_image("halflife/%s.png".format(filename), texture.width, texture.height, texture.pixels, ColFmt.RGBA);
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
