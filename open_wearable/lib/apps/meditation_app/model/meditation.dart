import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'user_account.dart';
import 'measurement.dart';
import 'meditation_session_generator.dart';

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

  MeditationScript? _script;

  Meditation({
    required this.userAccount,
    this.maxSegments = 10,
    this.meditationSegmentDuration,
  }) {
    phase = ValueNotifier<MeditationPhase>(MeditationPhase.preparing);
    ttsService = TtsService(userAccount: userAccount);
  }

  // This method can be overridden in subclasses to implement early exit conditions.
  bool checkEarlyExit() => false;

  HeartRateSample? readCurrentBiometrics() => null;

  void initializeAudioPlayers() async {
    // Initialize the music player
    await musicPlayer.setReleaseMode(ReleaseMode.loop);
    await musicPlayer.setVolume(0.3);
  }

  Future<void> start() async {
    isStopped = false;
    // Start background music
    await _startBackgroundMusic();

    // build meditation script
    _script = createMeditationScript(
      account: userAccount,
      maxSegments: maxSegments,
      segmentDuration: meditationSegmentDuration,
    );

    MeditationFrame opening;
    try {
      opening = await _script!.begin();
    } catch (e) {
      print("Error generating meditation opening: $e");
      _script!.dispose();
      _script = StaticMeditationScript.fallback(
        segmentCount: maxSegments,
        segmentDuration: meditationSegmentDuration,
      );
      opening = await _script!.begin();
    }

    if (isStopped) return _endRun();

    // Speak the welcome message
    phase.value = MeditationPhase.welcome;
    await _speakRespectingPause(opening.welcomeMessage);

    // Run through the meditation segments
    phase.value = MeditationPhase.segment;
    await _runSegments(opening.firstSegment);

    // Speak the completion message
    if (isStopped) return _endRun();
    phase.value = MeditationPhase.completion;
    await _speakRespectingPause(opening.completionMessage);

    // Mark the meditation as finished
    phase.value = MeditationPhase.finished;
    _endRun();
  }

  Future<void> stop() async {
    isStopped = true;
    progress.value = null;
    _resumeCompleter?.complete();
    _resumeCompleter = null;

    await musicPlayer.stop();
    await ttsService.stop();
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
    isStopped = true;
    _resumeCompleter?.complete();
    _resumeCompleter = null;

    musicPlayer.dispose();
    ttsService.dispose();
    isPaused.dispose();
  }

  Future<void> _waitForResume() {
    _resumeCompleter ??= Completer<void>();
    return _resumeCompleter!.future;
  }

  Future<void> _speakRespectingPause(String text) async {
    while (true) {
      if (isPaused.value) await _waitForResume();
      if (isStopped) return;

      await ttsService.speak(text);
      if (!isPaused.value) return;
    }
  }

  Future<void> _startBackgroundMusic() async {
    musicPlayer.audioCache =
        AudioCache(prefix: "lib/apps/meditation_app/assets/audio/");
    await musicPlayer.setReleaseMode(ReleaseMode.loop);
    await musicPlayer.setVolume(0.3);
    await musicPlayer.play(
      AssetSource(
        userAccount.meditationEnvironment?.assetPath ??
            MeditationEnvironment.nature.assetPath,
      ),
    );
  }

  Future<void> _runSegments(MeditationSegment first) async {
    MeditationSegment? segment = first;
    int index = 0;

    while (segment != null && !isStopped) {
      index++;
      final current = segment;
      final segmentStart = DateTime.now();
      final segmentDuration = Duration(seconds: current.durationSeconds);
      var pausedDuration = Duration.zero;
      var speaking = true;

      final speakFuture = _speakRespectingPause(current.instruction);
      speakFuture.whenComplete(() => speaking = false);

      // Prefetch of the next segment, started when speaking finishes.
      Future<MeditationSegment?>? nextFuture;

      while (true) {
        if (isPaused.value) {
          final pauseStart = DateTime.now();
          await _waitForResume();
          pausedDuration += DateTime.now().difference(pauseStart);
        }
        if (isStopped) break;

        // The instruction just finished: sample biometrics now and begin
        // generating the next segment during the remaining breathing pause.
        if (!speaking && nextFuture == null) {
          nextFuture = _script!.nextSegment(readCurrentBiometrics());
        }

        final elapsed =
            DateTime.now().difference(segmentStart) - pausedDuration;
        if (!speaking && elapsed >= segmentDuration) break;

        progress.value = SessionProgress(
          currentSegment: index,
          totalSegments: maxSegments,
          segmentElapsed: elapsed,
        );

        await Future.delayed(const Duration(seconds: 1));
      }

      await speakFuture; // ensure the instruction has finished speaking

      if (isStopped) break;
      if (checkEarlyExit()) break;

      // The prefetch usually completed during the pause; await whatever's left.
      // (If we broke before speaking ended, nextFuture may be null.)
      segment =
          await (nextFuture ?? _script!.nextSegment(readCurrentBiometrics()));
    }
  }

  void _endRun() {
    _script?.dispose();
    _script = null;
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
          await _player.onPlayerComplete.first;
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

  @override
  HeartRateSample? readCurrentBiometrics() => measurement.latestBiometrics;
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
