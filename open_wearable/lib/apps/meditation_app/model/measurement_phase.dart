import 'dart:async';

import 'package:flutter/foundation.dart';

import '../configs/bio_adaptive_mode_config.dart';
import 'biometric_source.dart';
import 'stress_detector.dart';
import 'user_account.dart';
import 'hr_hrv_processor.dart' show HeartRateSample;

class PhaseContext {
  final BiometricSource source;
  final StressDetector detector;
  final bool suppressStressDetectionDuringActivity;

  const PhaseContext({
    required this.source,
    required this.detector,
    this.suppressStressDetectionDuringActivity = true,
  });
}

sealed class MonitoringPhase {
  Duration? get duration;

  /// Timed phases may hold at 100% until the required sensor data is valid.
  bool get canAdvance => true;

  /// Called by the controller only after this phase's timer has expired.
  void atDeadline(PhaseContext ctx) {}

  StreamSubscription<HeartRateSample>? activate(
    PhaseContext ctx,
  );

  void complete(PhaseContext ctx) {}
}

class CalibrationPhase extends MonitoringPhase {
  @override
  final Duration duration;

  CalibrationPhase({
    this.duration = BioAdaptiveModeConfig.calibrationDuration,
  });

  @override
  StreamSubscription<HeartRateSample>? activate(
    PhaseContext ctx,
  ) {
    ctx.source.beginCalibration();
    return null;
  }
}

class BaselinePhase extends MonitoringPhase {
  final UserAccount userAccount;
  final bool useBestEffortAtDeadline;
  @override
  final Duration duration;

  int _heartRateCount = 0;
  double _heartRateTotal = 0;
  int _rmssdCount = 0;
  double _rmssdTotal = 0;
  BiometricSource? _source;
  HeartRateSample? _deadlineEstimate;

  BaselinePhase({
    required this.userAccount,
    Duration? duration,
    this.useBestEffortAtDeadline = false,
  }) : duration = duration ?? BioAdaptiveModeConfig.baselineDuration;

  @override
  bool get canAdvance => useBestEffortAtDeadline
      ? _deadlineEstimate?.rmssd != null
      : _heartRateCount > 0 && _rmssdCount > 0;

  @override
  void atDeadline(PhaseContext ctx) {
    if (!useBestEffortAtDeadline) return;
    // Keep asking until an estimate arrives that actually carries an RMSSD.
    // The source may return a heart-rate-only sample as its last resort, and
    // caching that with `??=` would pin [canAdvance] to false for good — the
    // demo would sit at the end of its baseline forever. The processor itself
    // applies the same rule: it only caches a resolved estimate with an RMSSD.
    if (_deadlineEstimate?.rmssd != null) return;
    _deadlineEstimate = _source?.finalizeBaselineEstimate();
  }

  bool get hasValidHeartRate => _heartRateCount > 0;
  bool get hasValidRmssd => _rmssdCount > 0;

  @override
  StreamSubscription<HeartRateSample> activate(
    PhaseContext ctx,
  ) {
    _source = ctx.source;
    ctx.source.beginMeasurement();
    return ctx.source.biometrics.listen((data) {
      _heartRateTotal += data.heartRate;
      _heartRateCount++;
      userAccount.baselineHeartRate =
          (_heartRateTotal / _heartRateCount).round();

      if (data.rmssd != null) {
        _rmssdTotal += data.rmssd!;
        _rmssdCount++;
        userAccount.baselineRMSSD = _rmssdTotal / _rmssdCount;
      }
    });
  }

  @override
  void complete(PhaseContext ctx) {
    if (!useBestEffortAtDeadline) return;
    final estimate = _deadlineEstimate;
    final rmssd = estimate?.rmssd;
    if (estimate == null || rmssd == null) return;
    // The deadline estimate is based on the complete retained demo window and
    // therefore supersedes partial rolling-window values emitted earlier.
    userAccount.baselineHeartRate = estimate.heartRate;
    userAccount.baselineRMSSD = rmssd;
  }
}

class StressMonitoringPhase extends MonitoringPhase {
  @override
  Duration? get duration => null;

  @override
  StreamSubscription<HeartRateSample> activate(
    PhaseContext ctx,
  ) {
    ctx.source.beginMeasurement();
    return ctx.source.biometrics.listen((sample) {
      ctx.detector.onSample(
        sample,
        suppress: ctx.suppressStressDetectionDuringActivity &&
            ctx.source.suppressStressDetection,
      );
    });
  }
}

class MonitoringPhaseController {
  final PhaseContext _ctx;
  final List<MonitoringPhase> _phases;

  late final ValueNotifier<MonitoringPhase> phase;
  final ValueNotifier<double?> progress = ValueNotifier(null);

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  StreamSubscription<HeartRateSample>? _phaseSub;
  int _index = 0;

  MonitoringPhaseController({
    required PhaseContext ctx,
    required List<MonitoringPhase> phases,
  })  : _ctx = ctx,
        _phases = phases {
    phase = ValueNotifier(_phases.first);
  }

  MonitoringPhase get current => _phases[_index];

  void start() {
    _index = 0;
    progress.value = 0;
    phase.value = current;
    _stopwatch
      ..reset()
      ..start();
    _activate();
    _startTicker();
  }

  void pause() {
    _stopwatch.stop();
    _ticker?.cancel();
    _phaseSub?.cancel();
  }

  void resume() {
    _stopwatch.start();
    _activate();
    if (current.duration != null) _startTicker();
  }

  void dispose() {
    _ticker?.cancel();
    _phaseSub?.cancel();
    phase.dispose();
    progress.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      BioAdaptiveModeConfig.phaseProgressUpdateInterval,
      (_) => _tick(),
    );
  }

  void _tick() {
    final duration = current.duration;
    if (duration == null) {
      progress.value = null;
      return; // indefinite phase — nothing to time or advance
    }
    progress.value =
        (_stopwatch.elapsed.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);
    if (_stopwatch.elapsed >= duration) {
      current.atDeadline(_ctx);
      if (current.canAdvance) _advance();
    }
  }

  void _advance() {
    if (_index >= _phases.length - 1) return; // last phase; stay put
    current.complete(_ctx);
    _phaseSub?.cancel();
    _index++;
    _stopwatch
      ..reset()
      ..start();
    _activate();
    progress.value = current.duration == null ? null : 0;
    phase.value = current;

    // Once we reach an indefinite phase, the ticker has nothing left to do.
    if (current.duration == null) {
      _ticker?.cancel();
    }
  }

  void _activate() {
    _phaseSub?.cancel();
    _phaseSub = current.activate(_ctx);
  }
}
