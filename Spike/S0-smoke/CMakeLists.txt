cmake_minimum_required(VERSION 3.16)
project(S0Smoke CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 COMPONENTS Core Gui Widgets REQUIRED)

qt_add_executable(s0-smoke main.cpp)
target_link_libraries(s0-smoke PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets)
set_target_properties(s0-smoke PROPERTIES
  MACOSX_BUNDLE TRUE
  MACOSX_BUNDLE_GUI_IDENTIFIER "com.user.freecad.s0smoke"
  MACOSX_BUNDLE_BUNDLE_VERSION "1"
  MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
)
