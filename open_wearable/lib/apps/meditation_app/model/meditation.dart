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

enum MeditationPhase {
  preparing,
  welcome,
  segment,
  completion,
  finished,
}

class Meditation {
  final UserAccount userAccount;
  final AudioPlayer musicPlayer = AudioPlayer();
  late final TtsService ttsService;
  final int maxSegments;
  Duration? meditationSegmentDuration;

  final ValueNotifier<SessionProgress?> progress =
      ValueNotifier<SessionProgress?>(null);
  late final ValueNotifier<MeditationPhase> phase;

  bool isStopped = false;
  final ValueNotifier<bool> isPaused = ValueNotifier<bool>(false);
  Completer<void>? _resumeCompleter;

  Meditation({
    required this.userAccount,
    this.maxSegments = 10,
    this.meditationSegmentDuration,
  }) {
    phase = ValueNotifier<MeditationPhase>(MeditationPhase.preparing);
    ttsService = TtsService(userAccount: userAccount);
    initializeAudioPlayers();
  }

  // This method can be overridden in subclasses to implement early exit conditions.
  bool checkEarlyExit() => false;

  void initializeAudioPlayers() async {
    // Initialize the music player
    await musicPlayer.setReleaseMode(ReleaseMode.loop);
    await musicPlayer.setVolume(0.3);
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
        maxSegments,
        (index) => MeditationSegment(
          segmentId: index + 1,
          instruction: defaultSegmentMessage,
          durationSeconds: meditationSegmentDuration?.inSeconds ?? 30,
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
        final sessionData = await generateMeditationSession(
          userAccount: userAccount,
          maxSegments: maxSegments,
          meditationSegmentDuration: meditationSegmentDuration,
        );
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
      phase.value = MeditationPhase.welcome;
      await _speakRespectingPause(welcomeMessage);
    }

    phase.value = MeditationPhase.segment;
    // Start the meditation segments
    int index = 0;
    for (final segment in segments) {
      // if the meditation has been stopped, break out of the loop
      if (isStopped) break;

      index++;
      final segmentStart = DateTime.now();
      final segmentDuration = Duration(seconds: segment.durationSeconds);
      var pausedDuration = Duration.zero;
      var speaking = true;

      final speakFuture = _speakRespectingPause(segment.instruction);
      speakFuture.whenComplete(() => speaking = false);

      while (true) {
        if (isPaused.value) {
          final pauseStart = DateTime.now();
          await _waitForResume();
          pausedDuration += DateTime.now().difference(pauseStart);
        }
        if (isStopped) break;

        final elapsed =
            DateTime.now().difference(segmentStart) - pausedDuration;

        if (!speaking && elapsed >= segmentDuration) break;

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
      phase.value = MeditationPhase.completion;
      await _speakRespectingPause(completionMessage);
    }

    // Mark the meditation as finished
    phase.value = MeditationPhase.finished;
  }

  Future<void> stop() async {
    isStopped = true;
    progress.value = null;
    _resumeCompleter?.complete();
    _resumeCompleter = null;

    await musicPlayer.stop();
    await ttsService.stop();
  }

  Future<void> _waitForResume() {
    _resumeCompleter ??= Completer<void>();
    return _resumeCompleter!.future;
  }

  // Speaks [text], but if pause() cuts it off mid-utterance, waits for
  // resume() and re-speaks from the start once the user comes back.
  Future<void> _speakRespectingPause(String text) async {
    while (true) {
      if (isPaused.value) await _waitForResume();
      if (isStopped) return;

      await ttsService.speak(text);
      if (!isPaused.value) return;
    }
  }

  void pause() {
    isPaused.value = true;
    _resumeCompleter ??= Completer<void>();
    musicPlayer.pause();
    ttsService.stop();
  }

  void resume() {
    isPaused.value = false;
    musicPlayer.resume();
    _resumeCompleter?.complete();
    _resumeCompleter = null;
  }

  void dispose() {
    musicPlayer.dispose();
    ttsService.dispose();
    isPaused.dispose();
  }
}

abstract interface class TtsProvider {
  bool get isAvailable;
  Future<Source> synthesize(String text);
}

class DashscopeTtsProvider implements TtsProvider {
  final UserAccount account;
  DashscopeTtsProvider(this.account);

  @override
  bool get isAvailable => account.hasValidDashscopeKey;

  @override
  Future<Source> synthesize(String text) async {
    final endpoint = Uri.parse(
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',
    );
    final res = await http.post(
      endpoint,
      headers: {
        'Authorization': 'Bearer ${account.dashscopeApiKey!}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'qwen3-tts-flash',
        'input': {
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': text},
              ],
            },
          ],
        },
        'parameters': {
          'voice': 'Seren',
          'language_type': 'English',
        },
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Dashscope ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final url = decoded['output']['audio']['url'] as String;
    return UrlSource(url);
  }
}

