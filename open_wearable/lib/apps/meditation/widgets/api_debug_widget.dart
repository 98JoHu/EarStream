import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../widgets/logging/log_files_screen.dart';
import '../model/meditation_config.dart';
import '../model/user_account.dart';

class ApiDebugWidget extends StatefulWidget {
  final String currentModeLabel;
  final String sensorSourceLabel;
  final DateTime? scheduledMeditationTime;

  const ApiDebugWidget({
    super.key,
    required this.currentModeLabel,
    required this.sensorSourceLabel,
    this.scheduledMeditationTime,
  });

  @override
  State<ApiDebugWidget> createState() => _ApiDebugWidgetState();
}

class _ApiDebugWidgetState extends State<ApiDebugWidget> {
  late Future<UserAccount> _accountFuture;
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _accountFuture = UserAccount.load();
  }

  String? _sanitizeGeminiKey(String? value) {
    final key = value?.trim() ?? '';
    if (key.startsWith('AIza')) {
      return key;
    }
    return null;
  }

  String? _sanitizeLongSecret(String? value) {
    final secret = value?.trim() ?? '';
    if (secret.length > 20) {
      return secret;
    }
    return null;
  }

  String? _effectiveGeminiKey(UserAccount account) {
    return _sanitizeGeminiKey(account.geminiApiKey) ??
        _sanitizeGeminiKey(MeditationConfig.geminiApiKey);
  }

  String? _effectiveElevenLabsKey(UserAccount account) {
    return _sanitizeLongSecret(account.elevenLabsApiKey) ??
        _sanitizeLongSecret(MeditationConfig.elevenLabsApiKey);
  }

  String? _effectiveOutlookToken(UserAccount account) {
    return _sanitizeLongSecret(account.microsoftGraphAccessToken) ??
        _sanitizeLongSecret(MeditationConfig.microsoftGraphAccessToken);
  }

  String _sourceLabel({
    required String localValue,
    required bool hasEnvFallback,
  }) {
    if (localValue.trim().isNotEmpty) {
      return 'In-app';
    }
    if (hasEnvFallback) {
      return '.env fallback';
    }
    return 'Missing';
  }

  String _maskValue(String? value) {
    if (value == null || value.isEmpty) {
      return 'Not configured';
    }

    if (value.length <= 8) {
      return value;
    }

    return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
  }

  String _formatSchedule(DateTime? value) {
    if (value == null) {
      return 'No timer scheduled';
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }

  Future<void> _testGeminiApi(UserAccount account) async {
    final apiKey = _effectiveGeminiKey(account);
    if (apiKey == null) {
      setState(() {
        _testResult = 'Gemini is not configured at runtime.';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final listUrl = Uri.parse(
        'https://generativelanguage.googleapis.com/v1/models?key=$apiKey',
      );
      final listResponse = await http.get(listUrl);

      if (listResponse.statusCode != 200) {
        setState(() {
          _testResult = 'Model lookup failed: ${listResponse.statusCode}';
        });
        return;
      }

      final data = jsonDecode(listResponse.body) as Map<String, dynamic>;
      final models =
          (data['models'] as List<dynamic>? ?? const <dynamic>[]).cast<dynamic>();
      final supportedModel = models.cast<Map<String, dynamic>>().firstWhere(
            (model) =>
                (model['supportedGenerationMethods'] as List<dynamic>? ?? const [])
                    .contains('generateContent'),
            orElse: () => <String, dynamic>{},
          );

      final modelName =
          supportedModel['name']?.toString().replaceFirst('models/', '');
      if (modelName == null || modelName.isEmpty) {
        setState(() {
          _testResult = 'No Gemini model with generateContent support was found.';
        });
        return;
      }

      final testUrl = Uri.parse(
        'https://generativelanguage.googleapis.com/v1/models/$modelName:generateContent?key=$apiKey',
      );
      final response = await http.post(
        testUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': 'Reply with just OK'}
              ]
            }
          ]
        }),
      );

      if (response.statusCode != 200) {
        setState(() {
          _testResult = 'Generation test failed: ${response.statusCode}';
        });
        return;
      }

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final text = responseData['candidates']?[0]?['content']?['parts']?[0]
              ?['text']
              ?.toString() ??
          'No text returned';

      setState(() {
        _testResult = 'Gemini runtime test passed via $modelName: $text';
      });
    } catch (error) {
      setState(() {
        _testResult = 'Gemini runtime test failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  Widget _buildSummaryTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String source,
    required String value,
    required String description,
    required Color color,
    Widget? action,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    source,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(color: Colors.grey[700], height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Text(
                value,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Info'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
          ),
        ),
        child: FutureBuilder<UserAccount>(
          future: _accountFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load EarStream debug data: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final account = snapshot.data!;
            final geminiKey = _effectiveGeminiKey(account);
            final elevenLabsKey = _effectiveElevenLabsKey(account);
            final outlookToken = _effectiveOutlookToken(account);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 3,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Runtime Summary',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildSummaryTile(
                                icon: Icons.tune,
                                label: 'Mode',
                                value: widget.currentModeLabel,
                                color: Colors.indigo,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildSummaryTile(
                                icon: Icons.sensors,
                                label: 'Sensor',
                                value: widget.sensorSourceLabel,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildSummaryTile(
                          icon: Icons.schedule,
                          label: 'Scheduled Meditation',
                          value: _formatSchedule(widget.scheduledMeditationTime),
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profile Summary',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Name: ${account.name.isEmpty ? "Missing" : account.name}',
                        ),
                        Text('Age: ${account.age}'),
                        Text('Gender: ${account.gender}'),
                        Text('Fitness: ${account.fitnessLevel}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatusCard(
                  title: 'Gemini Runtime Key',
                  source: _sourceLabel(
                    localValue: account.geminiApiKey,
                    hasEnvFallback: MeditationConfig.hasValidGeminiKey,
                  ),
                  value: _maskValue(geminiKey),
                  description:
                      'EarStream uses the in-app Gemini key first and only falls back to the bundled .env value when the in-app field is empty.',
                  color: geminiKey == null ? Colors.orange : Colors.indigo,
                  action: geminiKey == null
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isTesting
                                  ? null
                                  : () => _testGeminiApi(account),
                              icon: _isTesting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.science),
                              label: Text(
                                _isTesting
                                    ? 'Testing Gemini...'
                                    : 'Test Gemini Runtime',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            if (_testResult != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _testResult!,
                                style: TextStyle(
                                  color: _testResult!.contains('passed')
                                      ? Colors.green[700]
                                      : Colors.red[700],
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                _buildStatusCard(
                  title: 'ElevenLabs Runtime Key',
                  source: _sourceLabel(
                    localValue: account.elevenLabsApiKey,
                    hasEnvFallback: MeditationConfig.hasValidTtsKey,
                  ),
                  value: _maskValue(elevenLabsKey),
                  description:
                      'Premium voice follows the same precedence: in-app key first, then .env fallback if no local override is stored.',
                  color: elevenLabsKey == null ? Colors.orange : Colors.indigo,
                ),
                const SizedBox(height: 16),
                _buildStatusCard(
                  title: 'Outlook Runtime Token',
                  source: _sourceLabel(
                    localValue: account.microsoftGraphAccessToken,
                    hasEnvFallback:
                        MeditationConfig.hasValidMicrosoftGraphToken,
                  ),
                  value: _maskValue(outlookToken),
                  description:
                      'Meeting suppression uses the saved Outlook token first and falls back to the bundled .env token only when the in-app field is empty.',
                  color: outlookToken == null ? Colors.orange : Colors.indigo,
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Logs',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Open the shared app log viewer to inspect runtime traces, exported logs, and failures outside the EarStream UI.',
                          style: TextStyle(
                            color: Colors.grey[700],
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LogFilesScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Open Log Files'),
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
            );
          },
        ),
      ),
    );
  }
}
