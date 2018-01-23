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
        auto reg = data[1..$].map!(n => n.Extrapolate_Region(vertices.length))
                               .array;
        if ( reg.length == 4 ) { // build two faces from a quad
          faces ~= int3(reg[0].vertex, reg[1].vertex, reg[2].vertex);
          faces ~= int3(reg[0].vertex, reg[2].vertex, reg[3].vertex);
        } else {
          faces ~= int3(reg[0].vertex, reg[1].vertex, reg[2].vertex);
        }
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


private auto Extrapolate_Region ( string param, size_t vert_len ) {
  import stl;
  struct Region {
    int vertex;
    int uv = -1;
  }
  Region region;
  auto vars = param.split("/");
  region.vertex = vars[0].to!int;
  assert(region.vertex != 0, "Invalid face value of 0");
  if ( region.vertex < 0 )
    region.vertex = cast(int)(vert_len)+region.vertex;
  else
    region.vertex -= 1;
  return region;
}
