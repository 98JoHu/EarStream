import 'package:flutter/material.dart';
import '../model/improved_meditation_controller.dart';
import '../model/improved_meditation_llm_service.dart';
import '../model/meditation_voice_service.dart';
import '../model/meditation_config.dart';
import '../model/user_account.dart';
import '../model/user_meditation_profile.dart';
import '../model/hr_sensor_interface.dart';
import '../model/mood_entry.dart';
import '../model/meditation_cache.dart';
import '../widgets/user_onboarding_screen.dart';
import '../widgets/weekly_analysis_screen.dart';
import '../widgets/api_debug_widget.dart';
import 'breathing_animation.dart';

/// Improved meditation widget with natural voice and personalization
class LlmMeditationWidget extends StatefulWidget {
  final HrSensorInterface sensor;
  final VoidCallback? onReset;
  final void Function(String stressLevel)? onStressLevelChanged;
  
  const LlmMeditationWidget({
    super.key,
    required this.sensor,
    this.onReset,
    this.onStressLevelChanged,
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
  int _currentSegment = 0;
  int _totalSegments = 10;
  Duration _sessionElapsed = Duration.zero;
  
  // Services owned by this widget
  MeditationVoiceService? _voiceService;
  ImprovedMeditationLLMService? _llmService;
  
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
    print('🔄 LlmMeditationWidget._initialize() called with sensor: ${widget.sensor.runtimeType}');
    
    // NOTE: Cache auto-clear disabled now that regex bug is fixed
    // Cache will self-heal (deletes corrupted files < 1KB automatically)
    // Cache expires after 7 days
    // If issues recur, uncomment the lines below:
    // print('🗑️ Clearing TTS cache on startup...');
    // await MeditationCache.clearAllCache();
    
    // Load user account (primary source of truth)
    final account = await UserAccount.load();
    print('🔍 LOADED ACCOUNT: name="${account.name}", voice=${account.voiceGender}, style=${account.meditationStyle}');
    
    if (!account.isSetup && mounted) {
      // Show onboarding
      final newAccount = await Navigator.push<UserAccount>(
        context,
        MaterialPageRoute(builder: (context) => UserOnboardingScreen()),
      );
      
      if (newAccount != null) {
        setState(() {
          _userAccount = newAccount;
        });
      } else {
        // User cancelled, use default
        setState(() {
          _userAccount = account;
        });
      }
    } else {
      setState(() {
        _userAccount = account;
        _currentSegment = 0; // Reset segment UI
        _sessionElapsed = Duration.zero; // Reset timer UI
        _stressDetected = false; // Reset stress flag
      });
    }
    
    // Initialize services
    _voiceService = MeditationVoiceService();
    await _voiceService!.initialize(
      voiceGender: _userAccount!.voiceGender,
      meditationStyle: _userAccount!.meditationStyle,
      usePremiumVoice: _userAccount!.usePremiumVoice,
    );
    print('✅ Voice service initialized: gender=${_userAccount!.voiceGender.toUpperCase()}, style=${_userAccount!.meditationStyle}, premium=${_userAccount!.usePremiumVoice}');
    
    _llmService = ImprovedMeditationLLMService();
    _llmService!.setUserAccount(_userAccount!);
    
    // Create controller
    print('🎯 Creating ImprovedMeditationController with sensor: ${widget.sensor.runtimeType}');
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
        _lastMeditationCompletionTime = DateTime.now(); // Record completion time
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
      onStressDetected: (isStressed) {
        // Check if we're in cooldown period (2 minutes after last meditation)
        final now = DateTime.now();
        
        // Check if meditation is scheduled - don't prompt before scheduled time
        final beforeScheduledTime = _scheduledMeditationTime != null &&
            now.isBefore(_scheduledMeditationTime!);
        
        // Check if we're in cooldown period (2 minutes after last meditation)
        final inCooldown = _lastMeditationCompletionTime != null &&
            now.difference(_lastMeditationCompletionTime!).inMinutes < 2;
        
        print('\n=== STRESS CALLBACK ===');
        print('isStressed: $isStressed');
        print('_stressDetected: $_stressDetected');
        print('_currentState: $_currentState');
        print('inCooldown: $inCooldown');
        print('beforeScheduledTime: $beforeScheduledTime');
        print('_lastMeditationCompletionTime: $_lastMeditationCompletionTime');
        print('_scheduledMeditationTime: $_scheduledMeditationTime');
        print('=====================\n');
        
        // Always update stress state, but only auto-prompt if appropriate
        if (isStressed && !_stressDetected && _currentState == MeditationState.idle) {
          setState(() {
            _stressDetected = true;
          });
          // Notify parent of stress level change
          widget.onStressLevelChanged?.call('stressed');
          print('✓ Set _stressDetected=true');
          // Only show prompt if not in cooldown AND not before scheduled time
          if (!inCooldown && !beforeScheduledTime) {
            print('✓✓✓ SHOWING STRESS PROMPT!');
            _showStressPrompt();
          } else {
            print('✗ Not showing prompt - inCooldown=$inCooldown, beforeScheduledTime=$beforeScheduledTime');
          }
        } else {
          if (isStressed) {
            print('✗ Stress detected but NOT showing prompt because:');
            if (_stressDetected) print('  - _stressDetected is already true');
            if (_currentState != MeditationState.idle) print('  - state is $_currentState (not idle)');
          }
          
          if (!isStressed && _stressDetected) {
            print('Stress cleared - resetting _stressDetected only (keeping schedule)');
            setState(() {
              _stressDetected = false;
              // DON'T clear _scheduledMeditationTime here!
              // If user said "Later (30 min)", that schedule should persist
              // even if stress goes away temporarily
            });
            // Notify parent that stress cleared
            widget.onStressLevelChanged?.call('normal');
          }
        }
      },
    );
    
    setState(() {
      _isInitializing = false;
      _statusMessage = 'Monitoring your vitals...';
    });
    
    // Start monitoring
    _controller!.startMonitoring();
  }
  
