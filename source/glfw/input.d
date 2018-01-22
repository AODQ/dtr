module glfw.input;

private struct Mouse{
  float x, y, z;
  float motion_x, motion_y;
  bool left, middle, right;
  bool on_left, on_middle, on_right;
}

Mouse mouse; // gets set by GUI
