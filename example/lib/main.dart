import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llx_flutter/llx_flutter.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const LlxExampleApp());
}

class LlxExampleApp extends StatelessWidget {
  const LlxExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: LlxExamplePage(),
    );
  }
}

class LlxExamplePage extends StatefulWidget {
  const LlxExamplePage({super.key});

  @override
  State<LlxExamplePage> createState() => _LlxExamplePageState();
}

class _LlxExamplePageState extends State<LlxExamplePage> {
  static const String _modelAssetPath = 'assets/model.gguf';
  static const String _modelFilename = 'model.gguf';

  // This example is written for Qwen3-style chat prompts.
  //
  // Qwen3 supports a "/no_think" instruction to disable thinking mode. Other
  // GGUF chat models may require a different prompt template.
  static const String _qwenNoThinkInstruction = '/no_think';

  static const int _contextSize = 1024;
  static const int _maxGeneratedTokens = 512;
  static const int _gpuLayers = 0;

  final TextEditingController _promptController = TextEditingController();

  String _status = 'Starting...';
  String _response = '';
  String? _modelPath;
  bool _isPreparingModel = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _initializeExample();
  }

  Future<void> _initializeExample() async {
    try {
      LlxFlutter.initialize();
      _setStatus('LLX backend initialized');

      final modelPath = await _copyAssetToTempFile(
        assetPath: _modelAssetPath,
        filename: _modelFilename,
      );

      if (!mounted) return;

      setState(() {
        _modelPath = modelPath;
        _isPreparingModel = false;
        _status = 'Model ready';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isPreparingModel = false;
        _status = 'Failed to initialize example: $e';
      });
    }
  }

  Future<String> _copyAssetToTempFile({
    required String assetPath,
    required String filename,
  }) async {
    _setStatus('Preparing model from assets...');

    final data = await rootBundle.load(assetPath);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$filename');

    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );

    return file.path;
  }

  Future<void> _generate() async {
    if (_isGenerating || _modelPath == null) return;

    final userPrompt = _promptController.text.trim();

    if (userPrompt.isEmpty) {
      _setStatus('Enter a prompt first.');
      return;
    }

    final prompt = _formatQwen3Prompt(userPrompt);

    setState(() {
      _isGenerating = true;
      _response = '';
      _status = 'Loading model...';
    });

    LlxModel? model;
    LlxContext? context;

    try {
      model = LlxModel.loadFromFile(
        _modelPath!,
        nGpuLayers: _gpuLayers,
      );

      _setStatus('Creating context...');

      context = LlxContext.create(
        model,
        nCtx: _contextSize,
      );

      _setStatus('Generating...');

      await for (final token in context.generateStream(
        prompt,
        nPredict: _maxGeneratedTokens,
        temperature: 0.0,
      )) {
        if (!mounted) return;

        setState(() {
          _response += token;
        });
      }

      _setStatus('Generation complete');
    } catch (e) {
      _setStatus('Error: $e');
    } finally {
      context?.dispose();
      model?.dispose();

      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  String _formatQwen3Prompt(String userPrompt) {
    return '''
<|im_start|>user
$userPrompt $_qwenNoThinkInstruction
<|im_end|>
<|im_start|>assistant
''';
  }

  void _setStatus(String status) {
    if (!mounted) return;

    setState(() {
      _status = status;
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    LlxFlutter.shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canGenerate =
        !_isPreparingModel && !_isGenerating && _modelPath != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LLX Flutter Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
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
                hintText: 'Enter a prompt for the local Qwen3 model',
                border: OutlineInputBorder(),
              ),
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: canGenerate ? _generate : null,
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
                    _response.isEmpty
                        ? 'Response will appear here...'
                        : _response,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