  @override
  void dispose() {
    _controller?.dispose();
    _voiceService?.dispose();
    _llmService?.dispose();
    super.dispose();
  }
  
  Future<void> resetMeditation() async {
    print('🔄 RESET MEDITATION: Stopping current session and reinitializing...');
    
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
      print('🔄 Recreating controller with premium voice: ${_userAccount!.usePremiumVoice}');
      
      _voiceService = MeditationVoiceService();
      await _voiceService!.initialize(
        voiceGender: _userAccount!.voiceGender,
        meditationStyle: _userAccount!.meditationStyle,
        usePremiumVoice: _userAccount!.usePremiumVoice,
      );
      print('✅ Voice service reinitialized after reset: premium=${_userAccount!.usePremiumVoice}');
      
      _llmService = ImprovedMeditationLLMService();
      _llmService!.setUserAccount(_userAccount!);
      
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
        onStressDetected: (isStressed) {
          final now = DateTime.now();
          final beforeScheduledTime = _scheduledMeditationTime != null &&
              now.isBefore(_scheduledMeditationTime!);
          
          if (beforeScheduledTime) {
            return;
          }
          
          final inCooldown = _lastMeditationCompletionTime != null &&
              now.difference(_lastMeditationCompletionTime!).inMinutes < 2;
          
          if (inCooldown) {
            return;
          }
          
          if (isStressed && !_stressDetected && _currentState == MeditationState.idle) {
            setState(() {
              _stressDetected = true;
            });
          }
          
          if (!isStressed && _stressDetected) {
            setState(() {
              _stressDetected = false;
              // DON'T clear _scheduledMeditationTime - keep the schedule!
            });
          }
        },
      );
      
