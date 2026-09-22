import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
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
import 'audio_route_diagnostics.dart';
import 'tts_service.dart';

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
  final void Function(String, Map<String, Object?>)? diagnosticEventSink;

  late final ValueNotifier<MeditationPhase> phase;
  String? failureTitle;
  String? failureMessage;

  bool isStopped = false;
  bool _isDisposed = false;
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
    this.diagnosticEventSink,
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

  Future<void> start() async {
    if (_isDisposed) return;
    isStopped = false;
    phase.value = MeditationPhase.preparing;
    failureTitle = null;
    failureMessage = null;
    _analyticsStartedAt = DateTime.now();
    _analyticsRecorded = false;

    try {
      await _run();
    } on TtsSessionException catch (error) {
      debugPrint('Meditation stopped after voice service failure: $error');
      await _fail(
        title: 'Voice service interrupted',
        message: 'The selected voice service became unavailable. The session '
            'was stopped rather than switching to a different voice. Check '
            'the network connection and try again.',
      );
    } catch (error, stackTrace) {
      debugPrint('Meditation stopped after an unexpected failure: $error');
      debugPrint('$stackTrace');
      await _fail(
        title: 'Meditation interrupted',
        message: 'The meditation could not continue. Please try again.',
      );
    }
  }

  Future<void> _run() async {
    // Start background music
    await _startBackgroundMusic();
    if (isStopped) return _endRun();

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
      if (isStopped) {
        _endRun();
        return;
      }
      debugPrint('Error generating meditation opening: $e');
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
    if (_isDisposed) return;
    isStopped = true;
    _resumeCompleter?.complete();
    _resumeCompleter = null;

    await _stopPlayback();
    _endRun();
    await _recordAnalytics(completed: false);
  }

  void pause() {
    if (_isDisposed) return;
    isPaused.value = true;
    _resumeCompleter ??= Completer<void>();
    unawaited(_pausePlayback());
  }

  void resume() {
    if (_isDisposed) return;
    isPaused.value = false;
    unawaited(
      musicPlayer.resume().catchError(
        (Object error, StackTrace stackTrace) {
          _logPlaybackError(
            'resuming background music',
            error,
            stackTrace,
          );
        },
      ),
    );
    _resumeCompleter?.complete();
    _resumeCompleter = null;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    isStopped = true;
    _resumeCompleter?.complete();
    _resumeCompleter = null;

    _endRun();
    unawaited(
      musicPlayer.dispose().catchError(
        (Object error, StackTrace stackTrace) {
          _logPlaybackError(
            'disposing background music',
            error,
            stackTrace,
          );
        },
      ),
    );
    ttsService.dispose();
    isPaused.dispose();
    phase.dispose();
    unawaited(_recordAnalytics(completed: false));
  }

  Future<void> _waitForResume() {
    _resumeCompleter ??= Completer<void>();
    return _resumeCompleter!.future;
  }

  /// Records where Android is actually sending audio. Only does anything while
  /// the biosignal trace is enabled, and never propagates a failure.
  Future<void> _recordAudioRoute(String event) async {
    final sink = diagnosticEventSink;
    if (sink == null || !AudioRouteDiagnostics.isAvailable) return;
    final route = await AudioRouteDiagnostics.describe();
    if (route.isNotEmpty) sink(event, route);
  }

  Future<void> _speakRespectingPause(String text) async {
    while (true) {
      if (isPaused.value) await _waitForResume();
      if (isStopped) return;

      diagnosticEventSink?.call('narration_requested', const {});
      await _recordAudioRoute('audio_route_at_narration');
      try {
        await ttsService.speak(text);
        diagnosticEventSink?.call('narration_finished', const {});
      } catch (error) {
        diagnosticEventSink?.call('narration_failed', {
          'error_type': error.runtimeType.toString(),
        });
        rethrow;
      }
      if (!isPaused.value) return;
    }
  }

  Future<void> _startBackgroundMusic() async {
    // A debug-only A/B test for earbud audio/PPG transport contention. The
    // production meditation always retains its background music.
    if (kDebugMode &&
        const bool.fromEnvironment('MEDITATION_SKIP_BACKGROUND_MUSIC')) {
      diagnosticEventSink?.call('audio_skipped_for_diagnostics', const {});
      return;
    }
    diagnosticEventSink?.call('audio_start_requested', const {});
    try {
      musicPlayer.audioCache = AudioCache(
        prefix: OverallMeditationConfig.audioAssetPrefix,
      );
      await musicPlayer.setReleaseMode(ReleaseMode.loop);
      await musicPlayer
          .setVolume(OverallMeditationConfig.backgroundMusicVolume);
      await musicPlayer.play(
        AssetSource(
          userAccount.meditationEnvironment?.assetPath ??
              MeditationEnvironment.nature.assetPath,
        ),
      );
      diagnosticEventSink?.call('audio_started', const {});
      await _recordAudioRoute('audio_route_at_audio_start');
      // The collapse lands 7-8 seconds after this point in the sessions that
      // degrade, and never in the ones that do not. Sampling on both sides of
      // that window is what separates "the route changed" from "the route was
      // always the earbud and something else gave way".
      unawaited(
        Future<void>.delayed(const Duration(seconds: 12), () async {
          if (_isDisposed || isStopped) return;
          await _recordAudioRoute('audio_route_after_settling');
        }),
      );
    } catch (error) {
      diagnosticEventSink?.call('audio_start_failed', {
        'error_type': error.runtimeType.toString(),
      });
      rethrow;
    }
  }

  Future<void> _runSegments(MeditationSegment first) async {
    MeditationSegment? segment = first;
    while (segment != null && !isStopped) {
      final current = segment;
      final segmentStart = DateTime.now();
      final segmentDuration = Duration(seconds: current.durationSeconds);
      var pausedDuration = Duration.zero;
      var speaking = true;

      final speakFuture = _speakRespectingPause(current.instruction);
      // Observe completion without creating an unhandled derived Future when
      // speech fails. The original Future is still awaited below so its error
      // follows the meditation's normal failure path.
      unawaited(
        speakFuture.then<void>(
          (_) => speaking = false,
          onError: (Object _, StackTrace __) => speaking = false,
        ),
      );

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
    final script = _script;
    _script = null;
    script?.dispose();
  }

  Future<void> _fail({
    required String title,
    required String message,
  }) async {
    isStopped = true;
    if (!_isDisposed) {
      failureTitle = title;
      failureMessage = message;
      phase.value = MeditationPhase.failed;
    }
    await _stopPlayback();
    _endRun();
    await _recordAnalytics(completed: false);
  }

  Future<void> _pausePlayback() async {
    try {
      await musicPlayer.pause();
    } catch (error, stackTrace) {
      _logPlaybackError('pausing background music', error, stackTrace);
    }
    try {
      await ttsService.stop();
    } catch (error, stackTrace) {
      _logPlaybackError('pausing narration', error, stackTrace);
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await musicPlayer.stop();
    } catch (error, stackTrace) {
      _logPlaybackError('stopping background music', error, stackTrace);
    }
    try {
      await ttsService.stop();
    } catch (error, stackTrace) {
      _logPlaybackError('stopping narration', error, stackTrace);
    }
  }

  static void _logPlaybackError(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('Error $operation: $error');
    debugPrint('$stackTrace');
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

class BiometricMeditation extends Meditation {
  final Measurement measurement;

  BiometricMeditation({
    required super.userAccount,
    super.maxSegments = BioAdaptiveModeConfig.meditationSegmentCount,
    super.meditationSegmentDuration,
    super.promptPolicy,
    super.analyticsStore,
    super.analyticsMode,
    super.diagnosticEventSink,
    required this.measurement,
  });

  @override
  bool checkEarlyExit() => measurement.hasHeartRateRecoveredToBaseline;

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

  /// A delayed timer tick must not permanently miss a meditation just because
  /// it did not run during the exact scheduled minute.
  bool isDue([DateTime? now]) => isScheduledTimeDue(
        scheduledTime: scheduledTime,
        now: now ?? DateTime.now(),
      );

  static bool isScheduledTimeDue({
    required DateTime scheduledTime,
    required DateTime now,
  }) =>
      !now.isBefore(scheduledTime);
}
