module wavefront;
import vector;

float3 To_Float3 ( string[] args ) {
  import std.conv : to;
  return float3(args[0].to!float, args[1].to!float, args[2].to!float);
}

class WavefrontObj {
  float3[] vertices;
  float3[] uv_coords;
  int3[] faces;
  int3[] uv_faces;
  BoundingBox bbox;

  private void Apply_Line ( string line ) {
    import stl;
    auto data = line.split(" ");
    data = data.filter!(n => n != "").array;
    if ( data.length == 0 || data[0][0] == '#' ) return;
    switch ( data[0] ) {
      default: break;
      case "v":
        auto vert = data[1..4].To_Float3;
        bbox.Apply(vert);
        vertices ~= vert;
      break;
      case "vt":
        // uv_coords ~= data[1..4].To_Float3;
      break;
      case "f":
        faces    ~= int3(data[1..4].map!(t => t.split("/")[0].to!int-1).array);
        // uv_faces ~= int3(data[1..4].map!(t => t.split("/")[1].to!int-1).array);
      break;
    }
  }

  this ( string fname ) {
    import stl;
    bbox.bmin = float3( 1000.0f);
    bbox.bmax = float3(-1000.0f);
    File(fname).byLine.each!(n => Apply_Line(n.to!string));
  }
}
