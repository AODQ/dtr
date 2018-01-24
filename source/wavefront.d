module wavefront;
import vector;
import std.stdio : writeln;
import std.exception : enforce;
import rasterizer.pipeline : TextureType, TextureType_max;

float3 To_Float3 ( string[] args ) {
  import std.conv : to;
  return float3(args[0].to!float, args[1].to!float, args[2].to!float);
}
float2 To_Float2 ( string[] args ) {
  import std.conv : to;
  return float2(args[0].to!float, args[1].to!float);
}

class WavefrontObj {
  float3[] vertices;
  float3[] uv_coords;
  int3[] faces;
  int3[] uv_faces;

  bool has_uv = false;
  string[TextureType_max] textures;
  BoundingBox bbox;

  void Check_Valid ( ) {
    bool Is_Clamped(int3 face, size_t len) {
      return (face.x >= 0 && face.x < len &&
              face.y >= 0 && face.y < len &&
              face.z >= 0 && face.z < len );
    }
    void Clamp_Check ( ref int3[] arr, string label ) {
      import std.string : format;
      foreach ( f; arr )
        enforce(Is_Clamped(f, arr.length),
            "Face %s out of range of %s length %s"
            .format(f, label, arr.length));
    }
    Clamp_Check(faces, "geometry vertex");
    Clamp_Check(uv_faces, "UV vertex");
  }

  private void Apply_Line ( string line ) {
    import stl;
    auto data = line.split(" ");
    data = data.filter!(n => n != "").array;
    if ( data.length == 0 || data[0][0] == '#' ) return;
    switch ( data[0] ) {
      default: break;
      case "dtr_diffuse":
        has_uv = true;
        textures[TextureType.Diffuse] = data[1];
      break;
      case "dtr_normal":
        has_uv = true;
        textures[TextureType.Normal] = data[1];
      break;
      case "v":
        auto vert = data[1..4].To_Float3;
        bbox.Apply(vert);
        vertices ~= vert;
      break;
      case "vt":
        auto coords = data[1..$];
        if ( coords.length == 2 )
          uv_coords ~= float3(coords.To_Float2, 0.0f);
        else {
          assert(coords.length == 3, "Incorrect vt length");
          uv_coords ~= coords.To_Float3;
        }
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
        uv_faces ~= int3(reg[0].uv, reg[1].uv, reg[2].uv);
      break;
    }
  }

  this ( string fname ) {
    import stl;
    bbox.bmin = float3( 1000.0f);
    bbox.bmax = float3(-1000.0f);
    writeln("Constructing wavefront object ", fname);
    File(fname).byLine.each!(n => Apply_Line(n.to!string));
    writeln("Checking validity of model");
    Check_Valid();
    writeln("Successfully loaded ", fname);
  }
}


private auto Extrapolate_Region ( string param, size_t vert_len ) {
  import stl;
  struct Region {
    int vertex;
    int uv = -1;
  }
  Region region;
  auto vars = param.split("/").filter!(n => n!="").array;
  region.vertex = vars[0].to!int.RObj_Face_Index(vert_len);
  if ( vars.length > 1 )
    region.uv = vars[1].to!int.RObj_Face_Index(vert_len);
  return region;
}

private auto RObj_Face_Index ( int t, size_t len ) {
  assert(t > 0, "Invalid face value of 0");
  return t < 0 ? cast(int)(len) + t : t-1;
}
