// ignore_for_file: require_trailing_commas

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import '../biosignals/sensors/hr_sensor_interface.dart';
import 'improved_meditation_llm_service.dart';
import 'meditation_voice_service.dart';
import '../../models/user_account.dart';
import '../../config/demo_config.dart';
import 'personalized_stress_detector.dart';
import '../storage/meditation_history.dart';
import '../biosignals/activity_detector.dart';
import '../storage/meditation_cache.dart';

final _logger = Logger();

enum MeditationState {
  idle,
  measuringBaseline,
  generatingContent,
  speaking,
  waitingForBiosignals,
  paused,
  completed,
  error,
}

/// Main controller for adaptive meditation sessions
///
/// Manages the complete meditation flow including:
/// - Real-time biosignal monitoring (HR/HRV)
/// - Personalized stress detection with activity recognition
/// - LLM-generated meditation content
/// - Text-to-speech guidance
/// - Background music playback
/// - Session analytics and history tracking
class ImprovedMeditationController {
  final HrSensorInterface sensor;
  final ImprovedMeditationLLMService llmService;
  final MeditationVoiceService voiceService;
  final AudioPlayer backgroundMusicPlayer = AudioPlayer();
  final UserAccount userAccount;
  late PersonalizedStressDetector stressDetector;

  // Demo mode support
  final String demoMode;
  final DemoMeditationPreferences? demoPreferences;
  final double? demoBaselineHr;
  final double? demoBaselineRmssd;
  final VoidCallback? onDemoComplete;

  // State
  MeditationState _state = MeditationState.idle;
  MeditationState get state => _state;
  bool _isPaused = false;

  // Biosignal data
  double _baselineHr = 75.0;
  double _baselineHrv = 50.0;
  double _currentHr = 75.0;
  double _currentHrv = 50.0;

  // Calibration state
  bool _isCalibrating = true;
  DateTime? _calibrationStartTime;
  final List<double> _hrMeasurements = [];
  final List<double> _hrvMeasurements = [];
  
  // Calibration duration - demo mode uses 30s, normal uses 300s (5 min)
  int get _calibrationDurationSeconds {
    if (demoMode == DemoConfig.modeBiosignalAdaptive) {
      return DemoConfig.baselineDuration.inSeconds;
    }
    return 300; // 5 minutes for robust baseline calibration
  }
  
  // Max meditation iterations - varies by mode
  int get _maxMeditationIterations {
    if (demoMode == DemoConfig.modePersonalizedOnly) {
      return DemoConfig.personalizedOnlyMaxSegments;
    } else if (demoMode == DemoConfig.modeBiosignalAdaptive) {
      return DemoConfig.biosignalAdaptiveMaxSegments;
    }
    return 10; // Standard max for normal mode
  }

  // Session tracking
  int _iterationCount = 0;
  DateTime? _sessionStartTime;
  bool _isBaselineReady = false;
  double _peakStressLevel = 0.0;
  Timer? _sessionTimer;
  DateTime? _lastSensorDataTime; // Track when we last received sensor data
  static const int _sensorTimeoutSeconds =
      45; // Stop if no data for 45 seconds (increased from 15 to prevent false timeouts)
  bool _isCompletingSession = false; // Guard flag to prevent concurrent completion calls

  // Monitoring
  Timer? _stressMonitorTimer;
  bool _isMonitoringStress = false;
  bool _meditationAutoStarted = false;

  // Activity history for 5-minute buffer (prevents false stress detection after exercise)
  final List<({DateTime timestamp, ActivityLevel level})> _activityHistory = [];
  static const Duration _activityBufferDuration = Duration(minutes: 5);

  // Subscriptions
  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<Map<String, double>>? _hrvSubscription;

  // Callbacks
  final void Function(MeditationState state)? onStateChanged;
  final void Function(String message)? onStatusMessage;
  final void Function(double hr, double hrv)? onBiosignalUpdate;
  final void Function()? onSessionComplete;
  final void Function(bool isStressed)? onStressDetected;
  final void Function(int currentSegment, int estimatedTotal)? onSegmentUpdate;
  final void Function(Duration elapsed)? onTimerUpdate;

