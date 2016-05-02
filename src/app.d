import std.file: mkdir, exists;
import std.getopt;
import std.path;
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
        "hlwad <--list <wad> [search]|--extract <wad> [files]|--create <wad> <files/folders>>",
        parsed.options,
    );
    
    return 0;
}

void list(string[] args)
{
    //TODO
}

void extract(string[] args)
{
    //TODO
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
