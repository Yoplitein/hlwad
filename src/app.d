import std.file: mkdir, exists;
import std.getopt;
import std.path;
import std.stdio;
import std.string;

import imageformats;

import wad;

void main()
{
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
