module rasterizer.pipeline;
        import std.stdio;

import vector;
import buffer : OutBuffer;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.datetime : Duration;
import brdf : Material;

Duration vertex_shader_time,
         fragment_shader_time;
int vertices_rendered;

// Input assember

enum VertexType {Model, UVCoordinates}
enum RenderType { Wireframe, Fragment, Depth };

immutable size_t VertexType_max = VertexType.max+1;

struct VertexBuffer {
  float3[] coordinates;
  int3[]   elements;
  auto RCoord ( int3 elem, size_t idx ) {
    return coordinates[elem[idx]];
  }
  auto RCoord ( size_t face, size_t idx ) {
    return coordinates[elements[face][idx]];
  }
}

struct VertexBufferObject {
  VertexBuffer[VertexType_max] buffers;
  size_t RLength ( ) {
    return buffers[0].elements.length;
  }
  auto RCoord ( VertexType type, int3[VertexType_max] elem, size_t idx ) {
    return buffers[type].RCoord(elem[type], idx);
  }
}

import imf = imageformats;
class DamnRasterizer {
  static Material _mat = {
    roughness:0.5f, metallic:0.5f, fresnel:0.5f, subsurface:0.5f,
    anisotropic:0.5f
  };
  static float3 Lo = float3(1.1f, -0.5f, 5.0f);
  Camera camera;
  imf.IFImage normal_map;
private:
  struct VaryingBuffer {
    float3[3] varying_tri;
    float3[3] varying_uv;
    BoundingBox bbox;
  }


  float3 Fragment_Shader ( inout ref VaryingBuffer vb, float3 eye, float3 bary){
    import stl : max, min;
    float2 uv = Matrix_Mul(vb.varying_uv, bary).xy;
    float3 ori = Matrix_Mul(vb.varying_tri, bary);
    float3 N = Load_PNG(normal_map, uv).xyz;
    float3 tlo = Lo;
    float3 wo = Normalize(tlo - ori),
           wi = Normalize(ori - eye);
    import brdf;
    // float3 col = BRDF_F ( wi, N, wo, _mat, float3(0.8f));
    return min(1.0f, max(0.0f, dot(wo, N)))*float3(0.68f, 0.57f, 0.689f);
  }

  VertexBufferObject vbo;
  VaryingBuffer[] vary_buf;
public:
  this ( Camera _camera ) {
    camera = _camera;
    normal_map = imf.read_image("african_normal.png");
  }
  void Push_Vertex_Buffer ( VertexType type, VertexBuffer _vbo ) {
    vbo.buffers[type] = _vbo;
  }

  void Render ( OutBuffer out_buff, RenderType type ) {
    vary_buf.length = vbo.RLength();
    Vertex_Shader();
    final switch ( type ) {
      case RenderType.Wireframe:
        Wireframe_Shader(out_buff);
      break;
      case RenderType.Fragment:
        Rasterize_Shader(out_buff);
      break;
      case RenderType.Depth    :
        Depth_Shader(out_buff);
      break;
    }
  }

  auto Vertex_Shader () {
    import std.parallelism;
    immutable VBO = cast(immutable)vbo;
    immutable Matrix = camera.viewport*camera.projection*camera.model;
    immutable Camera_bbox = cast(immutable)camera.bbox;

    auto sw = StopWatch(AutoStart.yes);

    foreach ( it, ref result; parallel(vary_buf) ) {
      int3 model_elem =  VBO.buffers[0].elements[it];
      foreach ( face; 0 .. 3 ) {
        float3 coord = VBO.buffers[0].coordinates[model_elem[face]];
        coord = (Matrix*float4(coord, 1.0f)).xyz;
        result.varying_tri[face] = coord;
      }
    }
    foreach ( it, ref result; parallel(vary_buf) ) {
      result.bbox = camera.bbox.Triangle(result.varying_tri);
    }

    import stl : filter, array;
    vary_buf = vary_buf.filter!(n =>
      n.bbox.bmin.x != camera.image_dim.x && n.bbox.bmax.x != 0 &&
      n.bbox.bmin.y != camera.image_dim.y && n.bbox.bmax.y != 0
    ).array();
    vertices_rendered = cast(int)vary_buf.length;
    sw.stop();
    vertex_shader_time = sw.peek();
  }

