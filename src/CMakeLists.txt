# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(llx_flutter_library VERSION 0.0.1 LANGUAGES C CXX)

set(LLAMA_CURL OFF CACHE BOOL "llama: use libcurl to download model from an URL" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "llama: build common utils library" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "llama: build tests" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "llama: build tools" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "llama: build examples" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "llama: build server example" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "ggml: use LLAMAFILE" FORCE)

add_subdirectory(llama.cpp build-llama)

add_library(llx_flutter SHARED
  "llx_flutter.c"
)

set_target_properties(llx_flutter PROPERTIES
  PUBLIC_HEADER llx_flutter.h
  OUTPUT_NAME "llx_flutter"
)

target_compile_definitions(llx_flutter PUBLIC DART_SHARED_LIB)

target_link_libraries(llx_flutter PRIVATE llama)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(llx_flutter PRIVATE "-Wl,-z,max-page-size=16384")
endif()
