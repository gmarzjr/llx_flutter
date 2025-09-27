import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'llx_flutter_bindings_generated.dart';

const String _libName = 'llx_flutter';

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final LlxFlutterBindings _bindings = LlxFlutterBindings(_dylib);

/// Exception thrown when LLX operations fail
class LlxException implements Exception {
  final int errorCode;
  final String message;
  
  LlxException(this.errorCode, this.message);
  
  @override
  String toString() => 'LlxException($errorCode): $message';
}

/// Wrapper for LLX model
class LlxModel {
  final Pointer<llx_model> _model;
  bool _disposed = false;
  
  LlxModel._(this._model);
  
  /// Load a model from file
  static LlxModel loadFromFile(String modelPath, {int nGpuLayers = 0}) {
    final modelParams = calloc<llx_model_params>();
    final outModel = calloc<Pointer<llx_model>>();
    
    try {
      // Set parameters
      final defaultParams = _bindings.llx_default_model_params();
      modelParams.ref.n_gpu_layers = nGpuLayers;
      
      // Convert path to C string
      final pathPtr = modelPath.toNativeUtf8();
      
      try {
        final error = _bindings.llx_load_model(pathPtr.cast(), modelParams, outModel);
        if (error != LLX_SUCCESS) {
          final errorMsg = _bindings.llx_error_string(error).cast<Utf8>().toDartString();
          throw LlxException(error, errorMsg);
        }
        
        return LlxModel._(outModel.value);
      } finally {
        calloc.free(pathPtr);
      }
    } finally {
      calloc.free(modelParams);
      calloc.free(outModel);
    }
  }
  
  void dispose() {
    if (!_disposed) {
      _bindings.llx_free_model(_model);
      _disposed = true;
    }
  }
  
  bool get isDisposed => _disposed;
  Pointer<llx_model> get pointer => _disposed ? nullptr : _model;
}

/// Wrapper for LLX context
class LlxContext {
  final Pointer<llx_context> _context;
  bool _disposed = false;
  
  LlxContext._(this._context);
  
  /// Create context from model
  static LlxContext create(LlxModel model, {int? nCtx, int? nThreads}) {
    if (model.isDisposed) {
      throw StateError('Cannot create context from disposed model');
    }
    
    final contextParams = calloc<llx_context_params>();
    final outContext = calloc<Pointer<llx_context>>();
    
    try {
      // Set parameters
      final defaultParams = _bindings.llx_default_context_params();
      contextParams.ref.n_ctx = nCtx ?? defaultParams.n_ctx;
      contextParams.ref.n_threads = nThreads ?? defaultParams.n_threads;
      
      final error = _bindings.llx_create_context(model.pointer, contextParams, outContext);
      if (error != LLX_SUCCESS) {
        final errorMsg = _bindings.llx_error_string(error).cast<Utf8>().toDartString();
        throw LlxException(error, errorMsg);
      }
      
      return LlxContext._(outContext.value);
    } finally {
      calloc.free(contextParams);
      calloc.free(outContext);
    }
  }
  
  /// Generate text with streaming callback
  Stream<String> generateStream(
    String prompt, {
    int? nPredict,
    double? temperature,
  }) {
    if (_disposed) {
      throw StateError('Cannot generate from disposed context');
    }
    
    late StreamController<String> controller;
    
    controller = StreamController<String>(
      onListen: () async {
        await _runGeneration(controller, prompt, nPredict, temperature);
      },
      onCancel: () {
        // TODO: Implement cancellation
      },
    );
    
    return controller.stream;
  }
  
  Future<void> _runGeneration(
    StreamController<String> controller,
    String prompt,
    int? nPredict,
    double? temperature,
  ) async {
    // Run on separate isolate to avoid blocking UI
    final port = ReceivePort();
    
    try {
      await Isolate.spawn(_isolateGeneration, [
        port.sendPort,
        _context.address,
        prompt,
        nPredict ?? 32,
        temperature ?? 0.8,
      ]);
      
      await for (final message in port) {
        if (message is String) {
          if (message == '__DONE__') {
            controller.close();
            break;
          } else if (message.startsWith('__ERROR__:')) {
            controller.addError(Exception(message.substring(10)));
            break;
          } else {
            controller.add(message);
          }
        }
      }
    } catch (e) {
      controller.addError(e);
    } finally {
      port.close();
    }
  }
  
  void dispose() {
    if (!_disposed) {
      _bindings.llx_free_context(_context);
      _disposed = true;
    }
  }
  
  bool get isDisposed => _disposed;
}

/// Isolate function for text generation
void _isolateGeneration(List<dynamic> args) {
  final sendPort = args[0] as SendPort;
  final contextAddress = args[1] as int;
  final prompt = args[2] as String;
  final nPredict = args[3] as int;
  final temperature = args[4] as double;
  
  try {
    // Reconstruct context pointer
    final context = Pointer<llx_context>.fromAddress(contextAddress);
    
    // Set up generation parameters
    final genParams = calloc<llx_generate_params>();
    final defaultParams = _bindings.llx_default_generate_params();
    genParams.ref.n_predict = nPredict;
    genParams.ref.temperature = temperature;
    
    // Convert prompt to C string
    final promptPtr = prompt.toNativeUtf8();
    
    // Create callback function
    final callback = Pointer.fromFunction<llx_token_callbackFunction>(
      _tokenCallback,
      false, // Default return value
    );
    
    // Store send port for callback access
    _currentSendPort = sendPort;
    
    try {
      final error = _bindings.llx_generate_stream(
        context,
        promptPtr.cast(),
        genParams,
        callback,
        nullptr,
      );
      
      if (error != LLX_SUCCESS) {
        final errorMsg = _bindings.llx_error_string(error).cast<Utf8>().toDartString();
        sendPort.send('__ERROR__: $errorMsg');
      } else {
        sendPort.send('__DONE__');
      }
    } finally {
      calloc.free(promptPtr);
      calloc.free(genParams);
      _currentSendPort = null;
    }
  } catch (e) {
    sendPort.send('__ERROR__: $e');
  }
}

// Global variable to store current send port for callback
SendPort? _currentSendPort;

/// C callback function for token streaming
bool _tokenCallback(Pointer<Char> tokenPiece, Pointer<Void> userData) {
  try {
    final token = tokenPiece.cast<Utf8>().toDartString();
    _currentSendPort?.send(token);
    return true; // Continue generation
  } catch (e) {
    _currentSendPort?.send('__ERROR__: Failed to process token');
    return false; // Stop generation
  }
}

/// Main LLX Flutter API
class LlxFlutter {
  static bool _initialized = false;
  
  /// Initialize the LLX backend
  static void initialize() {
    if (!_initialized) {
      _bindings.llx_backend_init();
      _initialized = true;
    }
  }
  
  /// Shutdown the LLX backend
  static void shutdown() {
    if (_initialized) {
      _bindings.llx_backend_free();
      _initialized = false;
    }
  }
  
  /// Get error message for error code
  static String getErrorString(int errorCode) {
    return _bindings.llx_error_string(errorCode).cast<Utf8>().toDartString();
  }
}
