module glfw.gui;
import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;

import derelict.opengl;
import derelict.glfw3.glfw3;

import imgui;
import glfw;
import glfw.input : mouse;

auto Bool_Enable ( bool t ) {
  return t ? Enabled.yes : Enabled.no;
}

struct GUI {
    this(int nothing) {
        int width;
        int height;
        glfwGetWindowSize(window, &width, &height);

        // trigger initial viewport transform.
        On_Window_Resize(window, width, height);
        glfwSetWindowSizeCallback(window, &On_Window_Resize);
    }

    void render() {
        // Mouse states
        ubyte mousebutton = 0;
        double mouseX;
        double mouseY;
        glfwGetCursorPos(window, &mouseX, &mouseY);

        const scrollAreaWidth = (window_width / 4) - 10;  // -10 to allow room for the scrollbar
        const scrollAreaHeight = window_height - 20;

        int mousex = cast(int)mouseX;
        int mousey = cast(int)mouseY;

        mousey = window_height - mousey;
        int leftButton   = glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_LEFT);
        int rightButton  = glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_RIGHT);
        int middleButton = glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_MIDDLE);

        if (leftButton == GLFW_PRESS)
            mousebutton |= MouseButton.left;

        imguiBeginFrame(mousex, mousey, mousebutton, mouseScroll);

        static float prev_mouse_x = 0.0f, prev_mouse_y = 0.0f;
        static bool prev_mouse_left, prev_mouse_middle, prev_mouse_right;

        mouse.x = mouseX;
        mouse.y = mouseY;
        mouse.z = mouseScroll;
        mouse.motion_x = mouseX - prev_mouse_x;
        mouse.motion_y = mouseY - prev_mouse_y;
        mouse.left   = cast(bool)leftButton;
        mouse.middle = cast(bool)middleButton;
        mouse.right  = cast(bool)rightButton;
        mouse.on_left = mouse.left && !prev_mouse_left;
        mouse.on_right = mouse.right && !prev_mouse_right;
        mouse.on_middle = mouse.middle && !prev_mouse_middle;
        prev_mouse_left = mouse.left;
        prev_mouse_right = mouse.right;
        prev_mouse_middle = mouse.middle;

        prev_mouse_x = mouseX;
        prev_mouse_y = mouseY;

        if (mouseScroll != 0)
            mouseScroll = 0;

        static bool gui_active = false;
        if ( mouse.on_left || mouse.on_middle || mouse.on_right ) {
          if ( mouse.x < scrollAreaWidth ) {
            gui_active = true;
          }
        }

        if ( gui_active && !mouse.left ) gui_active = false;

        if ( gui_active ) {
          mouse.on_left = mouse.on_middle = mouse.on_right = false;
          mouse.motion_x = mouse.motion_y = 0.0f;
          writeln("activated");
        }
        displayArea1(scrollAreaWidth, scrollAreaHeight);

        imguiEndFrame();

        imguiRender(window_width, window_height);
}

    float prev_time = 0.0f, curr_time = 0.0f;
    int frame_count = 0;
    string fps_str = "";
    void displayArea1(int scrollAreaWidth, int scrollAreaHeight) {
      import stl : to, format;
      imguiBeginScrollArea("Settings", 10, 10, scrollAreaWidth, scrollAreaHeight, &scrollArea1);

      imguiSeparatorLine();
      imguiSeparator();

      curr_time = glfwGetTime();
      ++frame_count;
      if ( curr_time - prev_time >= 1.0f ) {
        fps_str = frame_count.to!string;
        prev_time = curr_time;
        frame_count = 0;
      }
      import rasterizer.pipeline : vertex_shader_time, fragment_shader_time,
                                   DamnRasterizer;
      imguiLabel("Framerate: " ~ fps_str.to!string);
      imguiLabel("Vertex Shader: %s".format(vertex_shader_time));
      imguiLabel("Fragment Shader: %s".format(fragment_shader_time));
      imguiLabel("Total: %s".format(vertex_shader_time+fragment_shader_time));

      import rasterizer : zoom, pan_eye, rotational_eye, animate,
                          model_dimensions;
      static bool animatal = true;
      if ( imguiCheck("animatal", &animatal) ) {
        rotational_eye.z = 0.0f;
      }

      if ( animatal ) {
        rotational_eye.y = curr_time;
      }

      import std.math : PI;
      static float delta = float.epsilon;
      imguiSlider("Rotation.x", &rotational_eye.x, -PI*0.5f, PI*0.5f, delta);
      { // handle possible animatal rotation y
        float* rot_ptr;
        static float dummy_rotate = float.nan; // To remove number on animate
        rot_ptr = animatal ? &dummy_rotate : &rotational_eye.y;
        imguiSlider("Rotation.y", rot_ptr, -PI, PI, delta,
                                            (!animatal).Bool_Enable);
      }
      imguiSlider("Rotation.z", &rotational_eye.z, -PI*0.5f, PI*0.5f, delta);
      imguiSlider("Pan.x", &pan_eye.x, -10.0, 10.0, delta);
      imguiSlider("Pan.y", &pan_eye.y, -10.0, 10.0, delta);
      imguiSlider("Zoom", &zoom, 0.1f, 10.0f, delta);

      // handle mouse
      if ( !animatal ) {
        if ( mouse.right ) {
          rotational_eye.y += mouse.motion_x*0.1f*(1.0f/zoom);
          rotational_eye.x += mouse.motion_y*0.1f*(1.0f/zoom);
        }
        if ( mouse.left ) {
          float aspect_ratio = cast(float)(window_width)/window_height;
          aspect_ratio.writeln;
          pan_eye.x += mouse.motion_x* 0.005f*aspect_ratio;
          pan_eye.y += mouse.motion_y*-0.005f;
        }
        if ( mouse.middle ) {
          import std.math : fmax;
          zoom += mouse.motion_x*0.01f;
          zoom = fmax(0.001f, zoom);
        }
      }
       imguiSlider("Lo.x", &DamnRasterizer.Lo.x, -500.0f, 500.0f, 0.001f);
       imguiSlider("Lo.y", &DamnRasterizer.Lo.y, -500.0f, 500.0f, 0.001f);
       imguiSlider("Lo.z", &DamnRasterizer.Lo.z, -10.0f, 10.0f, 0.01f);

      imguiSeparatorLine();
      imguiSeparator();

      float rough=0.0f;
      imguiSlider("roughness",   &DamnRasterizer._mat.roughness,   0.0f, 1.0f, 0.001f);
      imguiSlider("metallic",    &DamnRasterizer._mat.metallic,    0.0f, 1.0f, 0.001f);
      imguiSlider("fresnel",     &DamnRasterizer._mat.fresnel,     0.0f, 1.0f, 0.001f);
      imguiSlider("subsurface",  &DamnRasterizer._mat.subsurface,  0.0f, 1.0f, 0.001f);
      imguiSlider("anisotropic", &DamnRasterizer._mat.anisotropic, 0.0f, 1.0f, 0.001f);

      imguiEndScrollArea();
    }

    void onScroll(double hOffset, double vOffset) {
        mouseScroll = -cast(int)vOffset;
    }

private:
    int scrollArea1 = 0;
    int scrollArea2 = 0;
    int scrollArea3 = 0;
    int scrollArea4 = 0;
    int mouseScroll = 0;
}