  ImprovedMeditationController({
    required this.sensor,
    required this.llmService,
    required this.voiceService,
    required this.userAccount,
    this.onStateChanged,
    this.onStatusMessage,
    this.onBiosignalUpdate,
    this.onSessionComplete,
    this.onStressDetected,
    this.onSegmentUpdate,
    this.onTimerUpdate,
    this.demoMode = DemoConfig.modeNone,
    this.demoPreferences,
    this.demoBaselineHr,
    this.demoBaselineRmssd,
    this.onDemoComplete,
  }) {
    stressDetector = PersonalizedStressDetector(userAccount: userAccount);
    llmService.setUserAccount(userAccount);
    
    // Configure LLM service for demo mode
    if (demoMode != DemoConfig.modeNone) {
      llmService.setDemoMode(
        demoMode: demoMode,
        demoPreferences: demoPreferences,
      );
    }
  }

  void _setState(MeditationState newState) {
    _state = newState;
    onStateChanged?.call(newState);
    _logger.i('State: $newState');
  }

  void _sendStatus(String message) {
    onStatusMessage?.call(message);
    _logger.i('Status: $message');
  }

  /// Start meditation session
  Future<void> startSession() async {
    // Prevent starting if already active
    if (_state != MeditationState.idle) {
      _logger.w('Cannot start session - already in progress (state: $_state)');
      return;
    }

    try {
      _logger.i('Starting meditation session');
      _sessionStartTime = DateTime.now();
      _lastSensorDataTime =
          DateTime.now(); // Initialize sensor timeout tracking
      _iterationCount = 0;
      _isBaselineReady = false;
      _meditationAutoStarted = false;
      _peakStressLevel = 0.0;
      _isPaused = false;
      _isCompletingSession = false; // Reset completion flag

      llmService.startNewSession();

      // Start environment-based background ambience
      await _playBackgroundAmbience();

      // Subscribe to biosignals
      _subscribeToSensor();

      // Start session timer
      _startSessionTimer();

      // Measure baseline
      await _measureBaseline();

      // Generate welcome
      _setState(MeditationState.generatingContent);
      final welcomeText = await llmService.generatePersonalizedWelcome(
        currentHr: _currentHr,
        currentHrv: _currentHrv,
        baselineHr: _baselineHr,
        baselineHrv: _baselineHrv,
      );

      await _speak(welcomeText);

      // Start adaptive loop
      await _adaptiveLoop();
    } catch (e) {
      _logger.e('Error starting session: $e');
      _setState(MeditationState.error);
      _sendStatus('Error: $e');
    }
  }

  void _subscribeToSensor() {
    // Reset sensor timeout tracking to prevent false timeouts on reconnect
    // This prevents false timeout detection if reconnecting after a disconnect
    _lastSensorDataTime = null;

    _logger.i('Subscribing to sensor streams: ${sensor.runtimeType}');

    int hrCount = 0;
    _hrSubscription = sensor.hrStream.listen((hr) {
      hrCount++;
      if (hrCount <= 3) {
        _logger
            .i('HR Stream #$hrCount: $hr BPM (sensor: ${sensor.runtimeType})');
      }

      _currentHr = hr;
      _lastSensorDataTime = DateTime.now(); // Track data reception
      _refineBaselineDuringCalibration(); // Adaptively refine baseline during first 5 minutes
      onBiosignalUpdate?.call(_currentHr, _currentHrv);

      // Log to verify subscriptions are still active after meditation ends
      if (_state == MeditationState.completed ||
          _state == MeditationState.idle) {
        _logger.i('HR data received after session: HR=$hr (state: $_state)');
      }
    });

    int hrvCount = 0;
    _hrvSubscription = sensor.hrvStream.listen((hrvData) {
      hrvCount++;
      if (hrvCount <= 3) {
        _logger.i(
            'HRV Stream #$hrvCount: $hrvData (sensor: ${sensor.runtimeType})');
      }

      _currentHrv = hrvData['HRV_RMSSD'] ??
          hrvData['rmssd'] ??
          hrvData['RMSSD'] ??
          _currentHrv;
      _lastSensorDataTime = DateTime.now(); // Track data reception
      _refineBaselineDuringCalibration(); // Adaptively refine baseline during first 5 minutes
      onBiosignalUpdate?.call(_currentHr, _currentHrv);

      // Log to verify subscriptions are still active after meditation ends
      if (_state == MeditationState.completed ||
          _state == MeditationState.idle) {
        _logger.i(
            'HRV data received after session: HRV=$_currentHrv (state: $_state)');
      }
    });

    _logger.i('Subscribed to HR and HRV streams');
  }

