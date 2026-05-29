# llx_flutter_example

Example Flutter app for the `llx_flutter` plugin.

This example demonstrates local llama.cpp-backed inference from Flutter using a GGUF model bundled as an app asset. It loads a model through the plugin, creates an inference context, streams generated tokens into the UI, and exposes a few simple generation controls.

## What this example shows

* Loading a local GGUF model from Flutter assets
* Copying the model asset to a real filesystem path for native FFI use
* Initializing the `llx_flutter` backend
* Loading the model once when the app starts
* Creating a fresh inference context for each generation
* Streaming generated text into the Flutter UI
* Passing generation parameters from simple text fields
* Formatting prompts for a Qwen3-style chat model

## Model file

Model weights are not committed to this repository.

The example expects a GGUF model at:

```text
example/assets/model.gguf
```

The model is referenced in the Flutter asset bundle as:

```text
assets/model.gguf
```

To run inference, place a compatible GGUF model at `example/assets/model.gguf`.

## Qwen3 prompt format

This example is written around a Qwen3-style chat prompt template.

The app formats user input like this:

```text
<|im_start|>user
{user prompt} /no_think
<|im_end|>
<|im_start|>assistant
```

The `/no_think` instruction is specific to Qwen3-style behavior. Other GGUF chat models may require a different prompt template.

If you use a different model family, update the prompt formatting function in `lib/main.dart`.

## Generation settings

The example exposes these generation-time values in the UI:

| Field       | Default | Description                          |
| ----------- | ------: | ------------------------------------ |
| Max tokens  |   `512` | Maximum number of tokens to generate |
| Temperature |   `0.0` | Sampling temperature                 |

The example uses:

```text
nGpuLayers: 0
nCtx: 1024
```

`nGpuLayers` is set when the model is loaded. `nCtx` is set when the context is created.

The model is loaded once during app initialization. Each generation creates a fresh context, streams output, and disposes the context after generation completes.

## Running the example

From the repository root:

```sh
git submodule update --init --recursive
flutter pub get
```

Then from the example directory:

```sh
cd example
flutter pub get
```

Place a compatible GGUF model at:

```text
example/assets/model.gguf
```

Run the app:

```sh
flutter run
```

To run on a specific device:

```sh
flutter devices
flutter run -d <device-id>
```

## iOS build check

A debug iOS build can be checked with:

```sh
flutter build ios --debug --no-codesign
```

This verifies the Flutter example and plugin build without requiring code signing.

## Notes

This example is intentionally small. It is meant to make the Flutter → Dart FFI → native llama.cpp path easy to inspect.

The UI is minimal by design:

* prompt input
* max token input
* temperature input
* clear prompt button
* generate button
* streamed response output

Model selection, chat history, cancellation, production lifecycle handling, and platform-specific packaging details are outside the scope of this example.