      print('✅ Controller recreated successfully after reset');
    }
    
    // Don't call widget.onReset here - it's called by the parent already
    // This prevents infinite loop when parent calls resetMeditation()
  }
  
  Future<void> updateSettings(UserAccount updatedAccount) async {
    print('🔄 UPDATE SETTINGS CALLED: voiceGender=${updatedAccount.voiceGender.toUpperCase()}, env=${updatedAccount.preferredEnvironment}, style=${updatedAccount.meditationStyle}');
    
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
    
    // Initialize new services with updated account
    _voiceService = MeditationVoiceService();
    await _voiceService!.initialize(
      voiceGender: _userAccount!.voiceGender,
      meditationStyle: _userAccount!.meditationStyle,
      usePremiumVoice: _userAccount!.usePremiumVoice,
    );
    print('✅ Voice service RE-initialized: gender=${_userAccount!.voiceGender.toUpperCase()}, style=${_userAccount!.meditationStyle}, premium=${_userAccount!.usePremiumVoice}');
    
    _llmService = ImprovedMeditationLLMService();
    _llmService!.setUserAccount(_userAccount!);
    
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
              _baselineHr = _controller?.getCurrentBiosignals()['baselineHr'] ?? hr;
              _baselineHrv = _controller?.getCurrentBiosignals()['baselineHrv'] ?? hrv;
            });
          }
        }
      },
      onSegmentUpdate: (current, total) {
        if (mounted && (_currentSegment != current || _totalSegments != total)) {
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
      onStressDetected: (isStressed) {
        final now = DateTime.now();
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
        print('=====================\n');
        
        if (isStressed && !_stressDetected && _currentState == MeditationState.idle) {
          setState(() {
            _stressDetected = true;
          });
          print('✓ Set _stressDetected=true');
          if (!inCooldown && !beforeScheduledTime) {
            print('✓✓✓ SHOWING STRESS PROMPT!');
            _showStressPrompt();
          } else {
            print('✗ Not showing prompt - inCooldown=$inCooldown, beforeScheduledTime=$beforeScheduledTime');
          }
        } else {
          if (isStressed) {
            print('✗ Stress detected but NOT showing prompt because:');
            if (_stressDetected) print('  - _stressDetected is already true');
            if (_currentState != MeditationState.idle) print('  - state is $_currentState (not idle)');
          }
          
          if (!isStressed && _stressDetected) {
            print('Stress cleared - resetting _stressDetected only (keeping schedule)');
            setState(() {
              _stressDetected = false;
              // DON'T clear _scheduledMeditationTime - keep the schedule!
            });
          }
        }
      },
    );
    
    setState(() {
      _isInitializing = false;
      _statusMessage = 'Monitoring your vitals...';
    });
    
    // Start monitoring
    _controller!.startMonitoring();
    
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
                _scheduledMeditationTime = DateTime.now().add(Duration(days: 1));
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
            onPressed: () {
              Navigator.pop(context);
              _startMeditation();
            },
            child: const Text('Yes, Start Now'),
          ),
        ],
      ),
    );
  }
  
  void _scheduleDelayedMeditation(Duration delay) {
    final scheduledTime = DateTime.now().add(delay);
    setState(() {
      _statusMessage = 'Meditation scheduled in ${delay.inMinutes} minutes';
      _stressDetected = false;
      _scheduledMeditationTime = scheduledTime;
    });
    
    Future.delayed(delay, () {
      if (mounted && _currentState == MeditationState.idle) {
        // Clear the scheduled time and show prompt
        setState(() {
          _scheduledMeditationTime = null;
        });
        _showStressPrompt();
      }
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
    
    // Calculate stress reduction more conservatively
    // Use the max of HR reduction and HRV increase, capped at 100%
    double hrChange = _baselineHr > 0 ? ((_baselineHr - _currentHr) / _baselineHr * 100) : 0.0;
    double hrvChange = _baselineHrv > 0 ? ((_currentHrv - _baselineHrv) / _baselineHrv * 100) : 0.0;
    
    // Sometimes baseline is captured when already relaxed, leading to 0% or negative.
    // Ensure we don't show negative improvement for "Stress Reduction".
    if (hrChange < 0) hrChange = 0;
    if (hrvChange < 0) hrvChange = 0;

    double stressReduction = (hrChange + hrvChange) / 2;
    if (stressReduction > 100) stressReduction = 99.0; // Cap at 99% logic
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.celebration, color: Colors.green),
            const SizedBox(width: 8),
            Text('Great, ${_userAccount?.name ?? ""}!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'ve achieved ${stressReduction.toStringAsFixed(0)}% stress reduction in ${_sessionElapsed.inMinutes} minutes.',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 16),
            const Text(
              '💭 Stress monitoring is paused for 2 minutes to let you enjoy this calm state.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Before:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('❤️  ${_baselineHr.toStringAsFixed(0)} BPM', style: const TextStyle(fontSize: 13)),
                      Text('📊 ${_baselineHrv.toStringAsFixed(0)} ms', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('After:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('❤️  ${_currentHr.toStringAsFixed(0)} BPM', style: const TextStyle(fontSize: 13)),
                      Text('📊 ${_currentHrv.toStringAsFixed(0)} ms', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
                  _buildMoodButton('😌', 'Very Relaxed', MoodRating.veryRelaxed, stressReduction),
                  SizedBox(width: 4),
                  _buildMoodButton('😊', 'Relaxed', MoodRating.relaxed, stressReduction),
                   SizedBox(width: 4),
                  _buildMoodButton('😐', 'Neutral', MoodRating.neutral, stressReduction),
                   SizedBox(width: 4),
                  _buildMoodButton('😟', 'Stressed', MoodRating.stressed, stressReduction),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMoodButton(String emoji, String label, MoodRating mood, double stressReduction) {
    return InkWell(
      onTap: () async {
        // Save mood entry
        final entry = MoodEntry(
          timestamp: DateTime.now(),
          mood: mood,
          stressReduction: stressReduction,
          sessionDuration: _sessionElapsed,
        );
        await MoodHistory.saveMood(entry);
        
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
            content: Text('$emoji Thank you for sharing! Your session has been recorded.\n\nWould you like to view your weekly progress?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Later'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.insights),
                label: const Text('View Analysis'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
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
  
  /// Build calibration progress indicator (DISABLED - instant research baseline now used)
  List<Widget> _buildCalibrationIndicator() {
    // Calibration indicator removed - we now use instant research-based baselines
    // No need to show "Calibrating..." since we start immediately with research values
    return [];
  }
  
  @override
  Widget build(BuildContext context) {
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
            duration: const Duration(milliseconds: 150), // Reduced from 300ms for consistency
            child: (_currentState == MeditationState.speaking || 
                    _currentState == MeditationState.waitingForBiosignals ||
                    _currentState == MeditationState.paused ||
                    _currentState == MeditationState.generatingContent)
              ? Card(
                  key: const ValueKey('session_info_card'),
                  color: Colors.indigo,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _currentState == MeditationState.paused ? Icons.pause : Icons.spa,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _currentState == MeditationState.paused ? 'Paused' : 'Meditating...',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // Calibration progress indicator (now disabled)
                        if (_controller != null) ..._buildCalibrationIndicator(),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Timer
                            Icon(Icons.timer, size: 16, color: Colors.white.withOpacity(0.9)),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(_sessionElapsed),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Segment counter
                            Icon(Icons.layers, size: 16, color: Colors.white.withOpacity(0.9)),
                            const SizedBox(width: 4),
                            Text(
                              _currentSegment > 0 ? 'Segment $_currentSegment of ~$_totalSegments' : 'Preparing...',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withOpacity(0.9),
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
          
          // Use AnimatedSwitcher to prevent flickering when state changes
          // Keep breathing animation visible during content generation to prevent flicker
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150), // Reduced from 300ms for snappier feel
            child: (_currentState == MeditationState.speaking || 
                    _currentState == MeditationState.waitingForBiosignals ||
                    _currentState == MeditationState.generatingContent || // KEEP VISIBLE during generation!
                    _currentState == MeditationState.paused)
              ? Column(
                  key: const ValueKey('meditation_breathing'),
                  children: [
                    const SizedBox(height: 16),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: BreathingAnimation(
                          isActive: _currentState == MeditationState.speaking || 
                                   _currentState == MeditationState.generatingContent, // Keep animating during generation
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                )
              : const SizedBox.shrink(key: ValueKey('meditation_empty')),
          ),
          
          if (_currentState == MeditationState.speaking ||
              _currentState == MeditationState.waitingForBiosignals ||
              _currentState == MeditationState.generatingContent || // KEEP BUTTONS VISIBLE during generation!
              _currentState == MeditationState.paused)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _currentState == MeditationState.paused ? _resumeMeditation : _pauseMeditation,
                    icon: Icon(_currentState == MeditationState.paused ? Icons.play_arrow : Icons.pause),
                    label: Text(_currentState == MeditationState.paused ? 'Resume' : 'Pause'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _stopMeditation,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          
          // API Warning Banner (if APIs not configured)
          if (_currentState == MeditationState.idle && !MeditationConfig.hasValidGeminiKey)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange, width: 2),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange[800]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'API Not Configured',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[900],
                          ),
                        ),
                        Text(
                          'Using fallback mode. Tap "Check API Keys" to fix.',
                          style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          // Weekly Analysis Button (when idle or completed)
          if (_currentState == MeditationState.idle || _currentState == MeditationState.completed)
            Column(
              children: [
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WeeklyAnalysisScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.insights),
                  label: const Text('View Weekly Analysis'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
  
  void _startMeditation() {
    // Clear any scheduled meditation time when user starts a meditation
    setState(() {
      _scheduledMeditationTime = null;
    });
    _controller?.startSession();
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
        content: const Text('Would you like to be reminded to meditate if stress is detected later?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _stressDetected = false;
                _lastMeditationCompletionTime = DateTime.now().add(Duration(days: 1)); // Disable for whole day
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
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
