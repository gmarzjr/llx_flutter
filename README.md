# llx_flutter

A Flutter FFI plugin that wraps `llama.cpp` for local GGUF inference.

## Platform support

* Android builds `llama.cpp` from the `src/llama.cpp` submodule through the
  plugin CMake build. The default Android build is CPU-only and optimized for
  compatibility: native code is built as `Release`, and the CPU backend is linked
  directly rather than discovered from dynamically loaded backend variant files.
* iOS uses the checked-in `ios/Frameworks/llama.xcframework`. The iOS build does
  not build the `llama.cpp` submodule.
* Android GPU acceleration is not enabled by default. llama.cpp has Android GPU
  backend options such as OpenCL for newer Qualcomm Adreno devices, but those
  require a separate opt-in build flavor and real-device validation.
* Android arm64 builds can opt into KleidiAI CPU kernels by passing
  `-DLLX_ANDROID_USE_KLEIDIAI=ON` to the plugin CMake build. This is disabled by
  default because llama.cpp fetches the KleidiAI source during native configure.
* Dynamic ggml CPU backend variants are not enabled by default because Flutter's
  Android packaging may leave native libraries unextracted from the APK, which
  makes filesystem-based backend discovery unreliable.

The example currently passes `nGpuLayers: 0`, so generation is CPU-only unless
the app is changed to request GPU offload and the native build includes a GPU
backend.

## Building the example

```sh
flutter pub get
cd example
flutter pub get
flutter build apk --debug
flutter build ios --debug --no-codesign
```

The Android APK build requires the `src/llama.cpp` submodule to be present.

## Runtime diagnostics

The Dart API exposes `LlxFlutter.systemInfo`, `LlxFlutter.backendInfo`, and
`LlxContext.nThreads` so apps can confirm which llama.cpp CPU features, backends,
devices, and thread count are active at runtime.

## Binding to native code

To use the native code, bindings in Dart are needed.
To avoid writing these by hand, they are generated from the header file
(`src/llx_flutter.h`) by `package:ffigen`.
Regenerate the bindings by running `dart run ffigen --config ffigen.yaml`.

## Invoking native code

Very short-running native functions can be directly invoked from any isolate.
For example, see `sum` in `lib/llx_flutter.dart`.

Longer-running functions should be invoked on a helper isolate to avoid
dropping frames in Flutter applications.
For example, see `sumAsync` in `lib/llx_flutter.dart`.

## Flutter help

For help getting started with Flutter, view our
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
