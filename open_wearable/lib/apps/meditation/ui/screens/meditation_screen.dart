import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/apps/meditation/ui/shared/earstream_style.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import '../../core/biosignals/sensors/mock_hr_sensor.dart';
import '../../core/biosignals/sensors/earable_hr_sensor.dart';
import '../../core/biosignals/sensors/hr_sensor_interface.dart';
import '../../core/biosignals/activity_detector.dart';
import '../components/biosignal_display/hr_hrv_display_new.dart';
import '../components/meditation_session/llm_meditation_widget.dart';
import '../components/debug/api_debug_widget.dart';
import 'weekly_analysis_screen.dart';
import '../../models/user_account.dart';
import 'settings/earstream_settings_pages.dart';

class MeditationView extends StatefulWidget {
  final Sensor? ppgSensor;
  final SensorConfigurationProvider? sensorConfigProvider;
  final SensorManager sensorManager;
  final Wearable? wearable; // Added connection monitoring

  const MeditationView({
    super.key,
    this.ppgSensor,
    this.sensorConfigProvider,
    required this.sensorManager,
    this.wearable,
  });

  @override
  State<MeditationView> createState() => _MeditationViewState();
}

enum MeditationAppMode { normal, timer, test }

class _MeditationViewState extends State<MeditationView> {
  HrSensorInterface? _sensor;
  bool _useMockSensor = true;
  GlobalKey<LlmMeditationWidgetState> _meditationWidgetKey =
      GlobalKey<LlmMeditationWidgetState>();
  MeditationAppMode _selectedMode = MeditationAppMode.normal;
  bool _earStreamActivated = false;
  Timer? _timerModeTimer;
  DateTime? _timerModeScheduledTime;

  double _currentHr = 75.0;
  double _currentHrv = -1.0; // -1 means no data yet (RMSSD)
  double _currentSdnn =
      -1.0; // -1 means no data yet (SDNN - comparable to Apple Health)
  bool _hrvIsStable = false; // Track if HRV measurements are reliable
  int _hrvMeasurementCount = 0; // Count HRV measurements received
  int _measurementDurationSeconds = 0; // Track how long we've been measuring
  Timer? _measurementTimer; // Timer to track measurement duration

  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<Map<String, double>>? _hrvSubscription;
  StreamSubscription<bool>? _connectionSubscription; // Monitor connection state

  String _stressLevel =
      'normal'; // Track stress level: 'relaxed', 'normal', or 'stressed'

  void _recreateMeditationWidgetKey() {
    _meditationWidgetKey = GlobalKey<LlmMeditationWidgetState>();
  }

  void _setMode(MeditationAppMode mode) {
    if (_selectedMode == mode) {
      return;
    }
    setState(() {
      _selectedMode = mode;
      if (mode != MeditationAppMode.timer) {
        _clearTimerModeSchedule();
      }
    });
  }

  void _clearTimerModeSchedule() {
    _timerModeTimer?.cancel();
    _timerModeTimer = null;
    _timerModeScheduledTime = null;
  }

  void _activateEarStream() {
    if (_earStreamActivated) {
      return;
    }

    setState(() {
      _earStreamActivated = true;
    });
  }

  Future<DateTime?> _scheduleTimerModeAfter(Duration delay) async {
    final scheduled = DateTime.now().add(delay);
    return _scheduleTimerModeAt(
      scheduled,
      description: 'in ${delay.inMinutes} min',
    );
  }

  Future<DateTime?> _pickAndScheduleTimerModeTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (time == null || !mounted) {
      return null;
    }

