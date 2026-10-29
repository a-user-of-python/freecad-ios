cmake_minimum_required(VERSION 3.21)
project(S4Tier0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets OpenGL OpenGLWidgets)

# gl4es prefix, produced by Scripts/build-s4-lib.sh (build_gl4es):
#   $S4_PREFIX/{device,sim}/lib/libGL.a, include = gl4es source include dir
if(NOT DEFINED S4_PREFIX)
  message(FATAL_ERROR "S4_PREFIX not set")
endif()
if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator" OR QT_UIKIT_SDK MATCHES "simulator")
  set(S4_ARCH_DIR "sim")
else()
  set(S4_ARCH_DIR "device")
endif()
set(GL4ES_LIB "${S4_PREFIX}/${S4_ARCH_DIR}/lib/libGL.a")
set(GL4ES_INC "${S4_PREFIX}/src/gl4es/include")
if(NOT EXISTS "${GL4ES_LIB}")
  message(FATAL_ERROR "gl4es lib missing: ${GL4ES_LIB}")
endif()

qt_add_executable(S4Tier0 MACOSX_BUNDLE main.cpp gl_draw.cpp gl_draw.h)
target_include_directories(S4Tier0 PRIVATE "${GL4ES_INC}")
target_link_libraries(S4Tier0 PRIVATE
  Qt6::Widgets Qt6::OpenGL Qt6::OpenGLWidgets
  "${GL4ES_LIB}"
  "${S4_PREFIX}/${S4_ARCH_DIR}/lib/libGL4ESAppleFix.a"
  "-framework OpenGLES" "-framework CoreGraphics" "-framework QuartzCore"
  "-ldl" "-lm")
set_target_properties(S4Tier0 PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  MACOSX_BUNDLE_BUNDLE_NAME "S4Tier0"
  MACOSX_BUNDLE_BUNDLE_IDENTIFIER "com.user.freecad.s4tier0"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
  XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
