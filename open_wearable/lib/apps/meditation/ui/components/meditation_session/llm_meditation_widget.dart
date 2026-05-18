// ignore_for_file: require_trailing_commas

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/meditation/improved_meditation_controller.dart';
import '../../../core/meditation/improved_meditation_llm_service.dart';
import '../../../core/meditation/meditation_voice_service.dart';
import '../../../config/meditation_config.dart';
import '../../../config/demo_config.dart';
import '../../../core/meditation/outlook_meeting_blocker.dart';
import '../../../models/user_account.dart';
import '../../../core/biosignals/sensors/hr_sensor_interface.dart';
import '../../../core/storage/mood_entry.dart';
import '../../screens/weekly_analysis_screen.dart';

/// Improved meditation widget with natural voice and personalization
class LlmMeditationWidget extends StatefulWidget {
  final HrSensorInterface sensor;
  final VoidCallback? onReset;
  final Future<bool> Function()? onBeforeStartMeditation;
  final void Function(String stressLevel)? onStressLevelChanged;
  final bool stressDetectionEnabled;

  // Demo mode support
  final String demoMode;
  final DemoMeditationPreferences? demoPreferences;
  final double? demoBaselineHr;
  final double? demoBaselineRmssd;
  final VoidCallback? onDemoComplete;
  final ValueChanged<bool>? onMeditationSessionActive;

  const LlmMeditationWidget({
    super.key,
    required this.sensor,
    this.onReset,
    this.onBeforeStartMeditation,
    this.onStressLevelChanged,
    this.stressDetectionEnabled = true,
    this.demoMode = DemoConfig.modeNone,
    this.demoPreferences,
    this.demoBaselineHr,
    this.demoBaselineRmssd,
    this.onDemoComplete,
    this.onMeditationSessionActive,
  });

  @override
  State<LlmMeditationWidget> createState() => LlmMeditationWidgetState();
}

class LlmMeditationWidgetState extends State<LlmMeditationWidget> {
  ImprovedMeditationController? _controller;
  MeditationState _currentState = MeditationState.idle;
  String _statusMessage = 'Loading...';
  double _currentHr = 0.0;
  double _currentHrv = 0.0;
  bool _stressDetected = false;
  double _baselineHr = 0.0;

  /// Public getter for controller (used by meditation_view)
  ImprovedMeditationController? get controller => _controller;
  double _baselineHrv = 0.0;
  UserAccount? _userAccount;
  bool _isInitializing = true;
  DateTime? _lastMeditationCompletionTime;
  DateTime? _scheduledMeditationTime; // Track when meditation is scheduled
  Timer? _pendingStressPromptTimer;
  int _currentSegment = 0;
  int _totalSegments = 10;
  Duration _sessionElapsed = Duration.zero;

  // Services owned by this widget
  MeditationVoiceService? _voiceService;
  ImprovedMeditationLLMService? _llmService;
  OutlookMeetingBlocker? _meetingBlocker;

  bool get isIdle => _currentState == MeditationState.idle;
  bool get _hasConfiguredGeminiKey {
    final accountKey = _userAccount?.geminiApiKey.trim() ?? '';
    if (accountKey.length > 20 &&
        !accountKey.contains('YOUR_') &&
        !accountKey.contains('your_')) {
      return true;
    }
    return MeditationConfig.hasValidGeminiKey;
  }

  /// Public getter so the parent screen can show the API warning inline.
  bool get hasConfiguredApiKey => _hasConfiguredGeminiKey;

  Future<bool> startMeditationNowFromExternal() async {
    if (_currentState != MeditationState.idle) {
      return false;
    }
    return _attemptMeditationStart();
  }

