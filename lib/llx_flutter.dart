import 'dart:ffi';
import 'dart:io';
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

String getSystemInfo() {
  final ptr = _bindings.llx_get_system_info();
  return ptr.cast<Utf8>().toDartString();
}
