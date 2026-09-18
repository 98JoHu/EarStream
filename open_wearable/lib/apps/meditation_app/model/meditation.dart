import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import '../configs/bio_adaptive_mode_config.dart';
import '../configs/overall_config.dart';
import '../configs/timed_mode_config.dart';
import 'user_account.dart';
import 'measurement.dart';
import 'meditation_session_generator.dart';
import 'meditation_prompt_policy.dart';
import 'meditation_analytics.dart';
import 'hr_hrv_processor.dart' show HeartRateSample;
import 'stress_detector.dart' show StressLevel;
import 'tencent_tts_client.dart';
import 'elevenlabs_api.dart';

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
  failed,
  finished,
}

class Meditation {
  final UserAccount userAccount;
  final AudioPlayer musicPlayer = AudioPlayer();
  late final TtsService ttsService;
  final int maxSegments;
  Duration? meditationSegmentDuration;
  final MeditationPromptPolicy promptPolicy;
  final MeditationAnalyticsStore? analyticsStore;
  final MeditationAnalyticsMode? analyticsMode;

  final ValueNotifier<SessionProgress?> progress =
      ValueNotifier<SessionProgress?>(null);
  late final ValueNotifier<MeditationPhase> phase;
  final ValueNotifier<String?> failureMessage = ValueNotifier<String?>(null);

  bool isStopped = false;
  final ValueNotifier<bool> isPaused = ValueNotifier<bool>(false);
  Completer<void>? _resumeCompleter;

  MeditationScript? _script;
  DateTime? _analyticsStartedAt;
  bool _analyticsRecorded = false;

  Meditation({
    required this.userAccount,
    this.maxSegments = OverallMeditationConfig.defaultSegmentCount,
    this.meditationSegmentDuration,
    this.promptPolicy = MeditationPromptPolicy.standard,
    this.analyticsStore,
    this.analyticsMode,
  }) : assert(
          (analyticsStore == null) == (analyticsMode == null),
          'Analytics store and mode must either both be set or both be null.',
        ) {
    phase = ValueNotifier<MeditationPhase>(MeditationPhase.preparing);
    ttsService = TtsService(userAccount: userAccount);
  }

  // This method can be overridden in subclasses to implement early exit conditions.
  bool checkEarlyExit() => false;

  HeartRateSample? readCurrentBiometrics() => null;

  void initializeAudioPlayers() async {
    // Initialize the music player
    await musicPlayer.setReleaseMode(ReleaseMode.loop);
    await musicPlayer.setVolume(OverallMeditationConfig.backgroundMusicVolume);
  }

  Future<void> start() async {
    isStopped = false;
    failureMessage.value = null;
    _analyticsStartedAt = DateTime.now();
    _analyticsRecorded = false;

    try {
      await _run();
    } on TtsSessionException catch (error) {
      print('Meditation stopped after voice service failure: $error');
      isStopped = true;
      progress.value = null;
      failureMessage.value =
          'The selected voice service became unavailable. The session was '
          'stopped rather than switching to a different voice. Check the '
          'network connection and try again.';
      phase.value = MeditationPhase.failed;
      await musicPlayer.stop();
      await ttsService.stop();
      _endRun();
      await _recordAnalytics(completed: false);
    } catch (_) {
      _endRun();
      await _recordAnalytics(completed: false);
      rethrow;
    }
  }

