module rasterizer.pipeline;
        import std.stdio;

import vector;
import buffer : OutBuffer;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.datetime : Duration;
import brdf : BRDF_F, Material;
import rasterizer.pipeline.texture;
import settings;

Duration vertex_shader_time,
         fragment_shader_time;
int vertices_rendered;

// Input assember

enum VertexType {Model, UVCoordinates};
enum RenderType { Wireframe, Fragment, Depth };
enum TextureType { Diffuse, Normal };

immutable size_t VertexType_max = VertexType.max+1;
immutable size_t TextureType_max = VertexType.max+1;

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
  static float3 Lo = float3(-0.27f, -0.43f, -0.19f),
                Lemit = float3(1.0f);
  Camera camera;
  Texture[TextureType_max] textures;
  bool has_uv;
private:

  struct UniformBuffer {
    immutable float4x4 Matrix, MatrixInverse;
    immutable Texture[TextureType_max] textures;
    immutable Settings settings;
    immutable float3 Lo, Lemit;
    immutable Material mat;
  }

  struct VaryingBuffer {
    float3[3] world_tri;
    float3[3] varying_tri;
    float3[3] varying_uv;
    BoundingBox bbox;
  }


  float3 Fragment_Shader ( immutable ref UniformBuffer ub,
                           inout ref VaryingBuffer vb, float3 eye, float3 bary){
    import stl : max, min, fabs;
    float2 uv = Matrix_Mul(vb.varying_uv, bary).xy;
    float3 ori = Matrix_Mul(vb.world_tri, bary);
    float3 N;
    if ( ub.settings.render_textures[TextureType.Normal] &&
         ub.textures[TextureType.Normal] !is null ) {
      N = ub.textures[TextureType.Normal].Read(uv).xyz.Normalize;
      // N = (ub.MatrixInverse*float4(N, 0.0f)).xyz.Normalize;
    } else
      N = cross(vb.world_tri[2] - vb.world_tri[0],
                vb.world_tri[1] - vb.world_tri[0]).Normalize;
    float3 diff = float3(0.5f);
    if ( ub.settings.render_textures[TextureType.Diffuse] &&
         ub.textures[TextureType.Diffuse] !is null ) {
      diff = ub.textures[TextureType.Diffuse].Read(uv).xyz;
    }
    float3 wo = Normalize(ub.Lo - ori),
           wi = Normalize(ori - eye);
    float3 col = BRDF_F ( wi, N, wo, ub.mat, diff);
    return col*ub.Lemit;//diff*max(0.0f, dot(wi, N));
  }

  VertexBufferObject vbo;
  VaryingBuffer[] vary_buf;
public:
  this ( Camera _camera ) {
    camera = _camera;
  }
  void Push_Vertex_Buffer ( VertexType type, VertexBuffer _vbo ) {
    writeln("Pushing vertex buffer of type ", type);
    vbo.buffers[type] = _vbo;
  }

  void Set_Texture ( TextureType type, string filename ) {
    writeln("Pushing texture buffer of type ", type);
    has_uv = true;
    textures[type] = new Texture(filename);
  }

  void Render ( OutBuffer out_buff, RenderType type ) {
    vary_buf.length = vbo.RLength();
    Vertex_Shader();
    final switch ( type ) {
      case RenderType.Wireframe:
        Wireframe_Shader(out_buff);
      break;
      case RenderType.Fragment:
        Rasterize_Shader!(RenderType.Fragment)(out_buff);
      break;
      case RenderType.Depth    :
        Rasterize_Shader!(RenderType.Depth)(out_buff);
      break;
    }
  }

  auto Vertex_Shader () {
    import std.parallelism;
    immutable VBO = cast(immutable)vbo;
    immutable Matrix = camera.viewport*camera.projection*camera.model;
    immutable Camera_bbox = cast(immutable)camera.bbox;

    auto sw = StopWatch(AutoStart.yes);
    // TODO break these into multiple functions with stopwatch

    // -- Model Geometry --
    foreach ( it, ref result; parallel(vary_buf) ) {
      int3 model_elem =  VBO.buffers[0].elements[it];
      foreach ( face; 0 .. 3 ) {
        auto element = model_elem[face];
        float3 coord = VBO.buffers[0].coordinates[model_elem[face]];
        result.world_tri   [face] = coord;
        result.varying_tri [face] = (Matrix*float4(coord, 1.0f)).xyz;
      }
    }
    // -- Model UV/Texture --
    if ( has_uv ) { // TODO better if check
      foreach ( it, ref result; parallel(vary_buf) ) {
        int3 uv_elem = VBO.buffers[1].elements[it];
        foreach ( face; 0 .. 3 ) {
          float3 coord = VBO.buffers[1].coordinates[uv_elem[face]];
          result.varying_uv[face] = coord;
        }
      }
    }
    // -- bounding box --
    foreach ( it, ref result; parallel(vary_buf) ) {
      result.bbox = camera.bbox.Triangle(result.varying_tri);
    }
    // -- camera clipping -- TODO parallelize (?)
    import stl : filter, array;
    vary_buf = vary_buf.filter!(n =>
      n.bbox.bmin.x != camera.image_dim.x && n.bbox.bmax.x != 0 &&
      n.bbox.bmin.y != camera.image_dim.y && n.bbox.bmax.y != 0
    ).array();
    vertices_rendered = cast(int)vary_buf.length;
    sw.stop();
    vertex_shader_time = sw.peek();
  }

  void Rasterize_Shader(RenderType CRType)(OutBuffer out_buf) {
    import std.parallelism, stl;
    auto sw = StopWatch(AutoStart.yes);
    immutable Matrix = camera.viewport*camera.projection*camera.model;
    immutable ModelMatrix = camera.projection*camera.model;
    // TODO: move all this stuff up the pipeline, throw out Lo and _mat
    //           to settings. Better yet, seperate the pipeline from
    //           DamnRasterizer class
    immutable ubuffer = cast(immutable)UniformBuffer(
              cast(immutable)ModelMatrix,
              cast(immutable)ModelMatrix.inverse.transposed,
              cast(immutable)textures,
              cast(immutable)global_settings,
              cast(immutable)Lo,
              cast(immutable)Lemit,
              cast(immutable)_mat);

    immutable dim = camera.image_dim;
    immutable eye = (Matrix*float4(camera.eye, 0.0f)).xyz;
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
            float3 col;
            static if ( CRType == RenderType.Depth ) {
              col = float3(pixel.x/dim.x, 0.5f, pixel.y/dim.y)*
                    Clamp(z+1.0f, 0.0f, 2.0f)/2.0f;
            } else static if ( CRType == RenderType.Fragment ) {
              col = Fragment_Shader(ubuffer, result, eye, bary);
            }
            out_buf.Apply(To_Int2(pixel.xy), float4(col, 1.0f));
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
    foreach ( it, ref result; parallel(vary_buf) )   {
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
