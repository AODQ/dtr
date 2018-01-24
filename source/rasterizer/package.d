module rasterizer;

static import stl;
import buffer;
import vector;
import wavefront;
import stl : max, writeln;
import rasterizer.pipeline;

private GLBuffer gl_buffer;
private DamnRasterizer drast;
private Camera camera;

float3 model_dimensions;
float model_diameter;
float zoom    = 1.0f;
bool animate  = true;
float3 pan_eye = float3(0.0f);
float3 rotational_eye = float3(0.0f);
RenderType render_type = RenderType.Depth;

void Initialize ( string[] args = [] ) {
  writeln("Initializing");
  int2 dim = int2(640, 480);
  gl_buffer = new GLBuffer(dim.x, dim.y);
  auto wavefront_obj = new WavefrontObj(args[0]);

  writeln("Creating camera");
  camera = new Camera(float2(dim));
  camera.eye    = float3(0.0f,  2.0f, 3.0f);
  camera.center = float3(0.0f,  0.0f, 0.0f);
  camera.up     = float3(0.0f,  1.0f, 0.0f);
  camera.viewport   = camera.Viewport(0, 0, dim.x, dim.y);
  camera.model      = camera.Lookat();

  writeln("Creating rasterization pipeline");
  drast = new DamnRasterizer(camera);
  drast.Push_Vertex_Buffer(VertexType.Model,
                  VertexBuffer(wavefront_obj.vertices,
                               wavefront_obj.faces));
  if ( wavefront_obj.has_uv ) {
    drast.Push_Vertex_Buffer(VertexType.UVCoordinates,
                  VertexBuffer(wavefront_obj.uv_coords,
                               wavefront_obj.uv_faces));
  }
  foreach ( it, text_name; wavefront_obj.textures ) {
    if ( text_name != "" ) drast.Set_Texture(cast(TextureType)it, text_name);
  }
  model_dimensions = wavefront_obj.bbox.bmax - wavefront_obj.bbox.bmin;
  model_diameter   = max(model_dimensions.x, max(model_dimensions.y,
                         model_dimensions.z));
  pan_eye.y = -0.5f;
  delete wavefront_obj;
  writeln("Rasterization pipeline complete");
}


float timer = 0.0f;
void Render ( ) {
  import stl : sin, cos, max;
  import derelict.glfw3 : glfwGetTime;
  timer = glfwGetTime();
  camera.eye.z = 2.0f*model_diameter;
  camera.model      = camera.Lookat();
  camera.viewport   = camera.Viewport(0, 0, 640, 480);
  camera.viewport.translate(pan_eye);
  camera.Set_Projection(float3(model_diameter)*(1.0f/zoom));
  camera.model = camera.model.rotateX(rotational_eye.x) *
                 camera.model.rotateY(rotational_eye.y) *
                 camera.model.rotateZ(rotational_eye.z);

  gl_buffer.Clear(float4(0.0f, 0.0f, 0.0f, 0.0f));
  drast.Render(gl_buffer, render_type);
  gl_buffer.Render();
}