  Future<void> _measureBaseline() async {
    _setState(MeditationState.measuringBaseline);

    // In demo mode with provided baselines, use those directly
    if (demoMode == DemoConfig.modeBiosignalAdaptive && 
        demoBaselineHr != null && 
        demoBaselineRmssd != null) {
      _baselineHr = demoBaselineHr!;
      _baselineHrv = demoBaselineRmssd!;
      
      _logger.i(
          'Using demo baseline: HR=${_baselineHr.toStringAsFixed(1)}, RMSSD=${_baselineHrv.toStringAsFixed(1)}');
      _logger.i('   Demo mode: No demographic data used');
      
      // Skip calibration entirely for demo mode - baseline already measured
      _isCalibrating = false;
      _isBaselineReady = true;
      _sendStatus('Demo baseline applied');
      return;
    }
    
    // For personalized-only demo mode, use lighter calibration
    if (demoMode == DemoConfig.modePersonalizedOnly) {
      // Use fallback values for personalized-only (no biosignal adaptation needed)
      _baselineHr = DemoConfig.fallbackBaselineHr;
      _baselineHrv = DemoConfig.fallbackBaselineRmssd;
      
      _logger.i(
          'Personalized-Only Demo: Using fallback baseline: HR=${_baselineHr.toStringAsFixed(1)}, RMSSD=${_baselineHrv.toStringAsFixed(1)}');
      
      _isCalibrating = false;
      _isBaselineReady = true;
      _sendStatus('Starting personalized meditation...');
      return;
    }

    // Normal mode: Start with research-based baseline
    final researchBaseline = stressDetector.getResearchBaselines();
    _baselineHr = researchBaseline['baselineHr']!;
    _baselineHrv = researchBaseline['baselineHrv']!;

    _logger.i(
        'Starting with research baseline: HR=${_baselineHr.toStringAsFixed(1)}, HRV=${_baselineHrv.toStringAsFixed(1)}');
    _logger.i(
        '   Based on: ${userAccount.age}y, ${userAccount.gender}, ${userAccount.fitnessLevel}');

    // Start calibration period
    _isCalibrating = true;
    _calibrationStartTime = DateTime.now();
    _hrMeasurements.clear();
    _hrvMeasurements.clear();

    _sendStatus('Starting meditation...');

    // Mark baseline as ready immediately - we can start right away!
    _isBaselineReady = true;

    // No delay - start meditation immediately with research baseline
  }

  /// Refine baseline during calibration period using live measurements
  void _refineBaselineDuringCalibration() {
    if (!_isCalibrating || _calibrationStartTime == null) return;

    // Collect current measurements
    if (_currentHr > 0) _hrMeasurements.add(_currentHr);
    if (_currentHrv > 0) _hrvMeasurements.add(_currentHrv);

    final elapsed = DateTime.now().difference(_calibrationStartTime!).inSeconds;

    // Check if calibration period is over
    if (elapsed >= _calibrationDurationSeconds) {
      _finishCalibration();
      return;
    }

    // Send calibration progress status message
    final progress = (elapsed / _calibrationDurationSeconds * 100).round();
    _sendStatus('Calibrating baseline... ${progress}% (${elapsed}s / ${_calibrationDurationSeconds}s)');

    // Adaptive refinement during calibration
    if (_hrMeasurements.isEmpty || _hrvMeasurements.isEmpty) return;

    // Calculate measured average
    final measuredHr =
        _hrMeasurements.reduce((a, b) => a + b) / _hrMeasurements.length;
    final measuredHrv =
        _hrvMeasurements.reduce((a, b) => a + b) / _hrvMeasurements.length;

    // Get research baseline
    final researchBaseline = stressDetector.getResearchBaselines();
    final researchHr = researchBaseline['baselineHr']!;
    final researchHrv = researchBaseline['baselineHrv']!;

    // Weighted average: gradually trust measured values more over time
    // 0-100s: 80% research, 20% measured
    // 100-200s: 60% research, 40% measured
    // 200-300s: 40% research, 60% measured
    final researchWeight = 1.0 - (elapsed / _calibrationDurationSeconds * 0.6);
    final measuredWeight = 1.0 - researchWeight;

    _baselineHr = (researchHr * researchWeight) + (measuredHr * measuredWeight);
    _baselineHrv =
        (researchHrv * researchWeight) + (measuredHrv * measuredWeight);
  }