  Future<void> stopMeditationAndClearPendingActions() async {
    _pendingStressPromptTimer?.cancel();
    _pendingStressPromptTimer = null;

    if (_controller != null) {
      await _controller!.stopSession();
      _controller!.stopMonitoring();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _stressDetected = false;
      _scheduledMeditationTime = null;
      _lastMeditationCompletionTime = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(LlmMeditationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If sensor changed, reinitialize controller with new sensor
    if (oldWidget.sensor != widget.sensor) {
      print('Sensor changed - reinitializing controller');
      _controller?.dispose();
      _controller = null;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    print(
        '🔄 LlmMeditationWidget._initialize() called with sensor: ${widget.sensor.runtimeType}');

    // NOTE: Cache auto-clear disabled now that regex bug is fixed
    // Cache will self-heal (deletes corrupted files < 1KB automatically)
    // Cache expires after 7 days
    // If issues recur, uncomment the lines below:
    // print('🗑️ Clearing TTS cache on startup...');
    // await MeditationCache.clearAllCache();

    // Load user account (primary source of truth)
    final account = await UserAccount.load();
    print(
        '🔍 LOADED ACCOUNT: name="${account.name}", voice=${account.voiceGender}, type=${account.meditationType}');

    setState(() {
      _userAccount = account;
      _currentSegment = 0;
      _sessionElapsed = Duration.zero;
      _stressDetected = false;
    });

    // Initialize services
    _voiceService = MeditationVoiceService();
    final hasValidPremiumVoice =
        _userAccount!.elevenLabsApiKey.trim().length > 20 &&
            _userAccount!.elevenLabsVoiceId.trim().isNotEmpty;
    await _voiceService!.initialize(
      voiceGender: (widget.demoMode != 'none' && widget.demoPreferences != null)
          ? widget.demoPreferences!.voiceGender
          : _userAccount!.voiceGender,
      speakingSpeed:
          (widget.demoMode != 'none' && widget.demoPreferences != null)
              ? widget.demoPreferences!.speakingSpeed
              : _userAccount!.speakingSpeed,
      usePremiumVoice: _userAccount!.usePremiumVoice || hasValidPremiumVoice,
      elevenLabsApiKey: _userAccount!.elevenLabsApiKey,
      elevenLabsVoiceId: _userAccount!.elevenLabsVoiceId,
    );

    _llmService = ImprovedMeditationLLMService();
    _llmService!.setUserAccount(_userAccount!);

    _meetingBlocker?.dispose();
    if (widget.demoMode == DemoConfig.modeNone) {
      _meetingBlocker = OutlookMeetingBlocker(
        accessToken: _userAccount!.microsoftGraphAccessToken,
      );
      await _meetingBlocker!.refreshNow();
      _meetingBlocker!.startMonitoring();
    }

    // Create controller
    print(
        '🎯 Creating ImprovedMeditationController with sensor: ${widget.sensor.runtimeType}');
    _controller = ImprovedMeditationController(
      sensor: widget.sensor,
      llmService: _llmService!,
      voiceService: _voiceService!,
      userAccount: _userAccount!,
      onStateChanged: (state) {
        if (mounted && _currentState != state) {
          setState(() {
            _currentState = state;
          });
          widget.onMeditationSessionActive?.call(state != MeditationState.idle);
        }
      },
      onStatusMessage: (message) {
        // Only update if message actually changed to reduce redraws
        if (mounted && _statusMessage != message) {
          setState(() {
            _statusMessage = message;
          });
        }
      },
      onBiosignalUpdate: (hr, hrv) {
        // Batch updates to reduce setState calls - only update if changed significantly
        if (mounted) {
          final hrDiff = (hr - _currentHr).abs();
          final hrvDiff = (hrv - _currentHrv).abs();
          // High threshold to prevent flickering - only update on significant changes
          if (hrDiff > 5.0 || hrvDiff > 10.0) {
            setState(() {
              _currentHr = hr;
              _currentHrv = hrv;
            });
          }
        }
      },
      onSessionComplete: () {
        final biosignals = _controller!.getCurrentBiosignals();
        _baselineHr = biosignals['baselineHr'] ?? 0.0;
        _baselineHrv = biosignals['baselineHrv'] ?? 0.0;
        _lastMeditationCompletionTime =
            DateTime.now(); // Record completion time
        _showCompletionDialogWithMoodCheck();
      },
      onSegmentUpdate: (current, total) {
        if (mounted) {
          setState(() {
            _currentSegment = current;
            _totalSegments = total;
          });
        }
      },
      onTimerUpdate: (elapsed) {
        if (mounted) {
          setState(() {
            _sessionElapsed = elapsed;
          });
        }
      },
      onStressDetected: _handleStressDetected,
    );

    setState(() {
      _isInitializing = false;
      _statusMessage = 'Monitoring your vitals...';
    });

    // Start monitoring (only in modes that use biosignal-based stress detection;
    // timer mode is a pure output mode with no sensor polling)
    if (widget.stressDetectionEnabled) {
      _controller!.startMonitoring();
    }

    // In demo mode the meditation session must be triggered programmatically
    // because stress-detection-based auto-start is disabled (personalised) or
    // already satisfied in the monitoring phase (biosignal-adaptive).
    if (widget.demoMode != 'none') {
      print(
          '[EARSTREAM] Demo mode (${widget.demoMode}) – scheduling auto-start of meditation session');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _currentState == MeditationState.idle &&
            _controller != null) {
          print(
              '[EARSTREAM] Auto-starting meditation session for demo mode: ${widget.demoMode}');
          _startMeditation();
        } else {
          print(
              '[EARSTREAM] Auto-start skipped: mounted=$mounted, state=$_currentState, controller=$_controller');
        }
      });
    }
  }

