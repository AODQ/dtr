module vector;
public import gfm.math;

import stl;

alias float2 = vec2f;
alias float3 = vec3f;
alias float4 = vec4f;
alias float4x4 = mat4f;
alias int2 = vec2i;
alias int3 = vec3i;
alias int4 = vec4i;
alias ubyte4 = vec4ub;

int2 To_Int2 ( float x, float y ) { return int2(cast(int )x, cast(int )y ); }
int2 To_Int2 ( float2 p         ) { return To_Int2(p.x, p.y); }

T Normalize(T) ( T vec ) {
  vec.normalize;
  return vec;
}

float Clamp(float t, float u = 0.0f, float v = 1.0f) {
  if ( u > t ) return u;
  if ( t > v ) return v;
  return t;
}
float3 Clamp(float3 t, float3 u = float3(0.0f), float3 v = float3(1.0f) ) {
  return float3(Clamp(t.x, u.x, v.x),
                Clamp(t.y, u.y, v.y),
                Clamp(t.z, u.z, v.z));
}
float3 Clamp(float3 t, float u, float v) {
  return Clamp(t, float3(u), float3(v));
}

float3 Pow ( float3 a, float3 b ) {
  return float3(pow(a.x, b.x), pow(a.y, b.y), pow(a.z, b.z));
}

U Mix(U, V)(U x, U y, V a) {
  return x*(1.0f-a) + y*a;
}


struct BoundingBox {
  float3 bmin;
  float3 bmax;
  void Apply ( float3 pt ) {
    iota(0, 3).each!((it) {
      bmin[it] = min(bmin[it], pt[it]);
      bmax[it] = max(bmax[it], pt[it]);
    });
  }

  float3 Mix ( float3 pt ) {
    return (pt - bmin)/(bmax-bmin);
  }
  float2 Mix ( float2 pt ) {
    return Mix(float3(pt, 1.0f)).xy;
  }

  /// Returns if 'degenerate'
  void Clamp ( ref BoundingBox bbox, int params = 3) {
    iota(0, params).each!((it) {
      bmin[it] = max(bmin[it], bbox.bmin[it]);
      bmax[it] = min(bmax[it], bbox.bmax[it]);
    });
  }

  auto Triangle ( float3[] tris ) {
    BoundingBox rbox = BoundingBox(bmax, bmin);
    tris.each!(t => rbox.Apply(t));
    return rbox;
  }

  float2 Iterate ( float2 coord ) {
    coord.x += 1.0f;
    if ( coord.x >= bmax.x ) {
      coord.x = bmin.x;
      coord.y += 1.0f;
    }
    return coord;
  }

  BoundingBox opBinary(string op)(BoundingBox rhs) if ( op == "*" ) {
    return BoundingBox(bmin*rhs.bmin, bmax*rhs.bmax);
  }
  BoundingBox opBinary(string op)(float3 rhs) if ( op == "*" ) {
    return BoundingBox(bmin*rhs, bmax*rhs);
  }
}

class Camera {
  BoundingBox bbox;
  float2 image_dim;
  float4x4 model, projection, viewport;
  float3 eye, center, up;

  float3 Transform ( float3 vertex ) {
    return (vertex - bbox.bmin)/(bbox.bmax - bbox.bmin);
  }

  BoundingBox Transform ( BoundingBox bbox ) {
    return BoundingBox(Transform(bbox.bmin), Transform(bbox.bmax));
  }

  this ( float2 img_dim ) {
    bbox = BoundingBox(float3(0.0f), float3(img_dim.xy, 1.0f));
    image_dim.xy = img_dim.xy;
  }

  bool Valid_Pixel ( float2 pixel ) {
    return pixel.x >= bbox.bmin.x && pixel.y >= bbox.bmin.y &&
           pixel.x <  bbox.bmax.x && pixel.y <  bbox.bmax.y;
  }

  float4x4 Lookat () {
    return float4x4.lookAt(eye, center, up);
  }

  float4x4 Viewport ( int x, int y, int w, int h ) {
    float4x4 m = float4x4.identity();
    m.c[0][3] = x+w*0.5f;
    m.c[1][3] = y+w*0.5f;
    m.c[2][3] = 0.5f;

    m.c[0][0] = w*0.5f;
    m.c[1][1] = w*0.5f;
    m.c[2][2] = 0.5f;
    return m;
  }

  void Set_Projection (float3 dim) {
    projection = float4x4.orthographic(-dim.x, dim.x, -dim.y, dim.y,
                                       0.0f, 0.0f + dim.z);
  }
}

import imf = imageformats;
float4 Load_PNG ( ref imf.IFImage img, float2 uv ) {
  uv.y = 1.0f - uv.y;
  float2 uv_c = uv * float2(img.w, img.h);
  size_t idx = img.w*cast(size_t)(uv_c.y)*4 + cast(size_t)(uv_c.x)*4;
  ubyte[] col = img.pixels[idx .. idx+4];
  return float4(col.map!(n => n/255.0f).array);
}
