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
set(LLAMA_BUILD_APP OFF CACHE BOOL "llama: build the unified binary" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "llama: use openssl to support HTTPS" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "ggml: use LLAMAFILE" FORCE)

if (ANDROID)
  option(LLX_ANDROID_USE_KLEIDIAI "Enable KleidiAI CPU kernels for Android arm64 builds" OFF)

  set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared native libraries" FORCE)
  set(GGML_NATIVE OFF CACHE BOOL "ggml: use -march=native" FORCE)
  set(GGML_BACKEND_DL OFF CACHE BOOL "ggml: build backends as dynamic libraries" FORCE)
  set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "ggml: build all CPU backend variants" FORCE)

  if (ANDROID_ABI STREQUAL "arm64-v8a")
    set(GGML_SYSTEM_ARCH "ARM" CACHE STRING "ggml: system architecture" FORCE)
    set(GGML_CPU_KLEIDIAI ${LLX_ANDROID_USE_KLEIDIAI} CACHE BOOL "ggml: use KleidiAI optimized kernels" FORCE)
    set(GGML_OPENMP ON CACHE BOOL "ggml: use OpenMP" FORCE)
  elseif (ANDROID_ABI STREQUAL "x86_64")
    set(GGML_SYSTEM_ARCH "x86" CACHE STRING "ggml: system architecture" FORCE)
    set(GGML_OPENMP OFF CACHE BOOL "ggml: use OpenMP" FORCE)
  endif()
endif()

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
