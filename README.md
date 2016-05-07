# hlwad
A tool for working with GoldSrc wad files.

## Usage
#### Listing files in a wad
`hlwad -l file.wad`

#### Extracting textures from a wad
`hlwad -x file.wad tex1 tex2`

#### Creating a wad
`hlwad -c out.wad tex1.png tex2.png other/`

## Caveats
* As the wad format uses palettes to store textures, input images must be quantized to <= 256 colors beforehand
* Transparent textures must be named with [a special prefix](http://twhl.info/tutorial.php?id=26), all transparent pixels in the input image must have color value `0, 0, 255, 0` (RGBA)
* Produced wads don't seem to work correctly with  [other wad tools](http://nemesis.thewavelength.net/index.php?p=45), but the engine can still load them just fine. ¯\\\_(ツ)\_/¯

## License
Available under the Boost license. See [LICENSE](LICENSE) for details.