  void Rasterize_Shader(OutBuffer out_buf) {
    import std.parallelism, stl;
    auto sw = StopWatch(AutoStart.yes);
    immutable Matrix = camera.viewport*camera.projection*camera.model;

    immutable dim = camera.image_dim;
    immutable eye = (Matrix*float4(camera.eye, 0.0f)).xyz;
    float[] z_buf = Construct_Z_Buffer(camera.image_dim);

    foreach ( it, ref result; parallel(vary_buf) ) {
      immutable bbox = result.bbox;
      // if ( bbox.bmin.x < 0.0f  || bbox.bmin.y < 0.0f ||
      //      bbox.bmax.x > dim.x || bbox.bmax.y > dim.y ) goto NOLOOP;
      foreach ( p_x; iota(cast(int)bbox.bmin.x-1, cast(int)bbox.bmax.x+1))
      foreach ( p_y; iota(cast(int)bbox.bmin.y-1, cast(int)bbox.bmax.y+1)) {
        float2 pixel = float2(p_x, p_y);
        if ( camera.Valid_Pixel(pixel) ) {
          float3 bary = Barycentric(result.varying_tri, float3(pixel, 0.0f));
          if ( bary.x >= 0.0f && bary.y >= 0.0f && bary.z >= 0.0f ) {
            float z = iota(0, 3).map!(i => result.varying_tri[i].z*bary[i])
                                .reduce!((x, y) => x+y);
            size_t z_idx = RZ_Idx(pixel, out_buf.RWidth);
            if ( z_buf[z_idx] >= z ) continue;
            z_buf[z_idx] = z;
            float3 col = Fragment_Shader(result, eye, bary);
            out_buf.Apply(To_Int2(pixel.xy), float4(col, 1.0f));
          }
        }
      }
    }

    sw.stop();
    fragment_shader_time = sw.peek();
  }
  void Depth_Shader(OutBuffer out_buf) {
    import std.parallelism, stl;
    auto sw = StopWatch(AutoStart.yes);

    immutable dim = camera.image_dim;
    float[] z_buf = Construct_Z_Buffer(camera.image_dim);

    foreach ( it, ref result; parallel(vary_buf) ) {
      immutable bbox = result.bbox;
      foreach ( p_x; iota(cast(int)bbox.bmin.x-1, cast(int)bbox.bmax.x+1))
      foreach ( p_y; iota(cast(int)bbox.bmin.y-1, cast(int)bbox.bmax.y+1)) {
        float2 pixel = float2(p_x, p_y);
        if ( camera.Valid_Pixel(pixel) ) {
          float3 bary = Barycentric(result.varying_tri, float3(pixel, 0.0f));
          if ( bary.x >= 0.0f && bary.y >= 0.0f && bary.z >= 0.0f ) {
            float z = iota(0, 3).map!(i => result.varying_tri[i].z*bary[i])
                                .reduce!((x, y) => x+y);
            size_t z_idx = RZ_Idx(pixel, out_buf.RWidth);
            if ( z_buf[z_idx] >= z ) continue;
            z_buf[z_idx] = z;
            float3 col = float3(pixel.x/dim.x, 0.5f, pixel.y/dim.y);
            z = Clamp(z+1.0f, 0.0f, 2.0f)/2.0f;
            out_buf.Apply(To_Int2(pixel.xy), float4(col*z, 1.0f));
          }
        }
      }
    }

    sw.stop();
    fragment_shader_time = sw.peek();
  }
  void Wireframe_Shader(OutBuffer buf) {
    import std.parallelism;
    immutable dim = To_Int2(camera.image_dim.x, camera.image_dim.y);
    auto sw = StopWatch(AutoStart.yes);
    foreach ( it, ref result; parallel(vary_buf) ) {
      foreach ( v; 0 .. 3 ) {
        Render_Line(buf, dim, result.varying_tri[v].xy,
                              result.varying_tri[(v+1)%3].xy);
      }
    }
    sw.stop();
    fragment_shader_time = sw.peek();
  }
}


void Render_Line ( ref OutBuffer buf, int2 dim, float2 v0, float2 v1 ) {
  import stl : abs, swap;
  int2 i0 = (v0).To_Int2,
       i1 = (v1).To_Int2;
  bool steep = false;
  if ( abs(i0.x - i1.x) < abs(i0.y - i1.y) ) {
    swap(i0.x, i0.y);
    swap(i1.x, i1.y);
    steep = true;
  }
  if ( i0.x > i1.x ) {
    swap(i0.x, i1.x);
    swap(i0.y, i1.y);
  }
  int dx = i1.x - i0.x,
      dy = i1.y - i0.y;
  int derror2 = abs(dy)*2,
      error2 = 0;
  int y = i0.y;

  foreach ( x; i0.x .. i1.x ) {
    if ( steep ) buf.Apply(int2(y, x), float4(0.0f, 1.0f, 1.0f, 1.0f));
    else         buf.Apply(int2(x, y), float4(1.0f, 0.0f, 1.0f, 1.0f));
    error2 += derror2;
    if ( error2 > dx ) {
      y += (i1.y > i0.y?1:-1);
      error2 -= dx*2;
    }
  }
}


size_t RZ_Idx(T, U)(T pixel, U width)
            if ( is(T == int2) || is(T == float2) ) {
  return cast(size_t)(pixel.x) + cast(size_t)(pixel.y)*cast(size_t)(width);
}

float[] Construct_Z_Buffer ( float2 img_dim ) {
  float[] z_buffer;
  z_buffer.length = cast(int)(img_dim.x*img_dim.y);
  foreach ( ref z; z_buffer ) z = -1000.0f;
  return z_buffer;
}

float3 Barycentric ( float3[] pts, float3 pt ) {
  float3 v0 = pts[1] - pts[0],
         v1 = pts[2] - pts[0],
         v2 = pt     - pts[0];
  float d00 = dot(v0, v0), d01 = dot(v0, v1),
        d11 = dot(v1, v1), d20 = dot(v2, v0),
        d21 = dot(v2, v1);
  float denom = d00 * d11 - d01 * d01;
  float v = (d11 * d20 - d01 * d21)/denom;
  float w = (d00 * d21 - d01 * d20)/denom;
  return float3(1.0f-v-w, v, w);
}

float3 Matrix_Mul (T) ( T[3] a, float3 b ) {
  return a[0]*b.x + a[1]*b.y + a[2]*b.z;
}
