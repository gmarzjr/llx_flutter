# llx_flutter_example

Example Flutter app for the `llx_flutter` plugin. It demonstrates the complete
Flutter -> Dart FFI -> native llama.cpp path for local, on-device GGUF
inference.

The app initializes the plugin, copies a bundled GGUF asset to a temporary file
for native access, loads the model once, creates a fresh context for each
generation, streams generated tokens into the UI, and displays generation
metrics.

## What the app shows

* Loading a local GGUF model from Flutter assets.
* Copying the model asset to a real filesystem path for native FFI use.
* Initializing and shutting down the llama.cpp backend.
* Loading one model and creating a fresh context per generation.
* Streaming tokens through `LlxContext.generateStream`.
* Controlling max tokens, temperature, and thread count from the UI.
* Reporting actual thread count and generation throughput.
* Formatting prompts for a Qwen3-style chat model.

## Model file

Model weights are not committed to this repository. Place a compatible GGUF
model at:

```text
example/assets/model.gguf
```

The app references it in Flutter as:

```text
assets/model.gguf
```

`example/assets/*.gguf` is ignored by git, so local model files stay out of the
repository. The current example is written around a Qwen3-style chat model; a
small quantized model is usually the most practical choice for mobile testing.

## Prompt format

The app formats user input as a Qwen3-style chat prompt:

```text
<|im_start|>user
{user prompt} /no_think
<|im_end|>
<|im_start|>assistant
```

The `/no_think` instruction is specific to Qwen3-style behavior. If you use a
different GGUF model family, update `_formatQwen3Prompt` in `lib/main.dart`.

## Generation settings

The UI exposes:

| Field | Default | Description |
| --- | ---: | --- |
| Max tokens | `512` | Maximum number of tokens to generate. |
| Temperature | `0.0` | Sampling temperature; `0.0` uses greedy sampling. |
| Threads | Auto | Optional positive thread count for the native context. |

The example also uses:

```text
nGpuLayers: 0
nCtx: 1024
```

`nGpuLayers` is set when the model is loaded. `nCtx` and `nThreads` are set when
the context is created. Each generation disposes its context after streaming
finishes.

## Setup

From the repository root:

```sh
git submodule update --init --recursive
flutter pub get
cd example
flutter pub get
```

Then place your model at:

```text
example/assets/model.gguf
```

## Android

Android builds llama.cpp through the plugin CMake build automatically. Run on an
Android device or emulator with:

```sh
cd example
flutter devices
flutter run -d <android-device-id>
```

To verify a debug APK build:

```sh
cd example
flutter build apk --debug
```

## iOS

iOS requires a locally generated `llama.xcframework`. From the repository root:

```sh
git submodule update --init --recursive
cd src/llama.cpp
./build-xcframework.sh
cd ../..
mkdir -p ios/Frameworks
rm -rf ios/Frameworks/llama.xcframework
cp -R src/llama.cpp/build-apple/llama.xcframework ios/Frameworks/llama.xcframework
```

Then run the example:

```sh
cd example
flutter devices
flutter run -d <ios-device-or-simulator-id>
```

To verify a debug iOS build without code signing:

```sh
cd example
flutter build ios --debug --no-codesign
```

The generated `ios/Frameworks/llama.xcframework` is ignored by git. Rebuild and
copy it after a clean checkout or whenever the ignored framework is missing.

## UI

The example intentionally keeps the interface small:

* Prompt input.
* Max token input.
* Temperature input.
* Thread count input.
* Clear prompt button.
* Generate button.
* Streamed response output.
* Thread and generation metrics.

Model selection, chat history, cancellation, production lifecycle handling, and
platform-specific packaging are outside the scope of this example.
