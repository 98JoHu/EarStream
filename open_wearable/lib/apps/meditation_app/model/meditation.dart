import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'user_account.dart';
import 'measurement.dart';

final String welcomeMessage =
    "Welcome. I'm here to guide you through a calming meditation. Let's begin together.";
final String completionMessage =
    "Wonderful work. You have taken a meaningful step towards calm. Carry this peace with you.";
final defaultSegmentMessage =
    '''Take a deep breath in...  hold gently for a moment... and slowly release. Feel the tension melting away with each exhale. Your body is becoming more relaxed... your mind more peaceful. Continue breathing naturally... finding your center... allowing calmness to flow through you.''';

class SessionProgress {
  final int currentSegment;
  final int totalSegments;
  final Duration segmentElapsed;

  const SessionProgress({
    required this.currentSegment,
    required this.totalSegments,
    required this.segmentElapsed,
  });
}

class Meditation {
  final UserAccount userAccount;
  final AudioPlayer musicPlayer = AudioPlayer();
  final FlutterTts voicePlayer = FlutterTts();

  final ValueNotifier<SessionProgress?> progress =
      ValueNotifier<SessionProgress?>(null);

  bool isStopped = false;
  bool isPaused = false;
  Completer<void>? _resumeCompleter;

  Meditation({required this.userAccount}) {
    initializeAudioPlayers();
  }

  // This method can be overridden in subclasses to implement early exit conditions.
  bool checkEarlyExit() => false;

  void initializeAudioPlayers() async {
    // Initialize the music player
    await musicPlayer.setReleaseMode(ReleaseMode.loop);
    await musicPlayer.setVolume(0.3);

    // Initialize the voice player
    await voicePlayer.awaitSpeakCompletion(true);
    await voicePlayer.setLanguage("en-US");
    await voicePlayer.setSpeechRate(0.4);
    await voicePlayer.setVolume(1.0);
  }

  // Generate default instructions for fallback meditation
  ({
    String welcomeMessage,
    String completionMessage,
    List<MeditationSegment> segments
  }) _loadFallbackSession() {
    return (
      welcomeMessage: welcomeMessage,
      completionMessage: completionMessage,
      segments: List.generate(
        10,
        (index) => MeditationSegment(
          segmentId: index + 1,
          instruction: defaultSegmentMessage,
          durationSeconds: 30,
          targetBreathsPerMinute: 6,
        ),
      ),
    );
  }

  Future<void> start() async {
    isStopped = false;

    // Start background music
    musicPlayer.audioCache =
        AudioCache(prefix: "lib/apps/meditation_app/assets/audio/");
    await musicPlayer.play(
      AssetSource(
        userAccount.meditationEnvironment?.assetPath ??
            MeditationEnvironment.nature.assetPath,
      ),
    );

    final session = _loadFallbackSession();
    var welcomeMessage = session.welcomeMessage;
    var completionMessage = session.completionMessage;
    var segments = session.segments;

    if (userAccount.hasValidDeepseekKey) {
      try {
        final sessionData =
            await generateMeditationSession(userAccount: userAccount);
        welcomeMessage = sessionData['welcomeMessage'] as String;
        completionMessage = sessionData['completionMessage'] as String;
        segments = (sessionData['segments'] as List)
            .map((segment) => MeditationSegment.fromJson(segment))
            .toList();
      } catch (e) {
        print("Error generating meditation session: $e");
      }
    }

    // Speak the welcome message
    if (!isStopped) {
      await _speakRespectingPause(welcomeMessage);
    }

    // Start the meditation segments
    int index = 0;
    for (final segment in segments) {
      // if the meditation has been stopped, break out of the loop
      if (isStopped) break;

      index++;
      final segmentStart = DateTime.now();
      var pausedDuration = Duration.zero;
      var speaking = true;

      final speakFuture = _speakRespectingPause(segment.instruction);
      speakFuture.whenComplete(() => speaking = false);

      while (speaking) {
        if (isPaused) {
          final pauseStart = DateTime.now();
          await _waitForResume();
          pausedDuration += DateTime.now().difference(pauseStart);
        }
        if (isStopped) break;

        final elapsed =
            DateTime.now().difference(segmentStart) - pausedDuration;

        progress.value = SessionProgress(
          currentSegment: index,
          totalSegments: segments.length,
          segmentElapsed: elapsed,
        );

        await Future.delayed(const Duration(seconds: 1));
      }

      await speakFuture; // Ensure the segment instruction has finished speaking

      if (isStopped) break;
      if (checkEarlyExit()) break;
    }

    // Speak the completion message
    if (!isStopped) {
      await _speakRespectingPause(completionMessage);
    }
  }

  Future<void> stop() async {
    isStopped = true;
    progress.value = null;
    _resumeCompleter?.complete();
    _resumeCompleter = null;

    await musicPlayer.stop();
    await voicePlayer.stop();
  }

  Future<void> _waitForResume() {
    _resumeCompleter ??= Completer<void>();
    return _resumeCompleter!.future;
  }

  // Speaks [text], but if pause() cuts it off mid-utterance, waits for
  // resume() and re-speaks from the start once the user comes back.
  Future<void> _speakRespectingPause(String text) async {
    while (true) {
      if (isPaused) await _waitForResume();
      if (isStopped) return;

      await voicePlayer.speak(text);
      if (!isPaused) return;
    }
  }

