import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'user_account.dart';
import 'hr_hrv_processor.dart' show HeartRateSample;

class MeditationSegment {
  final int segmentId;
  final String instruction;
  final int durationSeconds;

  const MeditationSegment({
    required this.segmentId,
    required this.instruction,
    required this.durationSeconds,
  });

  factory MeditationSegment.fromJson(Map<String, dynamic> json) {
    return MeditationSegment(
      segmentId: json['segmentId'] as int,
      instruction: json['instruction'] as String,
      durationSeconds: json['durationSeconds'] as int,
    );
  }
}

class MeditationFrame {
  final String welcomeMessage;
  final String completionMessage;
  final MeditationSegment firstSegment;

  const MeditationFrame({
    required this.welcomeMessage,
    required this.completionMessage,
    required this.firstSegment,
  });
}

abstract interface class MeditationScript {
  // Begins the meditation, returning the opening frame (welcome message, completion message, and first segment).
  Future<MeditationFrame> begin();

  /// The next segment, adapted to [current], or null when the script is done.
  /// [current] may be null for meditations with no biosignal source.
  Future<MeditationSegment?> nextSegment(HeartRateSample? current);

  void dispose();
}

/// Chooses the right script for the account: adaptive if an LLM key is present,
/// static otherwise.
MeditationScript createMeditationScript({
  required UserAccount account,
  required int maxSegments,
  Duration? segmentDuration,
}) {
  if (account.hasValidDeepseekKey) {
    return AdaptiveMeditationScript(
      account: account,
      maxSegments: maxSegments,
      segmentDuration: segmentDuration,
    );
  }
  return StaticMeditationScript.fallback(
    segmentCount: maxSegments,
    segmentDuration: segmentDuration,
  );
}

class StaticMeditationScript implements MeditationScript {
  final String _welcome;
  final String _completion;
  final List<MeditationSegment> _segments;
  int _index = 0;

  StaticMeditationScript({
    required String welcome,
    required String completion,
    required List<MeditationSegment> segments,
  })  : _welcome = welcome,
        _completion = completion,
        _segments = segments;

  factory StaticMeditationScript.fallback({
    required int segmentCount,
    Duration? segmentDuration,
  }) {
    return StaticMeditationScript(
      welcome: _Fallback.welcome,
      completion: _Fallback.completion,
      segments: List.generate(
        segmentCount,
        (i) => _Fallback.segment(i + 1, segmentDuration),
      ),
    );
  }

  @override
  Future<MeditationFrame> begin() async {
    _index = 1;
    return MeditationFrame(
      welcomeMessage: _welcome,
      completionMessage: _completion,
      firstSegment: _segments.first,
    );
  }

  @override
  Future<MeditationSegment?> nextSegment(HeartRateSample? _) async {
    if (_index >= _segments.length) return null;
    return _segments[_index++];
  }

  @override
  void dispose() {}
}

class AdaptiveMeditationScript implements MeditationScript {
  final UserAccount _account;
  final int _maxSegments;
  final Duration? _segmentDuration;
  final http.Client _client;
  final bool _ownsClient;

  final List<Map<String, String>> _history = [];
  int _emitted = 0;

  AdaptiveMeditationScript({
    required UserAccount account,
    required int maxSegments,
    Duration? segmentDuration,
    http.Client? client,
  })  : _account = account,
        _maxSegments = maxSegments,
        _segmentDuration = segmentDuration,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  static final _endpoint =
      Uri.parse('https://api.deepseek.com/chat/completions');

  int get _durationSeconds => _segmentDuration?.inSeconds ?? 30;