  @override
  void dispose() {
    _meetingBlocker?.dispose();
    _controller?.dispose();
    _voiceService?.dispose();
    _llmService?.dispose();
    super.dispose();
  }

  Future<void> resetMeditation() async {
    print(
        '🔄 RESET MEDITATION: Stopping current session and reinitializing...');

    // CRITICAL: Stop and dispose current controller/services
    if (_controller != null) {
      await _controller!.stopSession(); // This stops voice and audio
      await _controller!.dispose(); // Dispose controller and all services
      _controller = null;
    }

    // Reset all timers and states
    setState(() {
      _stressDetected = false;
      _lastMeditationCompletionTime = null;
      _scheduledMeditationTime = null;
      _currentState = MeditationState.idle;
      _statusMessage = 'Monitoring your vitals...';
    });

    // Dispose old services (controller doesn't do it anymore)
    await _voiceService?.dispose();
    _llmService?.dispose();

    // Recreate controller with current user settings
    // This ensures premium voice and other settings are preserved
    if (_userAccount != null) {
      print(
          '🔄 Recreating controller with premium voice: ${_userAccount!.usePremiumVoice}');

      _voiceService = MeditationVoiceService();
      await _voiceService!.initialize(
        voiceGender:
            (widget.demoMode != 'none' && widget.demoPreferences != null)
                ? widget.demoPreferences!.voiceGender
                : _userAccount!.voiceGender,
        speakingSpeed:
            (widget.demoMode != 'none' && widget.demoPreferences != null)
                ? widget.demoPreferences!.speakingSpeed
                : _userAccount!.speakingSpeed,
        usePremiumVoice: _userAccount!.usePremiumVoice,
        elevenLabsApiKey: _userAccount!.elevenLabsApiKey,
        elevenLabsVoiceId: _userAccount!.elevenLabsVoiceId,
      );
      print(
          '✅ Voice service reinitialized after reset: speed=${_userAccount!.speakingSpeed}, premium=${_userAccount!.usePremiumVoice}');

      _llmService = ImprovedMeditationLLMService();
      _llmService!.setUserAccount(_userAccount!);

      _meetingBlocker?.dispose();
      if (widget.demoMode == DemoConfig.modeNone) {
        _meetingBlocker = OutlookMeetingBlocker(
          accessToken: _userAccount!.microsoftGraphAccessToken,
        );
        await _meetingBlocker!.refreshNow();
        _meetingBlocker!.startMonitoring();
      }

      // Create fresh controller
      _controller = ImprovedMeditationController(
        sensor: widget.sensor,
        llmService: _llmService!,
        voiceService: _voiceService!,
        userAccount: _userAccount!,
        onStateChanged: (state) {
          if (mounted && _currentState != state) {
            setState(() {
              _currentState = state;
            });
            widget.onMeditationSessionActive
                ?.call(state != MeditationState.idle);
          }
        },
        onStatusMessage: (message) {
          if (mounted && _statusMessage != message) {
            setState(() {
              _statusMessage = message;
            });
          }
        },
        onBiosignalUpdate: (hr, hrv) {
          if (mounted) {
            final hrDiff = (hr - _currentHr).abs();
            final hrvDiff = (hrv - _currentHrv).abs();
            if (hrDiff > 5.0 || hrvDiff > 10.0) {
              setState(() {
                _currentHr = hr;
                _currentHrv = hrv;
              });
            }
          }
        },
        onSessionComplete: () {
          final biosignals = _controller!.getCurrentBiosignals();
          _baselineHr = biosignals['baselineHr'] ?? 0.0;
          _baselineHrv = biosignals['baselineHrv'] ?? 0.0;
          _lastMeditationCompletionTime = DateTime.now();
          _showCompletionDialogWithMoodCheck();
        },
        onSegmentUpdate: (current, total) {
          if (mounted) {
            setState(() {
              _currentSegment = current;
              _totalSegments = total;
            });
          }
        },
        onTimerUpdate: (elapsed) {
          if (mounted) {
            setState(() {
              _sessionElapsed = elapsed;
            });
          }
        },
        onStressDetected: _handleStressDetected,
        demoMode: widget.demoMode,
        demoPreferences: widget.demoPreferences,
        demoBaselineHr: widget.demoBaselineHr,
        demoBaselineRmssd: widget.demoBaselineRmssd,
        onDemoComplete: widget.onDemoComplete,
      );

      print('✅ Controller recreated successfully after reset');
    }

    // Don't call widget.onReset here - it's called by the parent already
    // This prevents infinite loop when parent calls resetMeditation()
  }

