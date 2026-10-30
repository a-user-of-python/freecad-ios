cmake_minimum_required(VERSION 3.21)
project(S4Tier1 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets OpenGL OpenGLWidgets)

if(NOT DEFINED S4_PREFIX)
  message(FATAL_ERROR "S4_PREFIX not set")
endif()
if(NOT DEFINED FREECAD_SRC_DIR)
  message(FATAL_ERROR "FREECAD_SRC_DIR not set (extracted pinned FreeCAD tree)")
endif()
if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator" OR QT_UIKIT_SDK MATCHES "simulator")
  set(S4_ARCH_DIR "sim")
else()
  set(S4_ARCH_DIR "device")
endif()
set(S4_ARCH_PREFIX "${S4_PREFIX}/${S4_ARCH_DIR}")
set(GL4ES_INC "${S4_PREFIX}/src/gl4es/include")
set(GLU_INC "${S4_PREFIX}/src/glu-include")

foreach(lib lib/libGL.a lib/libGLU.a lib/libCoin.a)
  if(NOT EXISTS "${S4_ARCH_PREFIX}/${lib}")
    message(FATAL_ERROR "missing ${S4_ARCH_PREFIX}/${lib}")
  endif()
endforeach()

# ---- FreeCAD's vendored Quarter, compiled UNMODIFIED from the pinned
# snapshot. Sources per its own CMakeLists (GLOB_RECURSE *.cpp), minus
# SpaceNavigatorDevice.cpp: FreeCAD links the spacenav library only
# when found, and no navigation in this spike uses that device class.
set(QUARTER_DIR "${FREECAD_SRC_DIR}/src/Gui/Quarter")
file(GLOB_RECURSE QUARTER_SOURCES
  "${QUARTER_DIR}/*.cpp")
list(REMOVE_ITEM QUARTER_SOURCES "${QUARTER_DIR}/SpaceNavigatorDevice.cpp")
# FreeCAD-side Inventor extension Quarter depends on (not part of Coin):
list(APPEND QUARTER_SOURCES "${FREECAD_SRC_DIR}/src/Gui/Inventor/SoMouseWheelEvent.cpp")
file(GLOB_RECURSE QUARTER_HEADERS "${QUARTER_DIR}/*.h")

add_library(Quarter STATIC ${QUARTER_SOURCES} ${QUARTER_HEADERS})
# FreeCAD builds as C++20; SoQTQuarterAdaptor.cpp uses std::numbers.
set_target_properties(Quarter PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)
target_compile_definitions(Quarter PRIVATE QUARTER_INTERNAL)
# QuarterWidget.cpp tests GL_MULTISAMPLE through QOpenGLFunctions; the
# enum is absent from the GLES2 headers Qt maps to on iOS. gl4es (and
# GLES3) define it as 0x809D — supply the identical value.
target_compile_definitions(Quarter PRIVATE GL_MULTISAMPLE=0x809D)
target_include_directories(Quarter PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/fcshim"  # FIRST: Base/* + FCConfig.h spike shims win over FreeCAD's real Base headers
  "${FREECAD_SRC_DIR}/src"          # for <Gui/Quarter/...> includes
  "${FREECAD_SRC_DIR}/src/Gui"      # for <Quarter/Basic.h> style includes (Quarter's own)
  "${QUARTER_DIR}"                  # for local "QuarterWidget.h" style includes
  "${S4_ARCH_PREFIX}/include"       # Coin headers
  "${GL4ES_INC}"                    # <GL/gl.h> == gl4es
  "${GLU_INC}")                     # <GL/glu.h>
target_link_libraries(Quarter PUBLIC
  Qt6::Widgets Qt6::OpenGL Qt6::OpenGLWidgets
  "${S4_ARCH_PREFIX}/lib/libCoin.a")

qt_add_executable(S4Tier1 MACOSX_BUNDLE main.cpp gl_probe.cpp gl_probe.h)
set_target_properties(S4Tier1 PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)
target_include_directories(S4Tier1 PRIVATE "${GL4ES_INC}")
target_link_libraries(S4Tier1 PRIVATE
  Quarter
  "${S4_ARCH_PREFIX}/lib/libGLU.a"
  "${S4_ARCH_PREFIX}/lib/libGL.a"
  "${S4_ARCH_PREFIX}/lib/libGL4ESAppleFix.a"
  "-framework OpenGLES" "-framework CoreGraphics" "-framework QuartzCore"
  "-framework CoreFoundation" "-framework Foundation" "-framework UIKit"
  "-ldl" "-lm"
  "-Wl,-export_dynamic")
set_target_properties(S4Tier1 PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  MACOSX_BUNDLE_BUNDLE_NAME "S4Tier1"
  MACOSX_BUNDLE_BUNDLE_IDENTIFIER "com.user.freecad.s4tier1"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
  XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
