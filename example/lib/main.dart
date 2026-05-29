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
    return const MaterialApp(home: LlxExamplePage());
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
  static const int _gpuLayers = 0;

  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _maxTokensController = TextEditingController(
    text: '512',
  );
  final TextEditingController _temperatureController = TextEditingController(
    text: '0.0',
  );
  final TextEditingController _threadsController = TextEditingController();

  String _response = '';
  String _metrics = '';
  LlxModel? _model;
  bool _isLoadingModel = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _initializeExample();
  }

  Future<void> _initializeExample() async {
    try {
      LlxFlutter.initialize();
      debugPrint('LLX system info: ${LlxFlutter.systemInfo}');
      debugPrint('LLX backend info: ${LlxFlutter.backendInfo}');

      final modelPath = await _copyAssetToTempFile(
        assetPath: _modelAssetPath,
        filename: _modelFilename,
      );

      final model = LlxModel.loadFromFile(modelPath, nGpuLayers: _gpuLayers);

      if (!mounted) {
        model.dispose();
        return;
      }

      setState(() {
        _model = model;
        _isLoadingModel = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingModel = false;
        _response = 'Failed to initialize example: $e';
      });
    }
  }

  Future<String> _copyAssetToTempFile({
    required String assetPath,
    required String filename,
  }) async {
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
    if (_isGenerating || _model == null) return;

    final userPrompt = _promptController.text.trim();
    if (userPrompt.isEmpty) {
      setState(() {
        _response = 'Enter a prompt first.';
      });
      return;
    }

    final maxTokens = int.tryParse(_maxTokensController.text.trim());
    if (maxTokens == null || maxTokens <= 0) {
      setState(() {
        _response = 'Max tokens must be a positive integer.';
      });
      return;
    }

    final temperature = double.tryParse(_temperatureController.text.trim());
    if (temperature == null || temperature < 0) {
      setState(() {
        _response = 'Temperature must be a number greater than or equal to 0.';
      });
      return;
    }

    final threadsText = _threadsController.text.trim();
    final requestedThreads = threadsText.isEmpty
        ? null
        : int.tryParse(threadsText);
    if (threadsText.isNotEmpty &&
        (requestedThreads == null || requestedThreads <= 0)) {
      setState(() {
        _response = 'Threads must be empty or a positive integer.';
      });
      return;
    }

    final prompt = _formatQwen3Prompt(userPrompt);

    setState(() {
      _isGenerating = true;
      _response = '';
      _metrics = '';
    });

    LlxContext? context;

    try {
      context = LlxContext.create(
        _model!,
        nCtx: _contextSize,
        nThreads: requestedThreads,
      );
      debugPrint('LLX context threads: ${context.nThreads}');
      if (mounted) {
        setState(() {
          _metrics = 'Threads: ${context!.nThreads}';
        });
      }

      await for (final token in context.generateStream(
        prompt,
        nPredict: maxTokens,
        temperature: temperature,
      )) {
        if (!mounted) return;

        setState(() {
          _response += token;
        });
      }

      final stats = context.generationStats;
      if (!mounted) return;

      setState(() {
        _metrics = _formatMetrics(context!, stats);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _response = 'Error: $e';
      });
    } finally {
      context?.dispose();

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

  @override
  void dispose() {
    _promptController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    _threadsController.dispose();
    _model?.dispose();
    LlxFlutter.shutdown();
    super.dispose();
  }

  String _formatMetrics(LlxContext context, LlxGenerationStats stats) {
    return 'Threads: ${context.nThreads} | '
        'Prompt: ${stats.promptTokens} tokens in ${stats.promptSeconds.toStringAsFixed(2)}s | '
        'Generated: ${stats.generatedTokens} tokens in ${stats.decodeSeconds.toStringAsFixed(2)}s | '
        '${stats.tokensPerSecond.toStringAsFixed(2)} tok/s';
  }

  @override
  Widget build(BuildContext context) {
    final canGenerate = !_isLoadingModel && !_isGenerating && _model != null;

    return Scaffold(
      appBar: AppBar(title: const Text('LLX Flutter Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                border: OutlineInputBorder(),
              ),
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxTokensController,
                    decoration: const InputDecoration(
                      labelText: 'Max tokens',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _temperatureController,
                    decoration: const InputDecoration(
                      labelText: 'Temperature',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        final isValid = RegExp(
                          r'^\d*\.?\d*$',
                        ).hasMatch(newValue.text);
                        return isValid ? newValue : oldValue;
                      }),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _threadsController,
                    decoration: const InputDecoration(
                      labelText: 'Threads',
                      hintText: 'Auto',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isGenerating
                      ? null
                      : () {
                          _promptController.clear();
                        },
                  child: const Text('Clear prompt'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: canGenerate ? _generate : null,
                  child: Text(_isGenerating ? 'Generating...' : 'Generate'),
                ),
              ],
            ),
            if (_metrics.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text(_metrics)),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(width: double.infinity, child: Text(_response)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