  Future<void> updateSettings(UserAccount updatedAccount) async {
    print(
        '🔄 UPDATE SETTINGS CALLED: voiceGender=${updatedAccount.voiceGender.toUpperCase()}, env=${updatedAccount.meditationEnvironment}, type=${updatedAccount.meditationType}');

    // Stop current session if active
    if (_controller != null && _currentState != MeditationState.idle) {
      await _controller!.stopSession();
    }

    // Dispose old controller
    await _controller?.dispose();
    _controller = null;

    setState(() {
      _userAccount = updatedAccount;
      _isInitializing = true;
    });

    // Dispose old services
    await _voiceService?.dispose();
    _llmService?.dispose();
    _meetingBlocker?.dispose();

    // Initialize new services with updated account
    _voiceService = MeditationVoiceService();
    await _voiceService!.initialize(
      voiceGender: (widget.demoMode != 'none' && widget.demoPreferences != null)
          ? widget.demoPreferences!.voiceGender
          : _userAccount!.voiceGender,
      speakingSpeed:
          (widget.demoMode != 'none' && widget.demoPreferences != null)
              ? widget.demoPreferences!.speakingSpeed
              : _userAccount!.speakingSpeed,
      usePremiumVoice: _userAccount!.usePremiumVoice,
      elevenLabsApiKey: _userAccount!.elevenLabsApiKey,
      elevenLabsVoiceId: _userAccount!.elevenLabsVoiceId,
    );
    print(
        '✅ Voice service RE-initialized: gender=${_userAccount!.voiceGender.toUpperCase()}, speed=${_userAccount!.speakingSpeed}, premium=${_userAccount!.usePremiumVoice}');

    _llmService = ImprovedMeditationLLMService();
    _llmService!.setUserAccount(_userAccount!);

    if (widget.demoMode == DemoConfig.modeNone) {
      _meetingBlocker = OutlookMeetingBlocker(
        accessToken: _userAccount!.microsoftGraphAccessToken,
      );
      await _meetingBlocker!.refreshNow();
      _meetingBlocker!.startMonitoring();
    }

    // Create new controller with updated services
    _controller = ImprovedMeditationController(
      sensor: widget.sensor,
      llmService: _llmService!,
      voiceService: _voiceService!,
      userAccount: _userAccount!,
      onStateChanged: (state) {
        if (mounted && _currentState != state) {
          setState(() {
            _currentState = state;
          });
          widget.onMeditationSessionActive?.call(state != MeditationState.idle);
        }
      },
      onStatusMessage: (message) {
        if (mounted && _statusMessage != message) {
          setState(() {
            _statusMessage = message;
          });
        }
      },
      onBiosignalUpdate: (hr, hrv) {
        if (mounted) {
          final hrDiff = (hr - _currentHr).abs();
          final hrvDiff = (hrv - _currentHrv).abs();
          if (hrDiff > 0.5 || hrvDiff > 0.5) {
            setState(() {
              _currentHr = hr;
              _currentHrv = hrv;
              _baselineHr =
                  _controller?.getCurrentBiosignals()['baselineHr'] ?? hr;
              _baselineHrv =
                  _controller?.getCurrentBiosignals()['baselineHrv'] ?? hrv;
            });
          }
        }
      },
      onSegmentUpdate: (current, total) {
        if (mounted &&
            (_currentSegment != current || _totalSegments != total)) {
          setState(() {
            _currentSegment = current;
            _totalSegments = total;
          });
        }
      },
      onTimerUpdate: (elapsed) {
        if (mounted) {
          setState(() {
            _sessionElapsed = elapsed;
          });
        }
      },
      onStressDetected: _handleStressDetected,
      demoMode: widget.demoMode,
      demoPreferences: widget.demoPreferences,
      demoBaselineHr: widget.demoBaselineHr,
      demoBaselineRmssd: widget.demoBaselineRmssd,
      onDemoComplete: widget.onDemoComplete,
    );

    setState(() {
      _isInitializing = false;
      _statusMessage = 'Monitoring your vitals...';
    });

    // Start monitoring (only in modes that use biosignal-based stress detection;
    // timer mode is a pure output mode with no sensor polling)
    if (widget.stressDetectionEnabled) {
      _controller!.startMonitoring();
    }

    print('Settings update complete!');
  }

