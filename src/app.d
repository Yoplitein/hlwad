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
import std.file: mkdir, exists, readFile = read, writeFile = write;

import imageformats;

import wad;

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
        
        wad.add(texture, filename);
    }
    
    wad.write("test.wad");
}