  Future<void> _run() async {
    // Start background music
    await _startBackgroundMusic();

    // build meditation script
    _script = createMeditationScript(
      account: userAccount,
      maxSegments: maxSegments,
      segmentDuration: meditationSegmentDuration,
      promptPolicy: promptPolicy,
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
    await _recordAnalytics(completed: true);
  }

  Future<void> stop() async {
    isStopped = true;
    progress.value = null;
    _resumeCompleter?.complete();
    _resumeCompleter = null;

    await musicPlayer.stop();
    await ttsService.stop();
    await _recordAnalytics(completed: false);
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
    failureMessage.dispose();
    unawaited(_recordAnalytics(completed: false));
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
    musicPlayer.audioCache = AudioCache(
      prefix: OverallMeditationConfig.audioAssetPrefix,
    );
    await musicPlayer.setReleaseMode(ReleaseMode.loop);
    await musicPlayer.setVolume(OverallMeditationConfig.backgroundMusicVolume);
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

        await Future.delayed(
          OverallMeditationConfig.progressUpdateInterval,
        );
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

  Future<void> _recordAnalytics({required bool completed}) {
    final store = analyticsStore;
    final mode = analyticsMode;
    final startedAt = _analyticsStartedAt;
    if (store == null ||
        mode == null ||
        startedAt == null ||
        _analyticsRecorded) {
      return Future.value();
    }

    _analyticsRecorded = true;
    return store.recordSession(
      MeditationSessionRecord(
        mode: mode,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        completed: completed,
      ),
    );
  }
}

abstract interface class TtsProvider {
  bool get isAvailable;
  Future<List<Source>> synthesize(String text);

  void dispose();
}

class TencentTtsProvider implements TtsProvider {
  final String? _secretId;
  final String? _secretKey;
  final bool _isAvailable;
  final TencentTtsRegion _region;
  final int _voiceType;
  final double _speed;
  final TencentTtsClient _client;

  TencentTtsProvider(UserAccount account, {TencentTtsClient? client})
      : _secretId = account.tencentSecretId,
        _secretKey = account.tencentSecretKey,
        _isAvailable = account.hasValidTencentKey,
        _region = account.tencentTtsRegion,
        _voiceType = account.voiceGender == Gender.male
            ? OverallMeditationConfig.tencentPremiumMaleVoiceType
            : OverallMeditationConfig.tencentPremiumFemaleVoiceType,
        _speed = _tencentSpeed(account.speakingSpeed),
        _client = client ?? TencentTtsClient();

  @override
  bool get isAvailable =>
      _isAvailable &&
      _secretId?.trim().isNotEmpty == true &&
      _secretKey?.trim().isNotEmpty == true;

  @override
  Future<List<Source>> synthesize(String text) async {
    final chunks = splitTencentTtsText(text);
    final sources = <Source>[];
    for (final chunk in chunks) {
      final bytes = await _client.synthesize(
        text: chunk,
        secretId: _secretId!,
        secretKey: _secretKey!,
        region: _region,
        voiceType: _voiceType,
        speed: _speed,
      );
      sources.add(BytesSource(bytes, mimeType: 'audio/mpeg'));
    }
    return sources;
  }

  static double _tencentSpeed(SpeakingSpeed? speed) {
    return switch (speed ?? SpeakingSpeed.slow) {
      SpeakingSpeed.verySlow =>
        OverallMeditationConfig.tencentVerySlowSpeechRate,
      SpeakingSpeed.slow => OverallMeditationConfig.tencentSlowSpeechRate,
      SpeakingSpeed.medium => OverallMeditationConfig.tencentMediumSpeechRate,
      SpeakingSpeed.fast => OverallMeditationConfig.tencentFastSpeechRate,
    };
  }

  @override
  void dispose() => _client.dispose();
}

class ElevenLabsTtsProvider implements TtsProvider {
  static const maleVoiceId = OverallMeditationConfig.elevenLabsMaleVoiceId;
  static const femaleVoiceId = OverallMeditationConfig.elevenLabsFemaleVoiceId;

  final String? _apiKey;
  final bool _isAvailable;
  final String voiceId;

  ElevenLabsTtsProvider(UserAccount account)
      : _apiKey = account.elevenLabsApiKey,
        _isAvailable = account.hasValidElevenLabsKey,
        voiceId = resolveVoiceId(account);

  static String resolveVoiceId(UserAccount account) {
    final selected = account.elevenLabsVoiceId?.trim();
    if (selected?.isNotEmpty == true) return selected!;
    return account.voiceGender == Gender.male ? maleVoiceId : femaleVoiceId;
  }

  @override
  bool get isAvailable => _isAvailable && _apiKey?.trim().isNotEmpty == true;

  @override
  Future<List<Source>> synthesize(String text) async {
    final endpoint = Uri.parse(
      '${OverallMeditationConfig.elevenLabsApiBaseUrl}'
      '/v1/text-to-speech/$voiceId',
    );
    final res = await http
        .post(
          endpoint,
          headers: {
            'xi-api-key': _apiKey!,
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
          body: jsonEncode({
            'text': text,
            'model_id': OverallMeditationConfig.elevenLabsModel,
          }),
        )
        .timeout(OverallMeditationConfig.elevenLabsRequestTimeout);
    if (res.statusCode != 200) {
      throw ElevenLabsApiException.fromResponse(res);
    }
    return [BytesSource(res.bodyBytes, mimeType: 'audio/mpeg')];
  }

  @override
  void dispose() {}
}

class TtsSessionException implements Exception {
  final String providerName;
  final Object cause;

  const TtsSessionException({
    required this.providerName,
    required this.cause,
  });

  @override
  String toString() => '$providerName failed after retries: $cause';
}

class TtsService {
  final TtsProvider _provider;
  final FlutterTts _fallbackTts;
  final AudioPlayer _player = AudioPlayer();
  late final bool _usesDeviceFallback;
  int _playbackGeneration = 0;

  TtsService({required UserAccount userAccount})
      : _provider = switch (userAccount.ttsProvider) {
          TtsProviderOption.elevenLabs => ElevenLabsTtsProvider(userAccount),
          TtsProviderOption.tencent => TencentTtsProvider(userAccount),
        },
        _fallbackTts = FlutterTts() {
    // The route is selected once for the whole meditation. If a configured
    // cloud provider succeeds initially and later loses connectivity, the
    // session must not silently change to an unrelated device voice.
    _usesDeviceFallback = !_provider.isAvailable;
    _initializeFallbackTts(userAccount);
  }

  // Picked from this device's `getVoices()` output (Android's Google TTS
  // engine doesn't expose a gender field, unlike iOS/macOS/Windows) — swap
  // these if either doesn't actually sound right.
  static const _femaleVoice = OverallMeditationConfig.fallbackFemaleVoice;
  static const _maleVoice = OverallMeditationConfig.fallbackMaleVoice;

  void _initializeFallbackTts(UserAccount userAccount) async {
    await _fallbackTts.awaitSpeakCompletion(true);
    await _fallbackTts.setLanguage(OverallMeditationConfig.fallbackLanguage);
    await _fallbackTts.setSpeechRate(
      userAccount.speakingSpeed?.speed ??
          OverallMeditationConfig.fallbackSpeechRate,
    );
    await _fallbackTts.setVolume(OverallMeditationConfig.fallbackVolume);

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
    if (_usesDeviceFallback) {
      await _fallbackTts.speak(text);
      return;
    }

    Object? lastError;
    const retryDelays = OverallMeditationConfig.cloudTtsRetryDelays;
    for (var attempt = 0; attempt < retryDelays.length; attempt++) {
      if (playbackGeneration != _playbackGeneration) return;
      final delay = retryDelays[attempt];
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (playbackGeneration != _playbackGeneration) return;

      try {
        await _speakWithProvider(text, playbackGeneration);
        return;
      } catch (error) {
        lastError = error;
        print(
          'Error using ${_provider.runtimeType} '
          '(attempt ${attempt + 1}/${retryDelays.length}): $error',
        );
        await _player.stop();
      }
    }

    throw TtsSessionException(
      providerName: _provider.runtimeType.toString(),
      cause: lastError ?? StateError('Unknown voice service error'),
    );
  }

  Future<void> _speakWithProvider(
    String text,
    int playbackGeneration,
  ) async {
    final sources = await _provider.synthesize(text);
    if (sources.isEmpty) {
      throw StateError('The voice service returned no audio.');
    }
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
      if (playbackGeneration != _playbackGeneration) return;
    }
  }

  Future<void> stop() async {
    _playbackGeneration++;
    await _player.stop();
    await _fallbackTts.stop();
  }

  void dispose() {
    _playbackGeneration++;
    _provider.dispose();
    _player.dispose();
    _fallbackTts.stop();
  }
}

class BiometricMeditation extends Meditation {
  final Measurement measurement;

  BiometricMeditation({
    required super.userAccount,
    super.maxSegments = BioAdaptiveModeConfig.meditationSegmentCount,
    super.meditationSegmentDuration,
    super.promptPolicy,
    super.analyticsStore,
    super.analyticsMode,
    required this.measurement,
  });

  @override
  bool checkEarlyExit() =>
      measurement.currentStressLevel == StressLevel.relaxed;

  @override
  HeartRateSample? readCurrentBiometrics() =>
      promptPolicy.includePhysiologicalInformation
          ? measurement.latestBiometrics
          : null;
}

class ScheduledMeditation extends Meditation {
  static const segmentCount = TimedModeConfig.segmentCount;

  final DateTime scheduledTime;

  ScheduledMeditation({
    required super.userAccount,
    required this.scheduledTime,
    required MeditationAnalyticsStore analyticsStore,
  }) : super(
          maxSegments: segmentCount,
          meditationSegmentDuration: TimedModeConfig.segmentDurationOverride,
          analyticsStore: analyticsStore,
          analyticsMode: MeditationAnalyticsMode.timed,
        );

  bool isDue() {
    final now = DateTime.now();
    return now.year == scheduledTime.year &&
        now.month == scheduledTime.month &&
        now.day == scheduledTime.day &&
        now.hour == scheduledTime.hour &&
        now.minute == scheduledTime.minute;
  }
}
