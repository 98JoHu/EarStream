import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'user_account.dart';
import 'measurement.dart';
import 'meditation_session_generator.dart';
import 'hr_hrv_processor.dart' show HeartRateSample;
import 'stress_detector.dart' show StressLevel;
import 'tencent_tts_client.dart';

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
  Future<List<Source>> synthesize(String text);

  void dispose();
}

class TencentTtsProvider implements TtsProvider {
  final UserAccount account;
  final TencentTtsClient _client;

  TencentTtsProvider(this.account, {TencentTtsClient? client})
      : _client = client ?? TencentTtsClient();

  @override
  bool get isAvailable => account.hasValidTencentKey;

  @override
  Future<List<Source>> synthesize(String text) async {
    final chunks = splitTencentTtsText(text);
    final sources = <Source>[];
    for (final chunk in chunks) {
      final bytes = await _client.synthesize(
        text: chunk,
        secretId: account.tencentSecretId!,
        secretKey: account.tencentSecretKey!,
        region: account.tencentTtsRegion,
        voiceType: account.voiceGender == Gender.male ? 1050 : 1051,
        speed: _tencentSpeed(account.speakingSpeed),
      );
      sources.add(BytesSource(bytes));
    }
    return sources;
  }

  static double _tencentSpeed(SpeakingSpeed? speed) {
    return switch (speed ?? SpeakingSpeed.slow) {
      SpeakingSpeed.verySlow => -2,
      SpeakingSpeed.slow => -1,
      SpeakingSpeed.medium => 0,
      SpeakingSpeed.fast => 1,
    };
  }

  @override
  void dispose() => _client.dispose();
}

class ElevenLabsTtsProvider implements TtsProvider {
  final UserAccount account;
  ElevenLabsTtsProvider(this.account);

  @override
  bool get isAvailable => account.hasValidElevenLabsKey;

  @override
  Future<List<Source>> synthesize(String text) async {
    final voiceId = await _resolveVoiceId();
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
    return [BytesSource(res.bodyBytes)];
  }

  Future<String> _resolveVoiceId() async {
    final selected = account.elevenLabsVoiceId;
    if (selected != null && selected.isNotEmpty) return selected;

    final knownVoices = account.availableElevenLabsVoices;
    if (knownVoices != null && knownVoices.isNotEmpty) {
      return knownVoices.first.id;
    }

    final response = await http.get(
      Uri.parse('https://api.elevenlabs.io/v1/voices'),
      headers: {'xi-api-key': account.elevenLabsApiKey!},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('ElevenLabs rejected the configured credentials.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final voices = (decoded['voices'] as List)
        .map(
          (voice) => (
            voice: voice['name'] as String,
            id: voice['voice_id'] as String,
          ),
        )
        .toList();
    if (voices.isEmpty) {
      throw Exception('ElevenLabs returned no available voices.');
    }
    account.availableElevenLabsVoices = voices;
    account.elevenLabsVoiceId = voices.first.id;
    return voices.first.id;
  }

  @override
  void dispose() {}
}

class TtsService {
  final List<TtsProvider> _providers;
  final FlutterTts _fallbackTts;
  final AudioPlayer _player = AudioPlayer();
  int _playbackGeneration = 0;

  TtsService({required UserAccount userAccount})
      : _providers = [
          switch (userAccount.ttsProvider) {
            TtsProviderOption.elevenLabs => ElevenLabsTtsProvider(userAccount),
            TtsProviderOption.tencent => TencentTtsProvider(userAccount),
          },
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
    final playbackGeneration = ++_playbackGeneration;
    for (final provider in _providers) {
      if (provider.isAvailable) {
        try {
          final sources = await provider.synthesize(text);
          if (playbackGeneration != _playbackGeneration) return;
          await _player.setAudioContext(_premiumTtsAudioContext);
          for (final source in sources) {
            if (playbackGeneration != _playbackGeneration) return;
            final playbackEnded = Future.any([
              _player.onPlayerComplete.first,
              _player.onPlayerStateChanged
                  .firstWhere((state) => state == PlayerState.stopped),
            ]);
            await _player.play(source);
            await playbackEnded;
          }
          return;
        } catch (e) {
          print("Error using ${provider.runtimeType}: $e");
        }
      }
    }

    // Fallback to FlutterTts if no premium provider is available or fails
    if (playbackGeneration != _playbackGeneration) return;
    await _fallbackTts.speak(text);
  }

  Future<void> stop() async {
    _playbackGeneration++;
    await _player.stop();
    await _fallbackTts.stop();
  }

  void dispose() {
    _playbackGeneration++;
    for (final provider in _providers) {
      provider.dispose();
    }
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
