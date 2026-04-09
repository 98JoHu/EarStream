import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../model/meditation_config.dart';

/// Debug widget to help users verify their API keys are loaded correctly
class ApiDebugWidget extends StatefulWidget {
  const ApiDebugWidget({super.key});

  @override
  State<ApiDebugWidget> createState() => _ApiDebugWidgetState();
}

class _ApiDebugWidgetState extends State<ApiDebugWidget> {
  bool _isTesting = false;
  String? _testResult;

  Future<void> _testGeminiApi() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      print('🧪 Testing Gemini API with key: ${MeditationConfig.geminiApiKey.substring(0, 10)}...');
      
      // First, list available models
      print('📋 Listing available models...');
      final listUrl = Uri.parse(
        'https://generativelanguage.googleapis.com/v1/models?key=${MeditationConfig.geminiApiKey}'
      );
      
      final listResponse = await http.get(listUrl);
      
      if (listResponse.statusCode == 200) {
        final data = jsonDecode(listResponse.body);
        final models = data['models'] as List?;
        
        print('📋 Available models:');
        if (models != null && models.isNotEmpty) {
          for (final model in models) {
            final name = model['name']?.toString() ?? 'unknown';
            final supportedMethods = model['supportedGenerationMethods'] as List?;
            print('  - $name: ${supportedMethods?.join(", ") ?? "no methods"}');
          }
          
          // Try to find a model that supports generateContent
          final workingModels = models.where((m) {
            final methods = m['supportedGenerationMethods'] as List?;
            return methods?.contains('generateContent') ?? false;
          }).toList();
          
          if (workingModels.isNotEmpty) {
            final firstModel = workingModels.first;
            final modelName = firstModel['name']?.toString().replaceFirst('models/', '') ?? '';
            
            print('🔍 Testing with first working model: $modelName');
            final testUrl = Uri.parse(
              'https://generativelanguage.googleapis.com/v1/models/$modelName:generateContent?key=${MeditationConfig.geminiApiKey}'
            );
            
            final testResponse = await http.post(
              testUrl,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [{
                  'parts': [{'text': 'Reply with just "OK"'}]
                }]
              }),
            );
            
            if (testResponse.statusCode == 200) {
              final testData = jsonDecode(testResponse.body);
              final text = testData['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? 'No response';
              print('SUCCESS with model: $modelName - Response: $text');
              
              setState(() {
                _testResult = 'API Working!\nModel: $modelName\nResponse: ${text.substring(0, text.length > 30 ? 30 : text.length)}...';
              });
              return;
            } else {
              print('Test failed: ${testResponse.statusCode} - ${testResponse.body}');
            }
          } else {
            setState(() {
              _testResult = 'No models support generateContent!\n\nAvailable models: ${models.length}\nYour key might be restricted.';
            });
            return;
          }
        } else {
          setState(() {
            _testResult = 'No models available!\n\nYour API key has no access to Gemini models.';
          });
          return;
        }
      } else {
        print('ListModels failed: ${listResponse.statusCode} - ${listResponse.body}');
        setState(() {
          _testResult = 'Cannot list models: ${listResponse.statusCode}\n${listResponse.body.substring(0, listResponse.body.length > 100 ? 100 : listResponse.body.length)}';
        });
        return;
      }
      
      setState(() {
        _testResult = 'Test failed!\n\nTry creating a NEW key at:\naistudio.google.com/apikey';
      });
    } catch (e) {
      print('Gemini API Test Failed: $e');
      setState(() {
        _testResult = 'API Failed: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final geminiKey = MeditationConfig.geminiApiKey;
    final ttsKey = MeditationConfig.googleCloudTtsApiKey;
    
    final hasValidGemini = MeditationConfig.hasValidGeminiKey;
    final hasValidTts = MeditationConfig.hasValidTtsKey;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Configuration Debug'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple.shade50, Colors.blue.shade50],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              '🔍 API Key Status',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            
            // Gemini API Key Card
            _buildApiCard(
              title: '🤖 Gemini API (LLM)',
              keyValue: geminiKey,
              isValid: hasValidGemini,
              description: 'Used for generating personalized meditation content with biomarkers',
              testButton: hasValidGemini ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isTesting ? null : _testGeminiApi,
                    icon: _isTesting 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.science, size: 16),
                    label: Text(_isTesting ? 'Testing...' : 'Test API'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  if (_testResult != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _testResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _testResult!.startsWith('✅') ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ) : null,
            ),
            
            const SizedBox(height: 20),
            
            // Google Cloud TTS API Key Card
            _buildApiCard(
              title: '🎤 Google Cloud TTS API',
              keyValue: ttsKey,
              isValid: hasValidTts,
              description: 'Used for high-quality voice synthesis (optional)',
              isOptional: true,
            ),
            
            const SizedBox(height: 30),
            
            // Instructions
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'How to Fix Missing API Keys',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. Open the .env file in your project root:\n'
                      '   /open_wearable/.env\n\n'
                      '2. Replace placeholder values with real API keys:\n'
                      '   GEMINI_API_KEY=AIzaSy...\n\n'
                      '3. Restart the app (hot reload won\'t work for .env changes)\n\n'
                      '4. Get free API keys from:\n'
                      '   • Gemini: https://aistudio.google.com/apikey\n'
                      '   • Cloud TTS: https://console.cloud.google.com',
                      style: TextStyle(fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(
                          text: 'https://aistudio.google.com/apikey'
                        ));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied to clipboard!')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy Gemini API Link'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildApiCard({
    required String title,
    required String keyValue,
    required bool isValid,
    required String description,
    bool isOptional = false,
    Widget? testButton,
  }) {
    final statusColor = isValid ? Colors.green : (isOptional ? Colors.orange : Colors.red);
    final statusIcon = isValid ? Icons.check_circle : (isOptional ? Icons.info : Icons.error);
    final statusText = isValid ? 'Configured ✓' : (isOptional ? 'Optional (using fallback)' : 'Missing or Invalid');
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(statusIcon, color: statusColor, size: 28),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Status: ',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Key Value: ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    keyValue == 'NONE' 
                      ? 'NOT SET (using fallback)'
                      : keyValue.length > 20 
                        ? '${keyValue.substring(0, 20)}...' 
                        : keyValue,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isValid ? Colors.green[800] : Colors.red[800],
                    ),
                  ),
                ],
              ),
            ),
            if (testButton != null) ...[
              const SizedBox(height: 12),
              testButton,
            ],
          ],
        ),
      ),
    );
  }
}

