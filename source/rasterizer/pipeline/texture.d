module rasterizer.pipeline.texture;
import imf = imageformats;
import vector;
import std.stdio : writeln;

class Texture {
  imf.IFImage image;
  this ( string filename ) {
    image = imf.read_image(filename);
  }

  float2 RDim ( ) { return float2(image.w, image.h); }

  float4 Read ( float2 uv ) {
    import stl : map, array;
    // uv.y = 1.0f - uv.y;
    float2 uv_c = uv*RDim;
    size_t idx = image.w*cast(size_t)(uv_c.y)*4 + cast(size_t)(uv_c.x)*4;
    ubyte[] col = image.pixels[idx .. idx+4];
    return float4(col.map!(n => n/255.0f).array);
  }
}
