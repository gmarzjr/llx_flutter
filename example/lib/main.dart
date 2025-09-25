import 'package:flutter/material.dart';
import 'package:llx_flutter/llx_flutter.dart' as llx_flutter;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final systemInfo = llx_flutter.getSystemInfo();

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('llx_flutter Example'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Text(
              systemInfo,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

