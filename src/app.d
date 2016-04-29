#!/usr/bin/env rdmd
module wad;

import std.algorithm;
import std.array;
import std.bitmanip;
import std.conv;
import std.getopt;
import std.range;
import std.stdio;
import std.string;
import std.traits;
static import std.file;

enum textureNameLength = 16;
enum mipLevels = 4;

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

struct Texture
{
    char[textureNameLength] name;
    uint width;
    uint height;
    uint[mipLevels] offsets;
}

void main()
{
    auto data = cast(ubyte[])std.file.read("halflife.wad");
    auto header = data.unpack!Header;
    
    if(header.magicNumber != "WAD3")
        throw new Exception("Invalid wad");
    
    DirectoryEntry[] files;
    
    files.reserve(header.fileCount);
    
    foreach(fileNum; 0 .. header.fileCount)
    {
        size_t index = header.fileOffset + fileNum * packedSize!DirectoryEntry;
        files ~= unpack!DirectoryEntry(data[index .. $]);
    }
    
    foreach(file; files)
        writeln(file.name.to!string.stripRight('\0'));
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
            mixin("result." ~ fieldName) = cast(ElementType[])data[index .. index + FieldType.length];
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