    final now = DateTime.now();
    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return _scheduleTimerModeAt(
      scheduled,
      description: 'at ${time.format(context)}',
    );
  }

  DateTime? _scheduleTimerModeAt(DateTime scheduledTime,
      {required String description}) {
    if (!_earStreamActivated) {
      _showErrorDialog(
        'Click Start EarStreAM on the main page before scheduling a timed session.',
      );
      return null;
    }

    final now = DateTime.now();
    final delay = scheduledTime.difference(now);
    if (delay <= Duration.zero) {
      _showErrorDialog('Scheduled time must be in the future.');
      return null;
    }

    _clearTimerModeSchedule();
    setState(() {
      _timerModeScheduledTime = scheduledTime;
    });

    _timerModeTimer = Timer(delay, () async {
      if (!mounted) {
        return;
      }

      setState(() {
        _timerModeScheduledTime = null;
      });

      final meditationState = _meditationWidgetKey.currentState;
      if (meditationState == null) {
        _showErrorDialog(
            'Meditation widget is not ready yet. Please try again.');
        return;
      }

      if (!meditationState.isIdle) {
        _showSuccessSnackbar('Timer ended, but a session is already running.');
        return;
      }

      final started = await meditationState.startMeditationNowFromExternal();
      if (started && mounted) {
        _showSuccessSnackbar('Timer meditation started ($description).');
      }
    });
    return scheduledTime;
  }

  String _formatScheduledTime(DateTime scheduledTime) {
    final now = DateTime.now();
    final isToday = now.year == scheduledTime.year &&
        now.month == scheduledTime.month &&
        now.day == scheduledTime.day;
    final hour = scheduledTime.hour.toString().padLeft(2, '0');
    final minute = scheduledTime.minute.toString().padLeft(2, '0');
    return isToday ? 'Today $hour:$minute' : 'Tomorrow $hour:$minute';
  }

  Widget _buildModeSelector({
    required MeditationAppMode selectedMode,
    required ValueChanged<MeditationAppMode> onModeSelected,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meditation Mode',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Biosignal-Adaptive'),
                  selected: selectedMode == MeditationAppMode.normal,
                  onSelected: (_) => onModeSelected(MeditationAppMode.normal),
                ),
                ChoiceChip(
                  label: const Text('Timed'),
                  selected: selectedMode == MeditationAppMode.timer,
                  onSelected: (_) => onModeSelected(MeditationAppMode.timer),
                ),
                ChoiceChip(
                  label: const Text('Demo'),
                  selected: selectedMode == MeditationAppMode.test,
                  onSelected: (_) => onModeSelected(MeditationAppMode.test),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerModeCard({
    required DateTime? scheduledTime,
    required Future<void> Function(Duration delay) onScheduleAfter,
    required Future<void> Function() onPickTime,
    required VoidCallback onCancelSchedule,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timed meditation',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Schedule a meditation by delay or at a specific clock time.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => onScheduleAfter(const Duration(minutes: 5)),
                  child: const Text('After 5 min'),
                ),
                OutlinedButton(
                  onPressed: () => onScheduleAfter(const Duration(minutes: 10)),
                  child: const Text('After 10 min'),
                ),
                OutlinedButton(
                  onPressed: () => onScheduleAfter(const Duration(minutes: 30)),
                  child: const Text('After 30 min'),
                ),
                ElevatedButton.icon(
                  onPressed: onPickTime,
                  icon: const Icon(Icons.schedule),
                  label: const Text('Pick Time'),
                ),
              ],
            ),
            if (scheduledTime != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.timer_outlined, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scheduled for ${_formatScheduledTime(scheduledTime)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: onCancelSchedule,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTestModePlaceholder({
    required VoidCallback onRunPlaceholderAction,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Demo mode',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This area can host scripted scenarios, placeholder actions, or QA checks without showing the meditation playback UI.',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRunPlaceholderAction,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Run Placeholder Action'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeSensor();
  }

  bool get _hasEarableSensorAvailable =>
      widget.ppgSensor != null && widget.wearable != null;

  Future<void> _initializeSensor() async {
    // Don't reinitialize if sensor is already set
    // (e.g., after switching to earable sensor)
    if (_sensor != null) {
      print(
          'Sensor already initialized ($_sensor.runtimeType), skipping initialization');
      return;
    }

    if (_hasEarableSensorAvailable) {
      print('Starting with earable sensor');
      final initialized = await _switchToEarableSensor(showFeedback: false);
      if (initialized) {
        return;
      }
      print('Earable init failed, falling back to mock sensor');
    }

    // Fallback to mock sensor when no earable is available.
    print('Starting with mock sensor');
    _sensor = MockHrSensor();
    _useMockSensor = true;

    // Ensure sensor is started before monitoring begins
    print('>>> Starting mock sensor...');
    await _sensor!.start();
    print('✓ Mock sensor started');

    _startMonitoring();
  }

  /// Configure PPG sensor for streaming
  /// This is called on initial connection and when earable reconnects
  Future<void> _configurePpgSensor() async {
    if (widget.ppgSensor == null || widget.sensorConfigProvider == null) {
      print('Cannot configure PPG sensor - sensor or config provider is null');
      return;
    }

    print('Configuring PPG sensor...');
    final sensor = widget.ppgSensor!;
    final configProvider = widget.sensorConfigProvider!;

    try {
      SensorConfiguration configuration = sensor.relatedConfigurations.first;

      // Stream-Option aktivieren
      if (configuration is ConfigurableSensorConfiguration &&
          configuration.availableOptions.contains(StreamSensorConfigOption())) {
        configProvider.addSensorConfigurationOption(
            configuration, StreamSensorConfigOption());
        print('Added stream configuration option');
      }

      // Konfiguration setzen - WICHTIG: Nur "stream" Modi, NICHT "off"!
      List<SensorConfigurationValue> values = configProvider
          .getSensorConfigurationValues(configuration, distinct: true);

      // Filter for streaming configurations (exclude "off" modes)
      final streamingValues = values.where((v) {
        final str = v.toString().toLowerCase();
        return str.contains('stream') && !str.contains('off');
      }).toList();

      if (streamingValues.isEmpty) {
        print('No streaming PPG configuration found! Available: $values');
        // Fallback to first value if no streaming config found
        configProvider.addSensorConfiguration(configuration, values.first);
      } else {
        print(
            'Found ${streamingValues.length} streaming PPG configs: $streamingValues');
        // Use the first streaming configuration
        configProvider.addSensorConfiguration(
            configuration, streamingValues.first);
      }

      SensorConfigurationValue selectedValue =
          configProvider.getSelectedConfigurationValue(configuration)!;

      // KRITISCH: Sensor konfigurieren!
      configuration.setConfiguration(selectedValue);
      print('Set sensor configuration: $selectedValue');

      // Sensor initialization is asynchronous, wait for stream to be ready
      // The configuration is applied asynchronously, so we need to wait
      print('Waiting 500ms for PPG sensor to start streaming...');
      await Future.delayed(Duration(milliseconds: 500));
      print('PPG sensor configured and should be streaming now');
    } catch (e) {
      print('ERROR configuring PPG sensor: $e');
    }
  }

  Future<bool> _switchToEarableSensor({bool showFeedback = true}) async {
    if (widget.ppgSensor == null) {
      if (showFeedback) {
        _showErrorDialog(
            'No earable device connected. Please connect an OpenEarable device first.');
      }
      return false;
    }

    print('Switching to earable sensor...');

    // Stop current sensor
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _connectionSubscription?.cancel();
    _sensor?.dispose();

    // Configure PPG sensor
    await _configurePpgSensor();

    // Get sample frequency from sensor configuration
    double sampleFreq = 84.0; // Default to 84 Hz for PPG
    if (widget.sensorConfigProvider != null) {
      for (final config in widget.ppgSensor!.relatedConfigurations) {
        final value =
            widget.sensorConfigProvider!.getSelectedConfigurationValue(config);
        if (value is SensorFrequencyConfigurationValue) {
          sampleFreq = value.frequencyHz;
          print('Using sample frequency: $sampleFreq Hz');
          break;
        }
      }
    }

    // Create real sensor
    if (widget.wearable == null) {
      if (showFeedback) {
        _showErrorDialog('Internal Error: Wearable instance not found.');
      }
      return false;
    }

    print('=== CREATING EARABLE SENSOR ===');
    print('PPG Sensor: ${widget.ppgSensor}');
    print('Wearable: ${widget.wearable}');
    print('Sample Freq: $sampleFreq Hz');
    print('Config Provider: ${widget.sensorConfigProvider}');

    try {
      _sensor = EarableHrSensor(
        ppgSensor: widget.ppgSensor!,
        wearable: widget.wearable!,
        sensorManager: widget.sensorManager,
        sampleFreq: sampleFreq,
        configProvider: widget.sensorConfigProvider,
      );

      print('✓ EarableHrSensor created successfully!');

      setState(() {
        _useMockSensor = false;
        _recreateMeditationWidgetKey();
      });

      print('✓ State updated: _useMockSensor = $_useMockSensor');
      print('✓ New widget key created - LlmMeditationWidget will rebuild');

      // Start sensor before attaching listeners
      print('=== STARTING EARABLE SENSOR ===');
      await _sensor!.start();
      print('✓ Earable sensor started');

      // Restart monitoring with real sensor
      // (initState won't reinitialize since _sensor is now set)
      print('=== CALLING _startMonitoring() ===');
      _startMonitoring();
      print('✓ _startMonitoring() completed');

      print('Switched to earable sensor! _useMockSensor = $_useMockSensor');
    } catch (e, stackTrace) {
      print('❌ ERROR creating or starting EarableHrSensor: $e');
      print('Stack trace: $stackTrace');
      if (showFeedback) {
        _showErrorDialog('Failed to start earable sensor: $e');
      }
      _sensor = null;
      _useMockSensor = true;
      return false;
    }

    // Show success message only if widget is still mounted
    if (mounted && showFeedback) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSuccessSnackbar('Now using real earable data!');
        }
      });
    }
    return true;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => PlatformAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          PlatformDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _startMonitoring() async {
    print('>>> _startMonitoring() called, _sensor = $_sensor');
    if (_sensor == null) {
      print('❌ _sensor is null! Cannot start monitoring.');
      return;
    }

    print('>>> Calling _sensor.start()...');
    try {
      await _sensor!.start();
      print('✓ _sensor.start() completed successfully');
    } catch (e, stackTrace) {
      print('❌ ERROR in _sensor.start(): $e');
      print('Stack trace: $stackTrace');
      return;
    }

    // Reset stability tracking when starting new sensor
    setState(() {
      _hrvIsStable = _useMockSensor; // Mock sensor is always stable
      _hrvMeasurementCount = 0;
      _measurementDurationSeconds = 0;
    });

    // Start timer to track measurement duration
    _measurementTimer?.cancel();
    _measurementTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _measurementDurationSeconds++;
      });
    });

    _hrSubscription = _sensor!.hrStream.listen((hr) {
      setState(() {
        _currentHr = hr;
      });
    });

    _hrvSubscription = _sensor!.hrvStream.listen((hrv) {
      setState(() {
        _currentHrv = hrv['HRV_RMSSD'] ?? 40.0;
        _currentSdnn = hrv['HRV_SDNN'] ?? 40.0;
        _hrvMeasurementCount++;

        // HRV becomes stable after receiving 3 measurements
        // (which means ~30+ RR intervals collected)
        if (!_hrvIsStable && _hrvMeasurementCount >= 3 && !_useMockSensor) {
          _hrvIsStable = true;
          print(
              '✅ HRV measurements now stable ($_hrvMeasurementCount measurements received)');
          print(
              '   RMSSD: ${_currentHrv.toStringAsFixed(1)} ms, SDNN: ${_currentSdnn >= 0 ? _currentSdnn.toStringAsFixed(1) : "pending"} ms');
        }

        // Log HRV updates for debugging
        if (_hrvMeasurementCount % 5 == 0) {
          print(
              '📊 HRV Update #$_hrvMeasurementCount: RMSSD=${_currentHrv.toStringAsFixed(1)}ms, SDNN=${_currentSdnn >= 0 ? _currentSdnn.toStringAsFixed(1) : "pending"}ms, stable=$_hrvIsStable');
        }
      });
    });

    // Monitor connection state
    _connectionSubscription?.cancel();
    _connectionSubscription = _sensor!.isConnected.listen((isConnected) {
      if (!isConnected && mounted) {
        // Reset values to indicate "No Signal"
        setState(() {
          _currentHr = 0.0;
          _currentHrv = -1.0;
          _currentSdnn = -1.0;
          // _activityLevel cannot be set here as it's pulled from sensor directly
        });

        // Show persistent warning if disconnected
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.bluetooth_disabled, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('Earable Disconnected! Reconnecting...')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(
                days: 1), // Persistent until dismissed or reconnected
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                _sensor?.start();
                _startMonitoring();
              },
            ),
          ),
        );
      } else if (isConnected && mounted) {
        // Hide warning when reconnected
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
  }

  void _simulateStress() async {
    if (_sensor is MockHrSensor) {
      // First reset to baseline to ensure stress values change significantly
      (_sensor as MockHrSensor).reset();
      print('Resetting to baseline first...');
      _showSuccessSnackbar('Resetting to baseline...');

      // Reset stress level display immediately
      setState(() {
        _stressLevel = 'normal';
      });

      // Wait for values to normalize - 3 seconds should be enough
      // Mock sensor moves at 95% per second, so after 3s it's very close to target
      await Future.delayed(const Duration(seconds: 3));

      // Now simulate stress
      (_sensor as MockHrSensor).simulateStress();
      print(
          'Simulating stress: HR -> 100 BPM, HRV -> 12 ms (triggers stress detection!)');
      _showSuccessSnackbar('Simulating stress: HR↑100, HRV↓12ms');
    }
  }

  void _simulateRelaxation() {
    if (_sensor is MockHrSensor) {
      (_sensor as MockHrSensor).simulateRelaxation();
      print('Simulating relaxation: HR -> 65 BPM, HRV -> 150 ms');
      _showSuccessSnackbar('Simulating relaxation...');

      // Update stress level display immediately
      setState(() {
        _stressLevel = 'relaxed';
      });
    }
  }

  Future<void> _resetToBaseline() async {
    print('Resetting to baseline...');

    // Update stress level display immediately
    setState(() {
      _stressLevel = 'normal';
      // Reset key to force full widget rebuild and clear state (schedule/detection flags)
      _recreateMeditationWidgetKey();
      _clearTimerModeSchedule();
    });

    // Ensure services are stopped cleanly
    // Note: State is lost due to UniqueKey rebuild
    // await _meditationWidgetKey.currentState?.resetMeditation();

    // Stop current sensor
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _connectionSubscription?.cancel();
    _sensor?.dispose();

    // Reset to mock sensor
    _sensor = MockHrSensor();

    setState(() {
      _useMockSensor = true;
    });

    // Start mock sensor before monitoring
    print('>>> Starting mock sensor (reset)...');
    await _sensor!.start();
    print('✓ Mock sensor started (reset)');

    // Restart monitoring with mock sensor
    _startMonitoring();

    // Clear snooze and meditation timers from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('meditation_snooze_until');
    await prefs.remove('meditation_last_completion');
    await prefs.remove('meditation_scheduled_time');

    print(
        'Reset complete! Back to mock sensor. _useMockSensor = $_useMockSensor');
    _showSuccessSnackbar(
        'Reset to baseline (HR: 75, HRV: 120) and cleared all timers');
  }

  Future<void> _resetSession() async {
    print('Resetting meditation session...');
    await _meditationWidgetKey.currentState?.resetMeditation();

    setState(() {
      _stressLevel = 'normal';
      _clearTimerModeSchedule();
      _hrvMeasurementCount = 0;
      _measurementDurationSeconds = 0;
      _hrvIsStable = _useMockSensor;
    });

    if (_sensor is MockHrSensor) {
      (_sensor as MockHrSensor).reset();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('meditation_snooze_until');
    await prefs.remove('meditation_last_completion');
    await prefs.remove('meditation_scheduled_time');

    print('Session reset complete. _useMockSensor = $_useMockSensor');
    _showSuccessSnackbar('Session reset and timers cleared.');
  }

  String _getActivityDescription(ActivityLevel level) {
    // Basic description
    String desc;
    switch (level) {
      case ActivityLevel.resting:
        desc = 'Resting';
        break;
      case ActivityLevel.light:
        desc = 'Light movement';
        break;
      case ActivityLevel.moderate:
        desc = 'Moderate activity';
        break;
      case ActivityLevel.vigorous:
        desc = 'Vigorous exercise';
        break;
      case ActivityLevel.intense:
        desc = 'Intense exercise';
        break;
    }

    return desc;
  }

  String _getModeLabel(MeditationAppMode mode) {
    switch (mode) {
      case MeditationAppMode.normal:
        return 'Biosignal-Adaptive';
      case MeditationAppMode.timer:
        return 'Timed';
      case MeditationAppMode.test:
        return 'Demo';
    }
  }

  String _getModeDescription(MeditationAppMode mode) {
    switch (mode) {
      case MeditationAppMode.normal:
        return 'Stress-adaptive meditation is active and can respond to live biomarkers.';
      case MeditationAppMode.timer:
        return _timerModeScheduledTime == null
            ? 'Stress prompts are muted. Schedule meditation starts from the Meditation Mode page.'
            : 'Next timer meditation is scheduled for ${_formatScheduledTime(_timerModeScheduledTime!)}.';
      case MeditationAppMode.test:
        return 'Meditation playback is hidden so the page can focus on demo and QA actions.';
    }
  }

  Widget _buildSelectedModeSummary() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text.rich(
        TextSpan(
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
          children: [
            const TextSpan(text: 'Meditation Mode: '),
            TextSpan(
              text: _getModeLabel(_selectedMode),
              style: TextStyle(color: colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshMeditationSettings(UserAccount updatedAccount) async {
    final meditationState = _meditationWidgetKey.currentState;
    if (meditationState != null) {
      await meditationState.updateSettings(updatedAccount);
      return;
    }

    if (mounted) {
      setState(() {
        _recreateMeditationWidgetKey();
      });
    }
  }

  Future<UserAccount?> _openAccountSection(
      EarStreamAccountSection section) async {
    final currentAccount = await UserAccount.load();
    if (!mounted) {
      return null;
    }

    final updatedAccount = await Navigator.push<UserAccount>(
      context,
      MaterialPageRoute(
        builder: (context) => EarStreamAccountSectionPage(
          account: currentAccount,
          section: section,
        ),
      ),
    );

    if (updatedAccount != null && mounted) {
      await _refreshMeditationSettings(updatedAccount);
      _showSuccessSnackbar('EarStream settings updated.');
    }

    return updatedAccount;
  }

  Future<void> _openDebugInfoPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ApiDebugWidget(),
      ),
    );
  }

  Future<void> _openWeeklyAnalyticsPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WeeklyAnalysisScreen(),
      ),
    );
  }

  Future<void> _openDemoModePage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          var localSelectedMode = _selectedMode;
          var localScheduledTime = _timerModeScheduledTime;

          return StatefulBuilder(
            builder: (context, setPageState) {
              Future<void> scheduleAfter(Duration delay) async {
                final scheduled = await _scheduleTimerModeAfter(delay);
                if (scheduled == null || !context.mounted) {
                  return;
                }
                setPageState(() {
                  localScheduledTime = scheduled;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Timer meditation scheduled in ${delay.inMinutes} minutes.',
                    ),
                  ),
                );
              }

              Future<void> pickTime() async {
                final scheduled = await _pickAndScheduleTimerModeTime();
                if (scheduled == null || !context.mounted) {
                  return;
                }
                setPageState(() {
                  localScheduledTime = scheduled;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Timer meditation scheduled for ${_formatScheduledTime(scheduled)}.',
                    ),
                  ),
                );
              }

              void changeMode(MeditationAppMode mode) {
                _setMode(mode);
                setPageState(() {
                  localSelectedMode = mode;
                  if (mode != MeditationAppMode.timer) {
                    localScheduledTime = null;
                  }
                });
              }

              return Scaffold(
                appBar: EarStreamStyle.appBar(
                  context,
                  title: 'Meditation Mode',
                ),
                body: ListView(
                  padding: EarStreamStyle.pagePadding(context),
                  children: [
                      _buildModeSelector(
                        selectedMode: localSelectedMode,
                        onModeSelected: changeMode,
                      ),
                      const SizedBox(height: 12),
                      if (localSelectedMode == MeditationAppMode.timer)
                        _buildTimerModeCard(
                          scheduledTime: localScheduledTime,
                          onScheduleAfter: scheduleAfter,
                          onPickTime: pickTime,
                          onCancelSchedule: () {
                            _clearTimerModeSchedule();
                            setPageState(() {
                              localScheduledTime = null;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Scheduled timer cleared.'),
                              ),
                            );
                          },
                        ),
                      if (localSelectedMode == MeditationAppMode.test)
                        _buildTestModePlaceholder(
                          onRunPlaceholderAction: () {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Demo mode placeholder is active.'),
                                ),
                              );
                            }
                          },
                        ),
                      if (localSelectedMode == MeditationAppMode.normal)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _getModeDescription(MeditationAppMode.normal),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.4,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  bool _hasRequiredPersonalInfo(UserAccount account) {
    return account.name.trim().isNotEmpty &&
        account.age >= 13 &&
        account.age <= 120;
  }

  Future<bool> _ensureMeditationCanStart() async {
    final account = await UserAccount.load();
    if (_hasRequiredPersonalInfo(account)) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Personal Info Required'),
        content: const Text(
          'EarStream still needs a valid name and age before a meditation can start. Please complete Personal Info first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Personal Info'),
          ),
        ],
      ),
    );

    if (shouldOpenSettings != true || !mounted) {
      return false;
    }

    final updatedAccount =
        await _openAccountSection(EarStreamAccountSection.personalInfo);
    if (updatedAccount == null) {
      return false;
    }

    final isReady = _hasRequiredPersonalInfo(updatedAccount);
    if (!isReady && mounted) {
      _showErrorDialog(
        'Meditation cannot start until Personal Info contains a valid name and age.',
      );
    }

    return isReady;
  }

  Future<void> _closeDrawerAnd(Future<void> Function() action) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) {
      return;
    }
    await action();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EarStreamStyle.appBar(
        context,
        title: EarStreamStyle.appName,
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      EarStreamStyle.appName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Meditation Mode: ${_getModeLabel(_selectedMode)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Meditation Mode'),
                onTap: () => _closeDrawerAnd(_openDemoModePage),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Personal Info'),
                onTap: () => _closeDrawerAnd(
                  () => _openAccountSection(EarStreamAccountSection.personalInfo)
                      .then((_) {}),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.spa_outlined),
                title: const Text('Meditation Preferences'),
                onTap: () => _closeDrawerAnd(
                  () => _openAccountSection(
                    EarStreamAccountSection.meditationPreferences,
                  ).then((_) {}),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: const Text('Weekly Analytics'),
                onTap: () => _closeDrawerAnd(_openWeeklyAnalyticsPage),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Outlook Calendar Integration'),
                onTap: () => _closeDrawerAnd(
                  () => _openAccountSection(
                    EarStreamAccountSection.outlookCalendar,
                  ).then((_) {}),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('API Keys'),
                onTap: () => _closeDrawerAnd(
                  () => _openAccountSection(EarStreamAccountSection.apiKeys)
                      .then((_) {}),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Debug Info'),
                onTap: () => _closeDrawerAnd(_openDebugInfoPage),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: EarStreamStyle.pagePadding(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          _buildSelectedModeSummary(),
                          const SizedBox(height: 12),

                          HrHrvDisplayNew(
                            hr: _currentHr,
                            hrv: _currentHrv,
                            sdnn: _currentSdnn,
                            stressLevel: _stressLevel,
                            isHrvStable: _hrvIsStable,
                            measurementDurationSeconds:
                                _measurementDurationSeconds,
                            activityLevel: _sensor is EarableHrSensor
                                ? (_sensor as EarableHrSensor)
                                    .activityLevel
                                    .name
                                : null,
                            activityDescription: _sensor is EarableHrSensor
                                ? _getActivityDescription(
                                    (_sensor as EarableHrSensor).activityLevel)
                                : null,
                          ),
                          const SizedBox(height: 16),

                          if (_sensor != null &&
                              _selectedMode != MeditationAppMode.test &&
                              _earStreamActivated)
                            LlmMeditationWidget(
                              key: _meditationWidgetKey,
                              sensor: _sensor!,
                              onBeforeStartMeditation:
                                  _ensureMeditationCanStart,
                              stressDetectionEnabled:
                                  _selectedMode == MeditationAppMode.normal,
                              onReset: () {
                                unawaited(_resetSession());
                              },
                              onStressLevelChanged: (level) {
                                if (mounted) {
                                  setState(() {
                                    _stressLevel = level;
                                  });
                                }
                              },
                            ),

                          const SizedBox(height: 16),

                          if (_selectedMode != MeditationAppMode.test) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _sensor == null || _earStreamActivated
                                    ? null
                                    : _activateEarStream,
                                child: Text(
                                  _earStreamActivated
                                      ? '${EarStreamStyle.appName} Active'
                                      : 'Start ${EarStreamStyle.appName}',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed:
                                      _useMockSensor && _sensor is MockHrSensor
                                          ? _simulateStress
                                          : null,
                                  child: const Text('Simulate Stress'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    unawaited(_resetSession());
                                  },
                                  child: const Text('Reset'),
                                ),
                              ),
                            ],
                          ),
                          /*
                          Legacy controls retained temporarily for rollback safety
                          Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    print('🔘 USE EARABLE BUTTON PRESSED');
                                    print(
                                        '   ppgSensor: ${widget.ppgSensor != null ? "available" : "NULL"}');
                                    print('   _useMockSensor: $_useMockSensor');
                                    print(
                                        '   wearable: ${widget.wearable != null ? "available" : "NULL"}');

                                    if (widget.ppgSensor == null) {
                                      print(
                                          '   ❌ Cannot switch: ppgSensor is NULL');
                                      _showErrorDialog(
                                          'PPG Sensor not available. Please ensure earable is connected.');
                                      return;
                                    }

                                    if (!_useMockSensor) {
                                      print(
                                          '   ⚠️ Already using earable sensor');
                                      return;
                                    }

                                    print(
                                        '   ✅ Calling _switchToEarableSensor()');
                                    _switchToEarableSensor();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _useMockSensor
                                        ? Colors.blue[100]
                                        : Colors.green[100],
                                    foregroundColor: _useMockSensor
                                        ? Colors.blue[900]
                                        : Colors.green[900],
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: Text(_useMockSensor
                                      ? 'Use Earable'
                                      : '✓ Earable Active'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed:
                                      _useMockSensor && _sensor is MockHrSensor
                                          ? _simulateStress
                                          : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange[100],
                                    foregroundColor: Colors.orange[900],
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    disabledBackgroundColor: Colors.grey[300],
                                    disabledForegroundColor: Colors.grey[600],
                                  ),
                                  child: const Text('Simulate Stress'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _resetToBaseline,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[200],
                                    foregroundColor: Colors.grey[800],
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Reset'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed:
                                      _useMockSensor && _sensor is MockHrSensor
                                          ? _simulateRelaxation
                                          : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[100],
                                    foregroundColor: Colors.green[900],
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    disabledBackgroundColor: Colors.grey[300],
                                    disabledForegroundColor: Colors.grey[600],
                                  ),
                                  child: const Text('Simulate Relax'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          */
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timerModeTimer?.cancel();
    _measurementTimer?.cancel();
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _connectionSubscription?.cancel();
    _sensor?.dispose();
    // _audioPlayer.dispose(); // Removed
    super.dispose();
  }
}
