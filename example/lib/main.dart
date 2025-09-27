import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffi/ffi.dart';
import 'package:llx_flutter/llx_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Not initialized';
  final TextEditingController _promptController = TextEditingController();
  String _response = '';
  bool _isGenerating = false;
  String? _modelPath;

  @override
  void initState() {
    super.initState();
    _initializeLlx();
    _promptController.text = 'Hi';
    _prepareModel();
  }

  Future<void> _prepareModel() async {
    setState(() {
      _status = 'Preparing model from assets...';
    });

    try {
      _modelPath = await prepareAssetForFFI('assets/qwen3-0.6b-q4_k_s.gguf', 'qwen3-0.6b-q4_k_s.gguf');
      setState(() {
        _status = 'Model ready at: $_modelPath';
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to prepare model: $e';
      });
    }
  }

  Future<String> prepareAssetForFFI(String assetPath, String filename) async {
    // Load from assets
    final data = await rootBundle.load(assetPath);
    // Write to a real temp file
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path; // This path can be passed to C
  }

  void _initializeLlx() {
    try {
      LlxFlutter.initialize();
      setState(() {
        _status = 'LLX backend initialized successfully';
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to initialize: $e';
      });
    }
  }

  void _generate() async {
    if (_isGenerating || _modelPath == null) return;

    setState(() {
      _isGenerating = true;
      _response = '';
      _status = 'Loading model...';
    });

    try {
      // Load model using the prepared file path
      final model = LlxModel.loadFromFile(_modelPath!, nGpuLayers: 0);
      
      setState(() {
        _status = 'Creating context...';
      });

      // Create context
      final context = LlxContext.create(model, nCtx: 2048);

      setState(() {
        _status = 'Generating...';
      });

      // Generate with streaming
      await for (final token in context.generateStream(
        '<|im_start|>user\n/no_think ${_promptController.text}<|im_end|>\n<|im_start|>assistant\n',
        nPredict: 500,
        temperature: 0.8,
      )) {
        setState(() {
          _response += token;
        });
      }

      // Cleanup
      context.dispose();
      model.dispose();

      setState(() {
        _status = 'Generation complete';
      });

    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    LlxFlutter.shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('LLX Flutter Example')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                _status,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _promptController,
                decoration: const InputDecoration(
                  labelText: 'Prompt',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: (_isGenerating || _modelPath == null) ? null : _generate,
                child: Text(_isGenerating ? 'Generating...' : 'Generate'),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _response.isEmpty ? 'Response will appear here...' : _response,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