  /// Check if sensor data has timed out (no new data for too long)
  bool _hasSensorTimedOut() {
    if (_lastSensorDataTime == null) return false; // No data received yet

    final elapsed = DateTime.now().difference(_lastSensorDataTime!).inSeconds;
    return elapsed > _sensorTimeoutSeconds;
  }

  /// Complete calibration and finalize baseline
  void _finishCalibration() {
    if (!_isCalibrating) return;

    _isCalibrating = false;

    if (_hrMeasurements.length >= 5 && _hrvMeasurements.length >= 5) {
      // Use measured values with slight research influence
      final measuredHr =
          _hrMeasurements.reduce((a, b) => a + b) / _hrMeasurements.length;
      final measuredHrv =
          _hrvMeasurements.reduce((a, b) => a + b) / _hrvMeasurements.length;

      final researchBaseline = stressDetector.getResearchBaselines();
      _baselineHr =
          (measuredHr * 0.7) + (researchBaseline['baselineHr']! * 0.3);
      _baselineHrv =
          (measuredHrv * 0.7) + (researchBaseline['baselineHrv']! * 0.3);

      _logger.i(
          'Calibration complete! Refined baseline: HR=${_baselineHr.toStringAsFixed(1)}, HRV=${_baselineHrv.toStringAsFixed(1)}');
      _logger.i(
          '  Collected ${_hrMeasurements.length} HR and ${_hrvMeasurements.length} HRV measurements');
    } else {
      _logger.i(
          'Calibration complete (keeping research baseline - insufficient measurements)');
    }

    _sendStatus('Baseline established - meditation in progress...');
  }

  Future<void> _adaptiveLoop() async {
    final maxIterations = _maxMeditationIterations;

    while (_iterationCount < maxIterations &&
        _state != MeditationState.idle &&
        _state != MeditationState.completed) {
      if (_isPaused) {
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }

      _iterationCount++;

      // Notify about segment progress
      onSegmentUpdate?.call(_iterationCount, maxIterations);

      // Avoid state change here to prevent UI flicker
      // Just wait for biosignals silently without triggering state changes
      // _setState(MeditationState.waitingForBiosignals); // REMOVED to fix flickering

      // Wait for biosignals (don't interrupt mid-segment!)
      // We'll check for relaxation AFTER the next segment, not during waiting
      await Future.delayed(const Duration(seconds: 3));

      if (_state == MeditationState.idle) break; // User stopped

      // Check for sensor data timeout indicating connection loss
      if (_hasSensorTimedOut()) {
        _logger.e(
            'Sensor timeout detected - no new data for $_sensorTimeoutSeconds seconds!');
        _logger.e('   Connection likely lost. Ending meditation gracefully.');
        _sendStatus('Connection lost - ending session');
        // Call _completeSession() instead of stopSession() to speak a completion message
        await _completeSession();
        return;
      }

      // Get activity level if available
      ActivityLevel? activityLevel;
      try {
        final dynamic dynamicSensor = sensor;
        activityLevel = dynamicSensor.activityLevel as ActivityLevel?;
      } catch (e) {
        // Sensor doesn't support activity detection - that's OK
      }

      // Check stress with personalized detector (activity-aware)
      final stressLevel = stressDetector.getStressLevel(_currentHr, _currentHrv,
          activityLevel: activityLevel);
      final isNowRelaxed = stressDetector.isRelaxed(_currentHr, _currentHrv);
      _peakStressLevel =
          stressLevel > _peakStressLevel ? stressLevel : _peakStressLevel;

      final readyToEnd = stressDetector.isReadyToEndSession(
        startHr: _baselineHr,
        startHrv: _baselineHrv,
        currentHr: _currentHr,
        currentHrv: _currentHrv,
        iterationCount: _iterationCount,
      );

      final hrChange = ((_baselineHr - _currentHr) / _baselineHr * 100);
      final hrvChange = ((_currentHrv - _baselineHrv) / _baselineHrv * 100);

      _logger.i(
          'Iteration $_iterationCount: Stress=${stressLevel.toStringAsFixed(1)}%, '
          'Relaxed=$isNowRelaxed, HR change=${hrChange.toStringAsFixed(1)}%, '
          'HRV change=${hrvChange.toStringAsFixed(1)}%, Ready=$readyToEnd');

      if (readyToEnd) {
        final reason = stressDetector.getEndSessionReason(
          startHr: _baselineHr,
          startHrv: _baselineHrv,
          currentHr: _currentHr,
          currentHrv: _currentHrv,
        );
        _logger.i('Session complete: $reason');
        await _completeSession();
        return;
      }

      // Generate next segment
      _setState(MeditationState.generatingContent);
      _sendStatus('Creating personalized guidance...');

      try {
        final segment = await llmService.generateMeditationSegment(
          currentHr: _currentHr,
          currentHrv: _currentHrv,
          baselineHr: _baselineHr,
          baselineHrv: _baselineHrv,
          isStressed: true,
          stressLevel: stressLevel,
        );

        if (_state == MeditationState.idle) break; // User stopped

        await _speak(segment);

        if (_state == MeditationState.idle) break; // User stopped

        // Check again after speaking - person might have relaxed during the segment
        if (_iterationCount >= 3 &&
            stressDetector.isReadyToEndSession(
                startHr: _baselineHr,
                startHrv: _baselineHrv,
                currentHr: _currentHr,
                currentHrv: _currentHrv,
                iterationCount: _iterationCount)) {
          final reason = stressDetector.getEndSessionReason(
            startHr: _baselineHr,
            startHrv: _baselineHrv,
            currentHr: _currentHr,
            currentHrv: _currentHrv,
          );
          _logger.i('Session complete after segment: $reason');
          await _completeSession();
          return;
        }

        await Future.delayed(const Duration(
            milliseconds: 1500)); // Reduced from 3s to 1.5s for smoother flow
      } catch (e) {
        _logger.e('Error in loop: $e');
      }
    }

    if (_state != MeditationState.idle) {
      await _completeSession();
    }
  }

