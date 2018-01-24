module settings;
import rasterizer.pipeline : TextureType, TextureType_max;

struct Settings {
  bool[TextureType_max] render_textures = [true, false];
}

Settings global_settings;