  @override
  Future<MeditationFrame> begin() async {
    _history.add({'role': 'user', 'content': _openingPrompt()});
    final content = await _send(); // throws on failure — caller falls back
    _history.add({'role': 'assistant', 'content': content});

    final json = jsonDecode(content) as Map<String, dynamic>;
    _emitted = 1;
    return MeditationFrame(
      welcomeMessage: json['welcomeMessage'] as String,
      completionMessage: json['completionMessage'] as String,
      firstSegment: MeditationSegment.fromJson(
        json['segment'] as Map<String, dynamic>,
      ),
    );
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  @override
  Future<MeditationSegment?> nextSegment(HeartRateSample? current) async {
    if (_emitted >= _maxSegments) return null;

    _history.add({'role': 'user', 'content': _segmentPrompt(current)});
    try {
      final content = await _send();
      _history.add({'role': 'assistant', 'content': content});
      final json = jsonDecode(content) as Map<String, dynamic>;
      _emitted++;
      return MeditationSegment.fromJson(json);
    } catch (e) {
      // Resilience: a single failed call must not end the meditation. Drop the
      // dangling user turn, emit a generic segment, and let the session go on.
      debugPrint('Adaptive segment failed, using fallback: $e');
      _history.removeLast();
      _emitted++;
      return _Fallback.segment(_emitted, _segmentDuration);
    }
  }

  /// Posts the system prompt + full history, returns the assistant's raw
  /// content string. Throws [MeditationGenerationException] on any failure.
  Future<String> _send() async {
    final key = _account.deepseekApiKey;
    if (key == null) {
      throw Exception('No DeepSeek API key.');
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'deepseek-v4-pro',
              'response_format': {'type': 'json_object'},
              'messages': [
                {'role': 'system', 'content': _systemPrompt()},
                ..._history,
              ],
              'max_tokens': 2000,
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw Exception('Network error. $e');
    }

    if (response.statusCode != 200) {
      throw Exception(
        'DeepSeek returned HTTP ${response.statusCode}.',
      );
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded['choices'][0]['message']['content'] as String;
    } catch (e) {
      throw Exception('Malformed response. $e');
    }
  }

  // --- prompt building -----------------------------------------------------

  String _systemPrompt() {
    final meditationType = _account.meditationType ?? 'mindfulness';
    final userContext = _account.getContextSummary();

    return '''
You are a highly empathetic, warm, and professional meditation guide with a naturally calming voice.
You lead a personalized, ADAPTIVE meditation that unfolds one segment at a time. After each segment I will report the user's live biosignals, and you will adapt the next segment to guide them toward calm.

$userContext

MEDITATION TYPE: $meditationType
Stay true to this meditation type throughout.

HOW TO ADAPT TO BIOSIGNALS (reported after each segment):
- Heart rate (bpm): lower is calmer. A rising or high HR means the user is still activated — slow down, lengthen exhales, soften the language.
- HRV as RMSSD (ms): HIGHER RMSSD means more relaxed (parasympathetic). LOW RMSSD means stressed — keep grounding and steady the breath before deepening.
- If the user is clearly calming, you may gently deepen the practice. If not, stay with soothing, stabilizing guidance. Never rush them.

GUIDELINES:
1. ALWAYS include specific breathing instructions in every segment (e.g. "breathe in for 4 counts... out for 6").
2. Make it PERSONAL: use their name occasionally, reference their environment imagery, adapt to their profile.
3. Create natural transitions that build on what you said before. DO NOT signal an ending in a segment.
4. Speak slowly; use soothing language and natural pauses marked with ellipses (...).
5. Approximately 280 words per segment.

OUTPUT FORMAT — valid JSON only, no markdown, no commentary.

On the FIRST turn, output:
{
  "welcomeMessage": "string",
  "completionMessage": "string",
  "segment": {
    "segmentId": 1,
    "instruction": "string",
    "durationSeconds": $_durationSeconds,
  }
}

On EVERY LATER turn, output a single segment object:
{
  "segmentId": <int>,
  "instruction": "string",
  "durationSeconds": $_durationSeconds,
}

Remember: you're creating a calming, safe space for someone who may be stressed. Be warm, patient, and genuinely caring.''';
  }

  String _openingPrompt() {
    return 'Begin the session. Generate the welcomeMessage, the '
        'completionMessage, and the first segment, in the first-turn JSON '
        'format. There are no biosignals yet.';
  }

  String _segmentPrompt(HeartRateSample? b) {
    final next = _emitted + 1;
    if (b == null) {
      return 'The user has finished segment $_emitted. No biosignals are '
          'available. Generate segment $next as a single segment JSON object, '
          'continuing the calming progression.';
    }
    final hr = b.heartRate.toStringAsFixed(0);
    final rmssd = b.rmssd?.toStringAsFixed(0);
    return 'The user has finished segment $_emitted. Their current heart rate '
        'is $hr bpm and their HRV (RMSSD) is $rmssd ms. Adapt accordingly and '
        'generate segment $next as a single segment JSON object.';
  }
}

class _Fallback {
  static const welcome =
      "Welcome. I'm here to guide you through a calming meditation. "
      "Let's begin together.";

  static const completion =
      "Wonderful work. You have taken a meaningful step towards calm. "
      "Carry this peace with you.";

  static const _segmentText =
      'Take a deep breath in... hold gently for a moment... and slowly '
      'release. Feel the tension melting away with each exhale. Your body is '
      'becoming more relaxed... your mind more peaceful. Continue breathing '
      'naturally... finding your center... allowing calmness to flow through '
      'you.';

  static MeditationSegment segment(int id, Duration? duration) {
    return MeditationSegment(
      segmentId: id,
      instruction: _segmentText,
      durationSeconds: duration?.inSeconds ?? 30,
    );
  }
}