  Future<void> _speak(String text) async {
    if (_state == MeditationState.idle) return;

    _setState(MeditationState.speaking);
    _sendStatus('Guiding you...');

    // Lower background ambience during speech
    try {
      await backgroundMusicPlayer
          .setVolume(0.25); // Gentle background during voice (25%)
    } catch (e) {
      // Ignore if not playing
    }

    try {
      // Check if user stopped the session BEFORE speaking
      if (_state == MeditationState.idle) {
        _logger.i('Session stopped before speaking - skipping speech');
        return;
      }

      // Let the current segment finish completely without interruption
      await voiceService.speak(text);

      // After speech completes, check if we should end the session
      if (_state == MeditationState.idle) {
        _logger.i('Session stopped during speech - exiting gracefully');
        return;
      }

      // Don't check for relaxation here - it's handled in the main loop
      // This prevents duplicate completion calls
    } catch (e) {
      _logger.e('Speech error: $e');
    }

    // Restore ambience volume after speech
    try {
      await backgroundMusicPlayer.setVolume(0.30); // Back to 30%
    } catch (e) {
      // Ignore if not playing
    }
  }

  Future<void> _completeSession() async {
    // Ensure idempotency for session completion - prevent race conditions
    if (_isCompletingSession) {
      _logger.w('_completeSession() already in progress - skipping concurrent call');
      return;
    }
    
    if (_state == MeditationState.completed ||
        _state == MeditationState.idle) {
      _logger.w(
          '_completeSession() blocked - already completed or idle (state: $_state)');
      return;
    }

    // Set guard flag
    _isCompletingSession = true;
    
    _logger.i('Starting session completion...');
    _setState(MeditationState.generatingContent);

    try {
      final completionText = await llmService.generateCompletionText(
        startHr: _baselineHr,
        startHrv: _baselineHrv,
        endHr: _currentHr,
        endHrv: _currentHrv,
      );
      await _speak(completionText);
    } catch (e) {
      _logger.e('Completion error: $e');
    }

    // Stop audio
    await voiceService.stop();
    await backgroundMusicPlayer.stop();

    // Save to history
    final duration = DateTime.now().difference(_sessionStartTime!).inSeconds;
    await MeditationHistory.instance.addSession(
      userId: userAccount.userId,
      startHr: _baselineHr,
      startHrv: _baselineHrv,
      endHr: _currentHr,
      endHrv: _currentHrv,
      durationSeconds: duration,
      iterationCount: _iterationCount,
      peakStressLevel: _peakStressLevel,
    );

    _setState(MeditationState.completed);
    _sendStatus('Session complete!');
    _meditationAutoStarted = false;
    
    // Cancel session timer
    _sessionTimer?.cancel();
    _sessionTimer = null;

    // Keep monitoring active for post-session analytics
    // The app should continue monitoring HR/HRV to:
    // 1. Display real-time values to the user
    // 2. Detect if user becomes stressed again after cooldown
    // Subscriptions are kept active - they're only cancelled in stopSession() or dispose()
    _logger.i('Session complete - HR/HRV monitoring continues');

    onSessionComplete?.call();
    
    // Call demo complete callback if in demo mode
    if (demoMode != DemoConfig.modeNone) {
      onDemoComplete?.call();
      _logger.i('Demo session complete - callback invoked');
    }
  }

