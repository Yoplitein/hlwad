import std.algorithm;
import std.array;
import std.file: mkdir, exists;
import std.getopt;
import std.path;
import std.range;
import std.stdio;
import std.string;

import imageformats;

import wad;

int main(string[] args)
{
    bool doList;
    bool doExtract;
    bool doCreate;
    
    auto parsed = args.getopt(
        config.bundling,
        config.passThrough,
        "l|list", "List textures in a wad file.", &doList,
        "x|extract", "Extract textures from a wad file.", &doExtract,
        "c|create", "Create a wad file.", &doCreate,
    );
    
    args = args[1 .. $];
    
    try
    {
        if(doList)
        {
            list(args);
            
            return 0;
        }
        
        if(doExtract)
        {
            extract(args);
            
            return 0;
        }
        
        if(doCreate)
        {
            create(args);
            
            return 0;
        }
    }
    catch(Exception err)
    {
        writeln(err.msg);
        
        return 1;
    }
    
    defaultGetoptPrinter(
        "hlwad <--list <wad>|--extract <wad> [files]|--create <wad> <files/folders>>",
        parsed.options,
    );
    
    return 0;
}

void list(string[] args)
{
    if(args.length == 0)
        throw new Exception("Usage: hlwad --list <wad>");
    
    string filename = args[0];
    auto wad = WadFile(filename);
    
    foreach(file; wad.files)
        writeln(file.name.ptr.fromStringz);
}

void extract(string[] args)
{
    if(args.length == 0)
        throw new Exception("Usage: hlwad --extract <wad> [files]");
    
    string filename = args[0];
    auto wad = WadFile(filename);
    string[] fileWhitelist;
    
    if(args.length > 1)
        fileWhitelist = args
            .drop(1)
            .map!(x => x.toLower)
            .array
        ;
    
    bool useWhitelist = !fileWhitelist.empty;
    string foldername = filename
        .baseName
        .stripExtension
    ;
    
    if(!foldername.exists)
        mkdir(foldername);
    
    foreach(file; wad.files)
    {
        string name = file
            .name
            .ptr
            .fromStringz
            .toLower
            .idup
        ;
        
        if(useWhitelist && !fileWhitelist.canFind(name))
            continue;
        
        Texture texture = wad.readTexture(file);
        string outputFilename = foldername
            .buildPath(name)
            .setExtension(".png")
        ;
        
        writeImage(outputFilename, texture);
    }
}

void create(string[] args)
{
    //TODO
}

void writeImage(string filename, Texture texture)
{
    write_image(filename, texture.width, texture.height, texture.pixels, ColFmt.RGBA);
}

Texture readImage(string filename)
{
    IFImage img;
    
    try
        img = read_image(filename, ColFmt.RGBA);
    catch(ImageIOException err)
    {
        throw new Exception("Failed to read image `%s`: %s".format(filename, err.msg));
    }
    
    return Texture(img.w, img.h, img.pixels);
}