class ElevenLabsTtsProvider implements TtsProvider {
  final UserAccount account;
  ElevenLabsTtsProvider(this.account);

  @override
  bool get isAvailable => account.hasValidElevenLabsKey;

  @override
  Future<Source> synthesize(String text) async {
    final voiceId = account.elevenLabsVoiceId ??
        account.availableElevenLabsVoices!.first.id;
    final key = account.elevenLabsApiKey!;
    final endpoint = Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/$voiceId',
    );
    final res = await http.post(
      endpoint,
      headers: {
        'xi-api-key': key,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'text': text,
        'model_id': 'eleven_flash_v2_5', // fast + cheap
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('ElevenLabs ${res.statusCode}: ${res.body}');
    }
    return BytesSource(res.bodyBytes);
  }
}

class TtsService {
  final List<TtsProvider> _providers;
  final FlutterTts _fallbackTts;
  final AudioPlayer _player = AudioPlayer();

  TtsService({required UserAccount userAccount})
      : _providers = [
          DashscopeTtsProvider(userAccount),
          ElevenLabsTtsProvider(userAccount),
        ],
        _fallbackTts = FlutterTts() {
    _initializeFallbackTts(userAccount);
  }

  // Picked from this device's `getVoices()` output (Android's Google TTS
  // engine doesn't expose a gender field, unlike iOS/macOS/Windows) — swap
  // these if either doesn't actually sound right.
  static const _femaleVoice = {'name': 'en-us-x-sfg-local', 'locale': 'en-US'};
  static const _maleVoice = {'name': 'en-us-x-iob-local', 'locale': 'en-US'};

  void _initializeFallbackTts(UserAccount userAccount) async {
    await _fallbackTts.awaitSpeakCompletion(true);
    await _fallbackTts.setLanguage("en-US");
    await _fallbackTts.setSpeechRate(userAccount.speakingSpeed?.speed ?? 0.3);
    await _fallbackTts.setVolume(0.8);

    if (userAccount.voiceGender == Gender.male) {
      await _fallbackTts.setVoice(_maleVoice);
    } else if (userAccount.voiceGender == Gender.female) {
      await _fallbackTts.setVoice(_femaleVoice);
    }
  }

  // audioplayers defaults every player to an exclusive ("gain") Android audio
  // focus request, which pauses musicPlayer the instant this player starts —
  // gainTransientMayDuck just lowers the music's volume instead, letting it
  // keep playing under the narration.
  static final _premiumTtsAudioContext = AudioContext(
    android: AudioContextAndroid(
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  Future<void> speak(String text) async {
    for (final provider in _providers) {
      if (provider.isAvailable) {
        try {
          final source = await provider.synthesize(text);
          await _player.setAudioContext(_premiumTtsAudioContext);
          await _player.play(source);
          return;
        } catch (e) {
          print("Error using ${provider.runtimeType}: $e");
        }
      }
    }

    // Fallback to FlutterTts if no premium provider is available or fails
    await _fallbackTts.speak(text);
  }

  Future<void> stop() async {
    await _player.stop();
    await _fallbackTts.stop();
  }

  void dispose() {
    _player.dispose();
    _fallbackTts.stop();
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

  BiometricMeditation({
    required super.userAccount,
    super.maxSegments = 10,
    super.meditationSegmentDuration,
    required this.measurement,
  });

  @override
  bool checkEarlyExit() =>
      measurement.currentStressLevel == StressLevel.relaxed;
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
  Duration? meditationSegmentDuration,
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
        - Approximately 280 words per segment

      Expected JSON Output Structure:
      {
        "welcomeMessage": "string",
        "segments": [
          {
            "segmentId": 1,
            "instruction": "string",
            "durationSeconds": ${meditationSegmentDuration?.inSeconds ?? 30},
            "targetBreathsPerMinute": 6
          },
          ...
        ],
        "completionMessage": "string"
      }

      Remember: You're creating a calming, safe space for someone who may be stressed. Be warm, patient, and genuinely caring.''';
  final userPrompt = '''
      Generate a meditation session with $maxSegments segments. Each segment should be approximately 280 words, include specific breathing instructions, and be tailored to the user's profile and preferences. Ensure smooth transitions between segments and a gentle completion message. Output the result in valid JSON format as specified.''';

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
        'max_tokens': 10000,
        'temperature': 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final jsonContent = decoded['choices'][0]['message']['content'];
      final session = jsonDecode(jsonContent) as Map<String, dynamic>;
      // print("Generated meditation session: ${jsonEncode(session)}");
      return session;
    } else {
      throw Exception(
        'Failed to generate meditation session: ${response.statusCode}',
      );
    }
  } catch (e) {
    print("Error generating meditation session: $e");
    rethrow;
  }
}