  /// Stop session - PROPERLY
  Future<void> stopSession() async {
    _logger.i('Stopping session');

    // Set state first
    _setState(MeditationState.idle);
    _isPaused = false;
    _meditationAutoStarted = false;

    // Cancel session timer
    _sessionTimer?.cancel();
    _sessionTimer = null;

    // Stop audio playback
    await voiceService.stop();
    await backgroundMusicPlayer.stop();

    _logger.i('Session stopped - biosignal monitoring continues');
  }

  /// Pause session - PROPERLY
  Future<void> pauseSession() async {
    if (_state == MeditationState.idle) return;

    _logger.i('Pausing session');
    _isPaused = true;
    _setState(MeditationState.paused);

    await voiceService.pause();
    await backgroundMusicPlayer.pause();
  }

  /// Resume session
  Future<void> resumeSession() async {
    if (!_isPaused) return;

    _logger.i('Resuming session');
    _isPaused = false;
    _setState(MeditationState.speaking);

    await voiceService.resume();
    await backgroundMusicPlayer.resume();
  }

  /// Start monitoring
  void startMonitoring() {
    if (_isMonitoringStress) return;

    _logger.i('Starting stress monitoring');
    _isMonitoringStress = true;
    _subscribeToSensor();

    // Use research-based baseline immediately
    final researchBaseline = stressDetector.getResearchBaselines();
    _baselineHr = researchBaseline['baselineHr']!;
    _baselineHrv = researchBaseline['baselineHrv']!;
    _isBaselineReady = true;

    _logger.i(
        'Using research baseline: HR=${_baselineHr.toStringAsFixed(1)} BPM, HRV=${_baselineHrv.toStringAsFixed(1)} ms');
    _logger.i(
        '   Profile: ${userAccount.age}y ${userAccount.gender}, ${userAccount.fitnessLevel} fitness');

    // Refine with measured values after 5 minutes (only if still monitoring)
    Future.delayed(Duration(seconds: 300), () {
      if (!_isMonitoringStress) return; // Guard: only refine if still monitoring
      
      if (_currentHr > 40 && _currentHrv > 10) {
        // Weighted average: 60% measured + 40% research
        _baselineHr = (_currentHr * 0.6) + (_baselineHr * 0.4);
        _baselineHrv = (_currentHrv * 0.6) + (_baselineHrv * 0.4);
        _logger.i(
            'Baseline refined with measurements: HR=${_baselineHr.toStringAsFixed(1)}, HRV=${_baselineHrv.toStringAsFixed(1)}');
      }
    });

    // Check stress periodically (faster checks for testing)
    _stressMonitorTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isBaselineReady || _state != MeditationState.idle) return;

      // Get activity level from sensor (if available)
      ActivityLevel? activityLevel;
      // Try to get activity level if sensor supports it
      try {
        final dynamic dynamicSensor = sensor;
        activityLevel = dynamicSensor.activityLevel as ActivityLevel?;
      } catch (e) {
        // Sensor doesn't support activity detection - that's OK
      }

      // Update activity history with current reading
      _updateActivityHistory(activityLevel ?? ActivityLevel.resting);

      final isStressed = stressDetector.isStressed(_currentHr, _currentHrv,
          activityLevel: activityLevel);
      final stressLevel = stressDetector.getStressLevel(_currentHr, _currentHrv,
          activityLevel: activityLevel);

      // Check if recent activity should suppress meditation triggering
      final suppressedByActivity = _shouldSuppressMeditationDueToActivity();

      _logger.i(
          'Periodic stress check: HR=$_currentHr, HRV=$_currentHrv, activity=${activityLevel?.name ?? "unknown"}, stressed=$isStressed, level=${stressLevel.toStringAsFixed(1)}%, suppressed=$suppressedByActivity');
      onStressDetected?.call(isStressed);

