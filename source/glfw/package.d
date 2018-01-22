module glfw;

import std.algorithm : min;
import std.exception : enforce;
import std.functional : toDelegate;
import std.stdio : stderr;
import std.string : format;

import derelict.glfw3.glfw3, derelict.opengl;
import glfw.gui;
import imgui;

GUI gui;
GLFWwindow* window;
int window_width, window_height;
void Initialize ( int width, int height, string font ) {
  window_width = width;
  window_height = height;
  DerelictGL3.load();
  DerelictGLFW3.load();
  if (!glfwInit()) {
    assert(false, "glfwinit failed");
  }

  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE );
  glfwWindowHint(GLFW_RESIZABLE,      GL_FALSE                 );
  glfwWindowHint(GLFW_FLOATING,       GL_TRUE                  );
  glfwWindowHint( GLFW_REFRESH_RATE,  0                        );
  glfwSwapInterval(0);
  glfwInit();

  window = glfwCreateWindow(width, height, "DTR live render", null, null);

  glfwMakeContextCurrent(window);
  DerelictGL3.reload();
  glClampColor(GL_CLAMP_READ_COLOR, GL_FALSE);

  glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB);

  // import liverender.input;
  // glfwSetCursorPosCallback   (window, &Cursor_Position_Callback );
  // glfwSetMouseButtonCallback (window, &Cursor_Button_Callback   );
  // glfwSetKeyCallback         (window, &Key_Input_Callback       );

  gui = GUI(0);
  enforce(imguiInit(font));
  import glfw.render : Renderer_Initialize;
  Renderer_Initialize;
}

extern(C) void On_Window_Resize(GLFWwindow* w, int width, int height) nothrow {
    glViewport(0, 0, width, height);

    window_width  = width;
    window_height = height;
}
