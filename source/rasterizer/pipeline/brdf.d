module brdf;
import stl;
import vector;

immutable float PI   = 3.141592653589793f;
immutable float IPI  = 0.318309886183791f;
immutable float IPI2 = 0.159154943091895f;
immutable float TAU  = 6.283185307179586f;
immutable float ITAU = 0.159154943091895f;

T sqr(T)(T x){ return x*x; }

float Schlick_Fresnel ( float u ) {
  float f = Clamp(1.0f - u);
  float f2 = f*f;
  return f2*f2*f; // f^5
}

float3 Binormal ( float3 N ) {
  float3 axis = (abs(N.x) < 1.0f ? float3(1.0f, 0.0f, 0.0f) :
                                   float3(0.0f, 1.0f, 0.0f));
  return Normalize(cross(N, axis));
}

float Smith_G_GGX_Correlated ( float L, float R, float a ) {
  return L * sqrt(R - a*sqr(R) + a);
}

struct Material {
  float roughness, metallic, fresnel, subsurface, anisotropic;
}

// Actual BRDF function that returns the albedo of the surface
float3 BRDF_F ( float3 wi, float3 N, float3 wo, Material m, float3 col ) {
  // get binormal, bitangent, half vec etc
  const float3 binormal  = Binormal(N),
               bitangent = cross(binormal, N),
               L         =  wo, V = -wi,
               H         = Normalize(L+V);
  const float  cos_NV    = dot(N, V), cos_NL     = dot(N, L),
               cos_HV    = Clamp(dot(H, V)),
               cos_HL    = Clamp(dot(H, L)),
               Fresnel_L = Schlick_Fresnel(cos_NL),
               Fresnel_V = Schlick_Fresnel(cos_NV);
  // Diffusive component
  float3 diffusive_albedo = col*IPI;

  float3 microfacet = float3(1.0f);


  // probably transmittive
  if ( cos_NL <= 0.0f || cos_NV <= 0.0f ) {
    return float3(0.0f);
  }

  { // ------- Fresnel
    // modified diffusive fresnel from disney, modified to use albedo & F0
    const float F0 = m.fresnel * m.metallic,
                Fresnel_diffuse_90 = F0 * sqr(cos_HL);
    float3 F = (1.0f - F0) * diffusive_albedo +
            Mix(1.0f, Fresnel_diffuse_90, Fresnel_L) *
            Mix(1.0f, Fresnel_diffuse_90, Fresnel_V);
    microfacet *= Clamp(F);
  }

  { // ------- Geometric
    // Heits 2014, SmithGGXCorrelated with half vec combined with anisotropic
    // term using GTR2_aniso model
    const float Param  = 0.5f + m.roughness,
                Aspect = sqrt(1.0f - m.anisotropic*0.9f),
                Ax     = Param/Aspect, Ay = Param*Aspect,
                GGX_NV = Smith_G_GGX_Correlated(cos_HL, cos_NV, Ax),
                GGX_HL = Smith_G_GGX_Correlated(cos_NV, cos_HL, Ay);
    float G = 0.5f / (GGX_NV*Ax + GGX_HL*Ay);
    microfacet *= Clamp(G);
  }
  { // ------- Distribution
    // Hyper-Cauchy Distribution using roughness and metallic
    const float Param = 1.2f + m.anisotropic,
                Shape = (1.1f - m.roughness*0.55f),
                tan_HL = (cross(H, L)).magnitude/cos_HL;
    const float Upper  = (Param - 1.0f)*pow(sqrt(2.0f), (2.0f*Param - 2.0f)),
                LowerL = (PI*sqr(Shape) * pow(cos_HL, 4.0f)),
                LowerR = pow(2.0f + sqr(tan_HL)/sqr(Shape), Param);
    float D = (Upper/(LowerL*LowerR));
    microfacet *= Clamp(D);
  }

  // Since microfacet is described using half vec, the following energy
  // conservation model may be used [Edwards et al. 2006]
  microfacet /= 4.00f * cos_HV * fmax(cos_NL, cos_NV);

  { // --------- Subsurface
    // based off the Henyey-Greenstein equation
    const float R = 0.7f*(1.0 - m.roughness),
                M = 0.2f + m.subsurface;
    const float Rr_term = M * (1.0f - sqr(R))*(4.0f*IPI) *
                          (1.0f/(pow(1.0f + sqr(R) - 2.0f*R*cos_HL, 3.0f/2.0f)));
    const float3 Retro_reflection = diffusive_albedo * Rr_term *
                      (Fresnel_L + Fresnel_V + (Fresnel_L*Fresnel_V*(Rr_term)));
    diffusive_albedo = Mix(diffusive_albedo, Pow(Retro_reflection, float3(0.5f)),
                           m.subsurface*0.5f);
  }

  float3 result = Clamp((diffusive_albedo + microfacet));
  return result;
}