      // Only auto-start if stressed AND not suppressed by recent activity
      if (isStressed && !suppressedByActivity && !_meditationAutoStarted) {
        _meditationAutoStarted = true;
        _sendStatus('Stress detected');
      } else if (!isStressed && _meditationAutoStarted) {
        _meditationAutoStarted = false;
      }
    });
  }

  void stopMonitoring() {
    _stressMonitorTimer?.cancel();
    _isMonitoringStress = false;
    
    // Clear activity history to prevent memory leak
    _activityHistory.clear();
  }

  /// Update activity history with new reading and prune old entries
  void _updateActivityHistory(ActivityLevel currentLevel) {
    final now = DateTime.now();
    
    // Add current reading
    _activityHistory.add((timestamp: now, level: currentLevel));
    
    // Prune entries older than 5 minutes
    final cutoff = now.subtract(_activityBufferDuration);
    _activityHistory.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
  }

  /// Check if recent activity should suppress meditation triggering
  /// 
  /// Returns true if:
  /// - ANY intense activity detected in time window
  /// - OR Vigorous activity ≥5% of time window
  /// - OR Moderate activity ≥20% of time window
  /// - OR Light activity ≥40% of time window
  /// 
  /// Percentages apply to whatever time window is available (adapts before 5 minutes filled)
  bool _shouldSuppressMeditationDueToActivity() {
    if (_activityHistory.isEmpty) return false;
    
    // Calculate total time window (use actual time available, not fixed 5 minutes)
    final now = DateTime.now();
    final oldestEntry = _activityHistory.first.timestamp;
    final timeWindowSeconds = now.difference(oldestEntry).inSeconds;
    
    if (timeWindowSeconds == 0) return false; // Avoid division by zero
    
    // Count duration at each activity level
    // Assuming measurements every ~3 seconds, each entry represents ~3 seconds
    int intenseCount = 0;
    int vigorousCount = 0;
    int moderateCount = 0;
    int lightCount = 0;
    
    for (final entry in _activityHistory) {
      switch (entry.level) {
        case ActivityLevel.intense:
          intenseCount++;
          break;
        case ActivityLevel.vigorous:
          vigorousCount++;
          break;
        case ActivityLevel.moderate:
          moderateCount++;
          break;
        case ActivityLevel.light:
          lightCount++;
          break;
        case ActivityLevel.resting:
          // Resting doesn't contribute to suppression
          break;
      }
    }
    
    // ANY intense activity blocks meditation (sprinting, very intense exercise)
    if (intenseCount > 0) {
      return true;
    }
    
    // Each entry represents ~3 seconds (Timer.periodic interval)
    const secondsPerEntry = 3;
    final vigorousSeconds = vigorousCount * secondsPerEntry;
    final moderateSeconds = moderateCount * secondsPerEntry;
    final lightSeconds = lightCount * secondsPerEntry;
    
    // Calculate percentages relative to actual time window
    final vigorousPercent = (vigorousSeconds / timeWindowSeconds) * 100;
    final moderatePercent = (moderateSeconds / timeWindowSeconds) * 100;
    final lightPercent = (lightSeconds / timeWindowSeconds) * 100;
    
    // Check suppression criteria
    final suppressedByVigorous = vigorousPercent >= 5.0;
    final suppressedByModerate = moderatePercent >= 20.0;
    final suppressedByLight = lightPercent >= 40.0;
    
    return suppressedByVigorous || suppressedByModerate || suppressedByLight;
  }

  Map<String, dynamic> getCurrentBiosignals() {
    int? calibrationProgress;
    if (_isCalibrating && _calibrationStartTime != null) {
      final elapsed =
          DateTime.now().difference(_calibrationStartTime!).inSeconds;
      calibrationProgress =
          ((elapsed / _calibrationDurationSeconds) * 100).clamp(0, 100).toInt();
    }

    return {
      'currentHr': _currentHr,
      'currentHrv': _currentHrv,
      'baselineHr': _baselineHr,
      'baselineHrv': _baselineHrv,
      'isCalibrating': _isCalibrating,
      'calibrationProgress': calibrationProgress,
      'calibrationMeasurements': _hrMeasurements.length,
    };
  }

  /// Get current stress category as string
  String get currentStressCategory {
    if (_currentHrv < 0) return 'measuring';

    // Get activity level from sensor if available
    ActivityLevel? activityLevel;
    try {
      final dynamic dynamicSensor = sensor;
      activityLevel = dynamicSensor.activityLevel as ActivityLevel?;
    } catch (e) {
      // Sensor doesn't support activity detection
    }

    return stressDetector.getStressCategory(_currentHr, _currentHrv,
        activityLevel: activityLevel);
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sessionStartTime != null && _state != MeditationState.idle) {
        final elapsed = DateTime.now().difference(_sessionStartTime!);
        onTimerUpdate?.call(elapsed);
      }
    });
  }

  Future<void> _playMeditationAsset(String fileName) async {
    final assetPath = 'lib/apps/meditation/assets/$fileName';
    final bytes = await rootBundle.load(assetPath);
    await backgroundMusicPlayer.play(
      BytesSource(bytes.buffer.asUint8List()),
    );
  }

  /// Play background ambience based on user's environment preference
  Future<void> _playBackgroundAmbience() async {
    String? audioFile;
    try {
      final environment = userAccount.meditationEnvironment.toLowerCase();
      _logger.i('Starting background ambience for environment: "$environment"');

      // Map environment preference to audio file
      if (environment.contains('ocean') || environment.contains('beach')) {
        audioFile = 'Ocean_Beach.wav';
      } else if (environment.contains('mountain')) {
        audioFile = 'Mountain.wav';
      } else if (environment.contains('forest')) {
        audioFile = 'Forest.wav';
      } else if (environment.contains('garden')) {
        audioFile = 'Garden.mp3';
      } else if (environment.contains('nature')) {
        audioFile = 'Peaceful_Nature.wav';
      }

      if (audioFile != null) {
        _logger.i('Selected audio file: $audioFile');

        try {
          _logger.d('Setting release mode to loop...');
          await backgroundMusicPlayer.setReleaseMode(ReleaseMode.loop);

          // Configure audio context to allow mixing with TTS
          _logger.d('Configuring audio context...');
          final AudioContext audioContext = AudioContext(
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {
                AVAudioSessionOptions.mixWithOthers,
                // AVAudioSessionOptions.duckOthers, // Disabled: causing too much volume drop?
              },
            ),
            android: AudioContextAndroid(
              isSpeakerphoneOn: true,
              stayAwake: true,
              contentType: AndroidContentType.music,
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
          );

          // Apply context to this player
          _logger.d('Applying audio context...');
          await backgroundMusicPlayer.setAudioContext(audioContext);

          _logger.d('Setting volume to 60%...');
          await backgroundMusicPlayer.setVolume(0.60);

          _logger.i('Playing meditation asset: $audioFile');
          await _playMeditationAsset(audioFile);

          _logger.i('Background ambience playing successfully at 60% volume');
        } catch (e, stackTrace) {
          _logger.e('Failed to play $audioFile: $e');
          _logger.e('Stack trace: $stackTrace');
        }
      } else {
        _logger.w(
            'No specific audio file for environment: "$environment". Using default.');
        // Fallback to default meditation sound if available
        try {
          audioFile = 'meditation_sound.mp3';
          _logger.i('Trying default: $audioFile');
          await backgroundMusicPlayer.setReleaseMode(ReleaseMode.loop);
          await backgroundMusicPlayer.setVolume(0.30);
          await _playMeditationAsset(audioFile);
          _logger.i('Default background sound playing');
        } catch (e) {
          _logger.w('Default background sound failed: $e');
        }
      }
    } catch (e, stackTrace) {
      _logger.e('Background ambience failed: $e');
      _logger.e('Tried to play: $audioFile');
      _logger.e('Stack trace: $stackTrace');
    }
  }

  /// Emergency: Clear all cached audio (use if cache is corrupted)
  /// This will force fresh generation of all TTS audio
  Future<void> clearAudioCache() async {
    _logger.w('Clearing all TTS audio cache...');
    await MeditationCache.clearAllCache();
    _logger.i('Cache cleared successfully');
  }

  Future<void> dispose() async {
    _logger.i('Disposing ImprovedMeditationController');

    // Cancel timers first
    _stressMonitorTimer?.cancel();
    _sessionTimer?.cancel();

    // Stop session (stops audio, but doesn't cancel subscriptions)
    await stopSession();

    // NOW cancel subscriptions (only on full dispose)
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _logger.i('Biosignal subscriptions cancelled');

    // Dispose internally created resources
    await backgroundMusicPlayer.dispose();

    _logger.i('ImprovedMeditationController disposed');
  }
}