  void _showStressPrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Stress Detected'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_userAccount?.greeting ?? 'Hello'),
            const SizedBox(height: 8),
            Text('Your biomarkers indicate elevated stress:'),
            const SizedBox(height: 12),
            Text('❤️ Heart Rate: ${_currentHr.toStringAsFixed(0)} BPM'),
            Text('📊 HRV: ${_currentHrv.toStringAsFixed(0)} ms'),
            const SizedBox(height: 16),
            const Text('Would you like to start a guided meditation?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _stressDetected = false;
                _scheduledMeditationTime =
                    DateTime.now().add(Duration(days: 1));
              });
            },
            child: const Text('Not today'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _scheduleDelayedMeditation(Duration(minutes: 30));
            },
            child: const Text('Later (30 min)'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _scheduleDelayedMeditation(Duration(minutes: 10));
            },
            child: const Text('Later (10 min)'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _attemptMeditationStart();
            },
            child: const Text('Yes, Start Now'),
          ),
        ],
      ),
    );
  }

  void _scheduleDelayedMeditation(Duration delay) {
    final scheduledTime = DateTime.now().add(delay);
    _pendingStressPromptTimer?.cancel();
    setState(() {
      _statusMessage = 'Meditation scheduled in ${delay.inMinutes} minutes';
      _stressDetected = false;
      _scheduledMeditationTime = scheduledTime;
    });

    _pendingStressPromptTimer = Timer(delay, () {
      if (mounted && _currentState == MeditationState.idle) {
        // Clear the scheduled time and show prompt
        setState(() {
          _scheduledMeditationTime = null;
        });
        _showStressPrompt();
      }
      _pendingStressPromptTimer = null;
    });
  }

  void _showCompletionDialogWithMoodCheck() {
    // Prevent immediate stress re-detection after completion
    setState(() {
      _stressDetected = false;
    });

    // Add 2-minute cooldown before checking stress again
    Future.delayed(const Duration(minutes: 2), () {
      if (mounted) {
        setState(() {
          _stressDetected = false;
        });
      }
    });

    // Calculate stress reduction as average of HR reduction and HRV improvement.
    // HR reduction: how much HR dropped relative to baseline (BPM → %).
    // HRV improvement: how much RMSSD increased relative to baseline (ms → %).
    // Each component is clamped to [0, 100] before averaging, so the result
    // is also in [0, 100] with no further cap needed.
    final hrChange = _baselineHr > 0
        ? ((_baselineHr - _currentHr) / _baselineHr * 100).clamp(0.0, 100.0)
        : 0.0;
    final hrvChange = _baselineHrv > 0
        ? ((_currentHrv - _baselineHrv) / _baselineHrv * 100).clamp(0.0, 100.0)
        : 0.0;

    final double stressReduction = (hrChange + hrvChange) / 2;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final isDemo = widget.demoMode != DemoConfig.modeNone;
        final isTimerMode = !widget.stressDetectionEnabled && !isDemo;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.celebration, color: Colors.green),
              const SizedBox(width: 8),
              Text(isDemo ? 'Great!' : 'Great, ${_userAccount?.name ?? ""}!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your body has calmed down.',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 16),
              if (!isDemo && !isTimerMode) ...[
                const Text(
                  '💭 Stress monitoring is paused for 2 minutes to let you enjoy this calm state.',
                  style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey),
                ),
                const SizedBox(height: 20),
              ],
              if (!isDemo && !isTimerMode) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Before:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('❤️  ${_baselineHr.toStringAsFixed(0)} BPM',
                              style: const TextStyle(fontSize: 13)),
                          Text('📊 ${_baselineHrv.toStringAsFixed(0)} ms',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('After:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('❤️  ${_currentHr.toStringAsFixed(0)} BPM',
                              style: const TextStyle(fontSize: 13)),
                          Text('📊 ${_currentHrv.toStringAsFixed(0)} ms',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'How do you feel right now?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildMoodButton('😌', 'Very Relaxed',
                        MoodRating.veryRelaxed, stressReduction),
                    SizedBox(width: 4),
                    _buildMoodButton(
                        '😊', 'Relaxed', MoodRating.relaxed, stressReduction),
                    SizedBox(width: 4),
                    _buildMoodButton(
                        '😐', 'Neutral', MoodRating.neutral, stressReduction),
                    SizedBox(width: 4),
                    _buildMoodButton(
                        '😟', 'Stressed', MoodRating.stressed, stressReduction),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMoodButton(
      String emoji, String label, MoodRating mood, double stressReduction) {
    return InkWell(
      onTap: () async {
        if (widget.demoMode != DemoConfig.modeNone) {
          // Demo mode: dismiss dialog, stop sensors, return to demo selection
          Navigator.pop(context);
          if (mounted) {
            widget.onReset?.call();
          }
          return;
        }

        // Normal mode: save mood and offer analytics
        final entry = MoodEntry(
          timestamp: DateTime.now(),
          mood: mood,
          stressReduction: stressReduction,
          sessionDuration: _sessionElapsed,
        );
        await MoodHistory.saveMood(entry);

        if (!mounted) return;

        Navigator.pop(context);

        // Show completion message with option to view analysis
        if (!mounted) return;

        final viewAnalysis = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Session Saved!'),
              ],
            ),
            content: Text(
                '$emoji Thank you for sharing! Your session has been recorded.\n\nWould you like to view your weekly progress?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Later'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.insights),
                label: const Text('View Analysis'),
              ),
            ],
          ),
        );

        if (viewAnalysis == true && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const WeeklyAnalysisScreen(),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Build calibration progress indicator
  List<Widget> _buildCalibrationIndicator() {
    // Check if controller is calibrating
    final calibrationInfo = _controller?.getCurrentBiosignals();
    final isCalibrating = calibrationInfo?['isCalibrating'] == true;
    final calibrationProgress =
        calibrationInfo?['calibrationProgress']?.toInt() ?? 0;

    if (!isCalibrating) {
      return []; // No indicator if not calibrating
    }

    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.biotech, size: 16, color: Colors.amber[800]),
                const SizedBox(width: 8),
                Text(
                  'Calibrating Your Baseline',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.amber[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: calibrationProgress / 100,
              backgroundColor: Colors.amber.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(Colors.amber[700]!),
            ),
            const SizedBox(height: 6),
            Text(
              'Refining demographics-based estimate with your actual measurements...',
              style: TextStyle(
                fontSize: 11,
                color: Colors.amber[900],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isInitializing || _controller == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing meditation...'),
          ],
        ),
      );
    }

    // Show meditation UI
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Session info card with smooth transitions
          AnimatedSwitcher(
            duration: const Duration(
                milliseconds: 150), // Reduced from 300ms for consistency
            child: (_currentState == MeditationState.speaking ||
                    _currentState == MeditationState.waitingForBiosignals ||
                    _currentState == MeditationState.paused ||
                    _currentState == MeditationState.generatingContent)
                ? Card(
                    key: const ValueKey('session_info_card'),
                    color: colorScheme.primary,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _currentState == MeditationState.paused
                                    ? Icons.pause
                                    : Icons.spa,
                                color: colorScheme.onPrimary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _currentState == MeditationState.paused
                                    ? 'Paused'
                                    : 'Meditating...',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Calibration progress indicator (biosignal modes only)
                          if (widget.stressDetectionEnabled &&
                              _controller != null)
                            ..._buildCalibrationIndicator(),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Timer
                              Icon(Icons.timer,
                                  size: 16,
                                  color: colorScheme.onPrimary
                                      .withValues(alpha: 0.9)),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(_sessionElapsed),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onPrimary
                                      .withValues(alpha: 0.9),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Segment counter
                              Icon(Icons.layers,
                                  size: 16,
                                  color: colorScheme.onPrimary
                                      .withValues(alpha: 0.9)),
                              const SizedBox(width: 4),
                              Text(
                                _currentSegment > 0
                                    ? 'Segment $_currentSegment of ~$_totalSegments'
                                    : 'Preparing...',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onPrimary
                                      .withValues(alpha: 0.9),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('session_info_empty')),
          ),

          if (_currentState == MeditationState.speaking ||
              _currentState == MeditationState.waitingForBiosignals ||
              _currentState ==
                  MeditationState
                      .generatingContent || // KEEP BUTTONS VISIBLE during generation!
              _currentState == MeditationState.paused)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _currentState == MeditationState.paused
                        ? _resumeMeditation
                        : _pauseMeditation,
                    icon: Icon(_currentState == MeditationState.paused
                        ? Icons.play_arrow
                        : Icons.pause),
                    label: Text(_currentState == MeditationState.paused
                        ? 'Resume'
                        : 'Pause'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _stopMeditation,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer,
                      foregroundColor: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),

          // API Warning Banner (if APIs not configured)
          // Hidden in timer mode — the parent screen shows it below the timer card.
          if (_currentState == MeditationState.idle &&
              !_hasConfiguredGeminiKey &&
              widget.stressDetectionEnabled)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'API Not Configured',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                        Text(
                          'Using fallback mode. Open API Keys from the menu to add a runtime key.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSecondaryContainer
                                .withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<bool> _attemptMeditationStart() async {
    final canStart = await widget.onBeforeStartMeditation?.call() ?? true;
    if (!mounted || !canStart || _currentState != MeditationState.idle) {
      return false;
    }
    _startMeditation();
    return true;
  }

  void _startMeditation() {
    // Clear any scheduled meditation time when user starts a meditation
    setState(() {
      _scheduledMeditationTime = null;
    });
    _controller?.startSession();
  }

  void _handleStressDetected(bool isStressed) {
    if (!widget.stressDetectionEnabled) {
      if (_stressDetected) {
        setState(() {
          _stressDetected = false;
        });
      }
      return;
    }

    final now = DateTime.now();
    final inBusinessMeeting = _meetingBlocker?.isInMeeting ?? false;

    if (inBusinessMeeting) {
      if (_stressDetected) {
        setState(() {
          _stressDetected = false;
        });
        widget.onStressLevelChanged?.call('relaxed');
      }
      return;
    }

    final beforeScheduledTime = _scheduledMeditationTime != null &&
        now.isBefore(_scheduledMeditationTime!);
    final inCooldown = _lastMeditationCompletionTime != null &&
        now.difference(_lastMeditationCompletionTime!).inMinutes < 2;

    print('\n=== STRESS CALLBACK ===');
    print('isStressed: $isStressed');
    print('_stressDetected: $_stressDetected');
    print('_currentState: $_currentState');
    print('inCooldown: $inCooldown');
    print('beforeScheduledTime: $beforeScheduledTime');
    print('inBusinessMeeting: $inBusinessMeeting');
    print('_lastMeditationCompletionTime: $_lastMeditationCompletionTime');
    print('_scheduledMeditationTime: $_scheduledMeditationTime');
    print('=====================\n');

    if (isStressed &&
        !_stressDetected &&
        _currentState == MeditationState.idle) {
      setState(() {
        _stressDetected = true;
      });
      widget.onStressLevelChanged?.call('stressed');
      print('✓ Set _stressDetected=true');
      if (!inCooldown && !beforeScheduledTime) {
        print('✓✓✓ SHOWING STRESS PROMPT!');
        _showStressPrompt();
      } else {
        print(
            '✗ Not showing prompt - inCooldown=$inCooldown, beforeScheduledTime=$beforeScheduledTime');
      }
    } else {
      if (isStressed) {
        print('✗ Stress detected but NOT showing prompt because:');
        if (_stressDetected) print('  - _stressDetected is already true');
        if (_currentState != MeditationState.idle) {
          print('  - state is $_currentState (not idle)');
        }
      }

      if (!isStressed && _stressDetected) {
        print(
            'Stress cleared - resetting _stressDetected only (keeping schedule)');
        setState(() {
          _stressDetected = false;
          // DON'T clear _scheduledMeditationTime here!
          // If user said "Later (30 min)", that schedule should persist
          // even if stress goes away temporarily
        });
        widget.onStressLevelChanged?.call('relaxed');
      }
    }
  }

  void _pauseMeditation() {
    _controller?.pauseSession();
  }

  void _stopMeditation() async {
    await _controller?.stopSession();

    if (!mounted) return;

    // Show dismissal options
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Session Stopped'),
        content: const Text(
            'Would you like to be reminded to meditate if stress is detected later?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _stressDetected = false;
                _lastMeditationCompletionTime = DateTime.now()
                    .add(Duration(days: 1)); // Disable for whole day
              });
            },
            child: const Text('Leave me alone today'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _scheduleDelayedMeditation(Duration(minutes: 30));
            },
            child: const Text('Remind in 30 min'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _scheduleDelayedMeditation(Duration(minutes: 10));
            },
            child: const Text('Remind in 10 min'),
          ),
        ],
      ),
    );
  }

  void _resumeMeditation() {
    _controller?.resumeSession();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
