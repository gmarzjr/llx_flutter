# llx_flutter

`llx_flutter` is a Flutter FFI plugin for running local GGUF language models
through [llama.cpp](https://github.com/ggerganov/llama.cpp). It is focused on
mobile, on-device inference: Dart owns the app-facing API and lifecycle, while
the native layer owns llama.cpp model loading, context creation, token
generation, and runtime diagnostics.

The repository includes an example app that bundles a GGUF model as a Flutter
asset, copies it to a real filesystem path for native FFI access, streams tokens
back into the UI, and reports basic generation metrics.

## Current capabilities

* Load a GGUF model from a local path with configurable `nGpuLayers`.
* Create an inference context with configurable `nCtx` and `nThreads`.
* Stream generated text through a Dart `Stream<String>`.
* Run generation on a helper isolate so long native calls do not block the UI.
* Read llama.cpp system/backend diagnostics from Dart.
* Read per-generation prompt/decode timing, token counts, and tokens per second.

The primary Dart entry points are `LlxFlutter.initialize`,
`LlxModel.loadFromFile`, `LlxContext.create`, `LlxContext.generateStream`,
`LlxContext.generationStats`, and `LlxFlutter.shutdown`.

## Platform support

| Platform | Status | Native dependency path |
| --- | --- | --- |
| Android | Supported | Flutter/Gradle invokes `src/CMakeLists.txt`, which builds llama.cpp from the `src/llama.cpp` submodule. |
| iOS | Supported | CocoaPods links a locally generated `ios/Frameworks/llama.xcframework`. |

Android builds are CPU-only by default and optimized for compatibility. The
plugin builds native code as `Release`, links the ggml CPU backend directly, and
disables dynamic backend variants because Flutter Android packaging can leave
native libraries unextracted from the APK.

iOS does not build llama.cpp during the Flutter build. The `llama.xcframework`
is intentionally not tracked in git because it is hundreds of megabytes. Build
it from the submodule before building or running the iOS example.

The example passes `nGpuLayers: 0`, so inference is CPU-only unless the app is
changed to request GPU offload and the native build includes an appropriate
backend.

## Prerequisites

* Flutter with Dart support for this package's SDK constraints.
* Git submodule support.
* Android Studio or the Android SDK/NDK for Android builds.
* Xcode, CocoaPods, and CMake for iOS XCFramework generation and iOS builds.
* A local GGUF model for the example app.

## Repository setup

From a fresh clone:

```sh
git submodule update --init --recursive
flutter pub get
cd example
flutter pub get
```

Model weights are not committed. To run the example, place a compatible GGUF
model at:

```text
example/assets/model.gguf
```

`example/assets/*.gguf` is ignored so local model files do not get committed.

## Android build and run

The Android build uses the plugin CMake file at `src/CMakeLists.txt`; no manual
native build step is required beyond initializing the llama.cpp submodule.

```sh
cd example
flutter run -d <android-device-id>
```

To verify a debug APK build:

```sh
cd example
flutter build apk --debug
```

Android arm64 builds can opt into KleidiAI CPU kernels by passing
`-DLLX_ANDROID_USE_KLEIDIAI=ON` to the plugin CMake build. That is off by
default because llama.cpp fetches KleidiAI source during native configure and it
needs real-device validation.

Android GPU acceleration is also not enabled by default. llama.cpp supports
mobile GPU backend work in some configurations, but this plugin currently keeps
the default Android path CPU-first and portable.

## iOS build and run

Generate the llama.cpp XCFramework first:

```sh
git submodule update --init --recursive
cd src/llama.cpp
./build-xcframework.sh
cd ../..
mkdir -p ios/Frameworks
rm -rf ios/Frameworks/llama.xcframework
cp -R src/llama.cpp/build-apple/llama.xcframework ios/Frameworks/llama.xcframework
```

Then build or run the example:

```sh
cd example
flutter run -d <ios-device-or-simulator-id>
```

To verify a debug iOS build without code signing:

```sh
cd example
flutter build ios --debug --no-codesign
```

`ios/Frameworks/llama.xcframework` is ignored by git. Regenerate and copy it
after a clean checkout, after deleting ignored build artifacts, or after moving
the repo to a new machine.

## Runtime diagnostics

The Dart API exposes llama.cpp runtime details so apps can confirm what native
code is active on a device:

* `LlxFlutter.systemInfo` reports llama.cpp CPU/system feature information.
* `LlxFlutter.backendInfo` reports registered ggml backends and devices.
* `LlxContext.nThreads` reports the actual thread count used by a context.
* `LlxContext.generationStats` reports prompt tokens, generated tokens, prompt
  time, decode time, and tokens per second for the most recent generation.

The example prints system/backend diagnostics during startup and displays thread
count plus generation metrics after a run.

## Regenerating Dart bindings

Bindings are generated from `src/llx_flutter.h` with `package:ffigen`.

```sh
dart run ffigen --config ffigen.yaml
```

Regenerate bindings after changing the exported C API in `src/llx_flutter.h`.

## Troubleshooting

If Android native configuration fails, first confirm the submodule exists:

```sh
git submodule update --init --recursive
```

If iOS cannot find `llama.xcframework`, regenerate it with
`src/llama.cpp/build-xcframework.sh` and copy the output to
`ios/Frameworks/llama.xcframework`.

If the generated iOS framework cannot expose all required llama.cpp headers, the
local `build-xcframework.sh` may need the pending upstream module-map fix for
`ggml-opt.h`. That fix is intended to land in llama.cpp separately; until then,
use a local script patch when generating the framework.
