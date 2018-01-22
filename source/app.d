/**
    This example demonstrates how to properly handle memory management
    for displaying things such as text.
*/

import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;

static import rasterizer;

import derelict.opengl;
import derelict.glfw3.glfw3;

import imgui;
import glfw;

int main(string[] args) {
  int width = 1024, height = 768;
  string font_path = thisExePath().dirName().buildPath("DroidSans.ttf");
  Initialize(width, height, font_path);

  glClearColor(0.8f, 0.8f, 0.8f, 1.0f);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDisable(GL_DEPTH_TEST);

  rasterizer.Initialize();

  while (!glfwWindowShouldClose(window)) {
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    rasterizer.Render();
    gui.render();
    glfwSwapBuffers(window);
    glfwPollEvents();
  }

  imguiDestroy();
  return 0;
}