  void pause() {
    isPaused = true;
    _resumeCompleter ??= Completer<void>();
    musicPlayer.pause();
    voicePlayer.stop(); // flutter_tts can't reliably resume mid-utterance
  }

  void resume() {
    isPaused = false;
    musicPlayer.resume();
    _resumeCompleter?.complete();
    _resumeCompleter = null;
  }

  void dispose() {
    musicPlayer.dispose();
    voicePlayer.stop();
  }
}

class MeditationSegment {
  final int segmentId;
  final String instruction;
  final int durationSeconds;
  final int targetBreathsPerMinute;

  MeditationSegment({
    required this.segmentId,
    required this.instruction,
    required this.durationSeconds,
    required this.targetBreathsPerMinute,
  });

  factory MeditationSegment.fromJson(Map<String, dynamic> json) {
    return MeditationSegment(
      segmentId: json['segmentId'] as int,
      instruction: json['instruction'] as String,
      durationSeconds: json['durationSeconds'] as int,
      targetBreathsPerMinute: json['targetBreathsPerMinute'] as int,
    );
  }
}

class BiometricMeditation extends Meditation {
  final Measurement measurement;

  BiometricMeditation({required super.userAccount, required this.measurement});

  @override
  bool checkEarlyExit() =>
      measurement.checkStressLevel() == StressLevel.relaxed;
}

class ScheduledMeditation extends Meditation {
  final DateTime scheduledTime;

  ScheduledMeditation({
    required super.userAccount,
    required this.scheduledTime,
  });

  bool isDue() {
    final now = DateTime.now();
    return now.year == scheduledTime.year &&
        now.month == scheduledTime.month &&
        now.day == scheduledTime.day &&
        now.hour == scheduledTime.hour &&
        now.minute == scheduledTime.minute;
  }
}

Future<Map<String, dynamic>> generateMeditationSession({
  required UserAccount userAccount,
  int maxSegments = 10,
}) async {
  final url = Uri.parse('https://api.deepseek.com/chat/completions');
  final meditationType = userAccount.meditationType ?? 'mindfulness';
  final userContext = userAccount.getContextSummary();
  final systemPrompt = '''
      You are a highly empathetic, warm, and professional meditation guide with a naturally calming voice.
      Your purpose is to lead personalized, adaptive meditations based on real-time biosignals (heart rate and HRV).

      $userContext

      MEDITATION TYPE: $meditationType
      You are guiding a $meditationType meditation session. Stay true to this meditation type throughout all segments.

      CRITICAL GUIDELINES:
      1. ALWAYS include specific breathing instructions in every segment:
        - "Breathe in slowly for 4 counts... and breathe out for 6 counts"
        - "Let's take a deep breath together... in through your nose... out through your mouth"
        - "Notice your breath... inhale deeply... exhale completely..."

      2. Make it PERSONAL:
        - Use their name naturally (not every sentence, but occasionally)
        - Reference their specific stress triggers if mentioned
        - Use their meditation environment imagery
        - Adapt to their age and fitness level
        - Consider their gender when choosing imagery/language

      3. This is a MULTI-SEGMENT meditation:
        - Create natural transitions, not endings
        - Build on previous themes and progressions
        - End with gentle pauses that invite continuation
        - DO NOT say "the meditation is now over" unless explicitly asked

      4. MEDITATION TYPE determines your approach:
        - For 'breathing' or 'breath_focus': Focus heavily on breath awareness, breath counting (if appropriate), pranayama techniques
        - For 'body_scan' or 'progressive_relaxation': Systematically guide attention through body parts, progressive relaxation
        - For 'visualization': Create vivid imagery, sensory immersion
        - For 'mindfulness': Emphasize present-moment awareness, observation without judgment, acceptance

      5. VOICE QUALITY matters:
        - Speak slowly and clearly
        - Use soothing, descriptive language
        - Create natural pauses with ellipses (...)
        - Guide the breathing rhythm with your pacing

      6. OUTPUT FORMAT:
        - You MUST output valid JSON only
        - No markdown, no meta-comments
        - Just the spoken meditation words
        - Approximately 50 words per segment

      Expected JSON Output Structure:
      {
        "welcomeMessage": "string",
        "segments": [
          {
            "segmentId": 1,
            "instruction": "string",
            "durationSeconds": 60,
            "targetBreathsPerMinute": 6
          },
          ...
        ],
        "completionMessage": "string"
      }

      Remember: You're creating a calming, safe space for someone who may be stressed. Be warm, patient, and genuinely caring.''';
  final userPrompt = '''
      Generate a meditation session with $maxSegments segments. Each segment should be approximately 50 words, include specific breathing instructions, and be tailored to the user's profile and preferences. Ensure smooth transitions between segments and a gentle completion message. Output the result in valid JSON format as specified.''';

  try {
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer ${userAccount.deepseekApiKey!}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'deepseek-v4-pro',
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'max_tokens': 1000,
        'temperature': 0.7,
      }),
    );
    print(systemPrompt);
    print(userPrompt);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final jsonContent = decoded['choices'][0]['message']['content'];
      print("Deepseek API response: $jsonContent");
      return jsonDecode(jsonContent) as Map<String, dynamic>;
    } else {
      throw Exception(
          'Failed to generate meditation session: ${response.statusCode}');
    }
  } catch (e) {
    print("Error generating meditation session: $e");
    rethrow;
  }
}
