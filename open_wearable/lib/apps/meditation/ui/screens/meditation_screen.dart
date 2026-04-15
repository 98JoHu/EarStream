import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/apps/meditation/ui/shared/earstream_style.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import 'seal_check_screen.dart';
import '../../core/biosignals/sensors/mock_hr_sensor.dart';
import '../../core/biosignals/sensors/earable_hr_sensor.dart';
import '../../core/biosignals/sensors/hr_sensor_interface.dart';
import '../../core/biosignals/activity_detector.dart';
import '../../config/biosignal_config.dart';
import '../../config/demo_config.dart';
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
  List<HrDataPoint> _hrHistory = []; // HR values for the last 5 minutes
  bool _hrIsStable = false; // Track if HR measurements have 30+ seconds of data
  bool _hrvIsStable = false; // Track if HRV measurements are reliable
  int _hrvMeasurementCount = 0; // Count HRV measurements received
  int _measurementDurationSeconds = 0; // Track how long we've been measuring
  Timer? _measurementTimer; // Timer to track measurement duration

  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<Map<String, double>>? _hrvSubscription;
  StreamSubscription<bool>? _connectionSubscription; // Monitor connection state

  String _stressLevel =
      'relaxed'; // Track stress level: 'relaxed' or 'stressed'

  // Demo mode state tracking
  DemoPhase _demoPhase = DemoPhase.none;
  String _demoSubMode = DemoConfig.modeNone;
  DemoMeditationPreferences? _demoPreferences;
  DateTime? _demoPhaseStartTime;
  Timer? _demoPhaseTimer;
  double? _demoBaselineHr;
  double? _demoBaselineRmssd;

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

  void _deactivateEarStream() {
    setState(() {
      _earStreamActivated = false;
      // Reset monitoring state
      _currentHr = 0.0;
      _currentHrv = -1.0;
      _hrHistory.clear();
      _hrIsStable = false;
      _stressLevel = 'relaxed';
      _hrvIsStable = false;
      _hrvMeasurementCount = 0;
    });
  }

  Future<void> _toggleEarStream() async {
    if (_earStreamActivated) {
      // Show confirmation dialog when stopping
      final shouldStop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stop Monitoring?'),
          content: const Text(
            'Do you want to stop monitoring your biosignals?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Stop'),
            ),
          ],
        ),
      );

      if (shouldStop == true && mounted) {
        _deactivateEarStream();
      }
    } else {
      _activateEarStream();
    }
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
    required VoidCallback onStartNow,
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onStartNow,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Now'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
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

  Widget _buildDemoModeSelection({
    required VoidCallback onSelectPersonalizedOnly,
    required VoidCallback onSelectBiosignalAdaptive,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'ACM UbiComp 2026 Demo Mode',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Select a demo experience to showcase EarStream capabilities:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // Personalized Meditation Only Option
        Card(
          elevation: 2,
          child: InkWell(
            onTap: onSelectPersonalizedOnly,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.psychology_outlined,
                          color: colorScheme.onPrimaryContainer,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Personalized Meditation Only',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Set meditation preferences or use "Surprise me"\n'
                    '• Experience AI-generated personalized meditation\n'
                    '• 3 content segments (~5 minutes)\n'
                    '• No biosignal requirements',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // Biosignal-Adaptive Option
        Card(
          elevation: 2,
          child: InkWell(
            onTap: onSelectBiosignalAdaptive,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.sensors_outlined,
                          color: colorScheme.onSecondaryContainer,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Biosignal-Adaptive',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Automatic seal check guided setup\n'
                    '• 30s calibration + 30s baseline measurement\n'
                    '• Real-time stress detection (3% threshold)\n'
                    '• Adaptive meditation up to 4 segments\n'
                    '• Live biosignal analytics',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDemoPhaseIndicator() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String phaseTitle;
    String phaseMessage;
    IconData phaseIcon;
    Color phaseColor;
    Widget? progressWidget;

    switch (_demoPhase) {
      case DemoPhase.sealCheck:
        phaseTitle = 'Demo: Seal Check';
        phaseMessage = DemoConfig.sealCheckMessage;
        phaseIcon = Icons.verified_outlined;
        phaseColor = colorScheme.primary;
        break;
      
      case DemoPhase.calibration:
        phaseTitle = 'Demo: Calibration Phase';
        phaseMessage = DemoConfig.calibrationMessage;
        phaseIcon = Icons.settings_outlined;
        phaseColor = Colors.orange;
        
        if (_demoPhaseStartTime != null) {
          final elapsed = DateTime.now().difference(_demoPhaseStartTime!);
          final remaining = DemoConfig.calibrationDuration - elapsed;
          final progress = elapsed.inSeconds / DemoConfig.calibrationDuration.inSeconds;
          
          progressWidget = Column(
            children: [
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
              const SizedBox(height: 4),
              Text(
                '${remaining.inSeconds} seconds remaining',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        }
        break;
      
      case DemoPhase.baselineMeasurement:
        phaseTitle = 'Demo: Baseline Measurement';
        phaseMessage = DemoConfig.baselineMessage;
        phaseIcon = Icons.straighten_outlined;
        phaseColor = Colors.blue;
        
        if (_demoPhaseStartTime != null) {
          final elapsed = DateTime.now().difference(_demoPhaseStartTime!);
          final remaining = DemoConfig.baselineDuration - elapsed;
          final progress = elapsed.inSeconds / DemoConfig.baselineDuration.inSeconds;
          
          progressWidget = Column(
            children: [
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
              const SizedBox(height: 4),
              Text(
                '${remaining.inSeconds} seconds remaining',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        }
        break;
      
      case DemoPhase.monitoring:
        phaseTitle = 'Demo: Stress Monitoring';
        phaseMessage = DemoConfig.monitoringMessage;
        phaseIcon = Icons.monitor_heart_outlined;
        phaseColor = Colors.green;
        
        if (_demoBaselineHr != null && _demoBaselineRmssd != null) {
          progressWidget = Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Baseline: HR ${_demoBaselineHr!.toStringAsFixed(0)} BPM, '
              'RMSSD ${_demoBaselineRmssd!.toStringAsFixed(0)} ms',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        break;
      
      case DemoPhase.settingPreferences:
        phaseTitle = 'Demo: Personalized Meditation';
        phaseMessage = 'Starting meditation with your preferences...';
        phaseIcon = Icons.spa_outlined;
        phaseColor = colorScheme.primary;
        break;
      
      case DemoPhase.meditationSession:
        phaseTitle = 'Demo: Meditation In Progress';
        phaseMessage = _demoSubMode == DemoConfig.modePersonalizedOnly
            ? 'Personalized meditation (3 segments)'
            : 'Biosignal-adaptive meditation (max 4 segments)';
        phaseIcon = Icons.self_improvement_outlined;
        phaseColor = Colors.purple;
        break;
      
      case DemoPhase.analytics:
        phaseTitle = 'Demo: Session Complete';
        phaseMessage = 'Showing session analytics...';
        phaseIcon = Icons.analytics_outlined;
        phaseColor = Colors.green;
        break;
      
      default:
        return const SizedBox.shrink();
    }

    return Card(
      color: phaseColor.withOpacity(0.1),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(phaseIcon, color: phaseColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    phaseTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: phaseColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              phaseMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
              ),
            ),
            if (progressWidget != null) progressWidget,
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
    // Target: 200 Hz for accurate HRV (research standard)
    // Fallback: Use highest available if 200 Hz not supported
    double sampleFreq = BiosignalConfig.ppgSamplingFrequency; // Target 200 Hz
    bool found200Hz = false;
    
    if (widget.sensorConfigProvider != null) {
      for (final config in widget.ppgSensor!.relatedConfigurations) {
        final value =
            widget.sensorConfigProvider!.getSelectedConfigurationValue(config);
        if (value is SensorFrequencyConfigurationValue) {
          sampleFreq = value.frequencyHz;
          if (sampleFreq >= 200.0) {
            found200Hz = true;
            print('Using sample frequency: $sampleFreq Hz (≥200 Hz target achieved)');
          } else {
            print('Using sample frequency: $sampleFreq Hz (below 200 Hz target)');
          }
          break;
        }
      }
      
      if (!found200Hz) {
        print('WARNING: 200 Hz PPG sampling not available. Using $sampleFreq Hz.');
        print('HRV accuracy may be reduced. Recommend configuring sensor for ≥200 Hz.');
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
        
        // Add to HR history with timestamp
        final now = DateTime.now();
        _hrHistory.add(HrDataPoint(timestamp: now, hr: hr));
        
        // Keep only last 5 minutes of data (300 seconds)
        final cutoffTime = now.subtract(const Duration(seconds: 300));
        _hrHistory.removeWhere((point) => point.timestamp.isBefore(cutoffTime));
        
        // HR becomes stable after 30 seconds of measurements
        if (!_hrIsStable && _measurementDurationSeconds >= 30) {
          _hrIsStable = true;
          print('✅ HR measurements now stable (30+ seconds of data)');
        }
      });
    });

    _hrvSubscription = _sensor!.hrvStream.listen((hrv) {
      setState(() {
        _currentHrv = hrv['HRV_RMSSD'] ?? 40.0;
        _hrvMeasurementCount++;

        // HRV becomes stable after receiving 3 measurements
        // (which means ~30+ RR intervals collected)
        if (!_hrvIsStable && _hrvMeasurementCount >= 3 && !_useMockSensor) {
          _hrvIsStable = true;
          print(
              '✅ HRV measurements now stable ($_hrvMeasurementCount measurements received)');
          print(
              '   RMSSD: ${_currentHrv.toStringAsFixed(1)} ms');
        }

        // Log HRV updates for debugging
        if (_hrvMeasurementCount % 5 == 0) {
          print(
              '📊 HRV Update #$_hrvMeasurementCount: RMSSD=${_currentHrv.toStringAsFixed(1)}ms, stable=$_hrvIsStable');
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
          _hrHistory.clear();
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
        _stressLevel = 'relaxed';
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
      _stressLevel = 'relaxed';
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
      _stressLevel = 'relaxed';
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

  Future<void> _openSealCheckPage() async {
    // Check if wearable is available and has AudioResponseManager capability
    if (widget.wearable == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect an OpenEarable device first.'),
        ),
      );
      return;
    }

    if (!widget.wearable!.hasCapability<AudioResponseManager>()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This device does not support seal check (AudioResponseManager not available).',
          ),
        ),
      );
      return;
    }

    final audioManager = widget.wearable!.requireCapability<AudioResponseManager>();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AudioResponseMeasurementView(
          manager: audioManager,
          title: 'OpenEarable 2.0 Seal Check',
          parameters: const {},
        ),
      ),
    );
  }

  Future<void> _openDemoModePage() async {
    final selectedDemoMode = await Navigator.push<String>(
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
                          onStartNow: () async {
                            // Start meditation immediately
                            _scheduleTimerModeAt(
                              DateTime.now(),
                              description: 'now',
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Meditation started!'),
                                ),
                              );
                            }
                          },
                        ),
                      if (localSelectedMode == MeditationAppMode.test)
                        _buildDemoModeSelection(
                          onSelectPersonalizedOnly: () {
                            Navigator.of(context).pop(DemoConfig.modePersonalizedOnly);
                          },
                          onSelectBiosignalAdaptive: () {
                            Navigator.of(context).pop(DemoConfig.modeBiosignalAdaptive);
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

    // Handle selected demo mode
    if (selectedDemoMode != null && 
        selectedDemoMode != DemoConfig.modeNone && 
        mounted) {
      setState(() {
        _demoSubMode = selectedDemoMode;
        _demoPhase = DemoPhase.modeSelection;
      });
      
      // Start the appropriate demo flow
      if (selectedDemoMode == DemoConfig.modePersonalizedOnly) {
        _startPersonalizedOnlyDemo();
      } else if (selectedDemoMode == DemoConfig.modeBiosignalAdaptive) {
        _startBiosignalAdaptiveDemo();
      }
    }
  }

  // ============================================================================
  // DEMO MODE FLOWS
  // ============================================================================

  Future<void> _startPersonalizedOnlyDemo() async {
    // Show preferences selection dialog
    final preferences = await _showDemoPreferencesDialog();
    
    if (preferences == null || !mounted) {
      // User cancelled
      _resetDemoMode();
      return;
    }
    
    setState(() {
      _demoPreferences = preferences;
      _demoPhase = DemoPhase.settingPreferences;
    });
    
    // Immediately start meditation with these preferences
    _startPersonalizedOnlyMeditation();
  }

  Future<void> _startBiosignalAdaptiveDemo() async {
    // Start with seal check phase
    setState(() {
      _demoPhase = DemoPhase.sealCheck;
    });
    
    // Automatically navigate to seal check screen
    await _openSealCheckPage();
    
    if (!mounted) return;
    
    // After seal check, proceed to calibration if sensor is ready
    if (_sensor != null) {
      _startCalibrationPhase();
    } else {
      // Need to initialize sensor first
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please ensure earable is connected and try again.'),
        ),
      );
      _resetDemoMode();
    }
  }

  Future<DemoMeditationPreferences?> _showDemoPreferencesDialog() async {
    return await showDialog<DemoMeditationPreferences>(
      context: context,
      barrierDismissable: false,
      builder: (context) => _DemoPreferencesDialog(),
    );
  }

  void _resetDemoMode() {
    setState(() {
      _demoPhase = DemoPhase.none;
      _demoSubMode = DemoConfig.modeNone;
      _demoPreferences = null;
      _demoPhaseStartTime = null;
      _demoBaselineHr = null;
     _demoBaselineRmssd = null;
    });
    _demoPhaseTimer?.cancel();
    _demoPhaseTimer = null;
  }

  void _startPersonalizedOnlyMeditation() {
    setState(() {
      _demoPhase = DemoPhase.meditationSession;
    });
    
    // For personalized-only, we still need the sensor for the widget
    // but we don't need stress detection
    if (!_earStreamActivated && _sensor != null) {
      _activateEarStream();
      _startMonitoring();
    }
    
    // The LlmMeditationWidget will handle the meditation with demo preferences
    // It will be configured to use 3 segments based on demo mode
  }

  void _startCalibrationPhase() {
    setState(() {
      _demoPhase = DemoPhase.calibration;
      _demoPhaseStartTime = DateTime.now();
    });
    
    // Automatically activate EarStream monitoring
    if (!_earStreamActivated) {
      _activateEarStream();
      _startMonitoring();
    }
    
    // Start timer for calibration duration
    _demoPhaseTimer = Timer(DemoConfig.calibrationDuration, () {
      if (mounted && _demoPhase == DemoPhase.calibration) {
        _startBaselineMeasurementPhase();
      }
    });
  }

  void _startBaselineMeasurementPhase() {
    setState(() {
      _demoPhase = DemoPhase.baselineMeasurement;
      _demoPhaseStartTime = DateTime.now();
      // Reset baseline values
      _demoBaselineHr = null;
      _demoBaselineRmssd = null;
    });
    
    // Start timer for baseline duration
    _demoPhaseTimer = Timer(DemoConfig.baselineDuration, () {
      if (mounted && _demoPhase == DemoPhase.baselineMeasurement) {
        _captureBaselineAndStartMonitoring();
      }
    });
  }

  void _captureBaselineAndStartMonitoring() {
    // Capture current HR and HRV as baseline
    setState(() {
      _demoBaselineHr = _currentHr > 0 ? _currentHr : DemoConfig.fallbackBaselineHr;
      _demoBaselineRmssd = _currentHrv > 0 ? _currentHrv : DemoConfig.fallbackBaselineRmssd;
      _demoPhase = DemoPhase.monitoring;
      _demoPhaseStartTime = DateTime.now();
    });
    
    print('Demo Baseline Captured: HR=${_demoBaselineHr?.toStringAsFixed(1)} BPM, '
          'RMSSD=${_demoBaselineRmssd?.toStringAsFixed(1)} ms');
    
    // Start periodic stress checking (every 3 seconds)
    _demoPhaseTimer?.cancel();
    _demoPhaseTimer = Timer.periodic(DemoConfig.monitoringCheckInterval, (timer) {
      _checkDemoStressLevel();
    });
    
    // Also set max monitoring duration timeout
    Timer(DemoConfig.maxMonitoringDuration, () {
      if (mounted && _demoPhase == DemoPhase.monitoring) {
        print('Demo: Max monitoring duration reached, forcing meditation start');
        _startBiosignalAdaptiveMeditation();
      }
    });
  }

  void _checkDemoStressLevel() {
    if (_demoPhase != DemoPhase.monitoring) return;
    if (_demoBaselineHr == null || _demoBaselineRmssd == null) return;
    
    final currentHr = _currentHr;
    final currentRmssd = _currentHrv;
    
    if (currentHr <= 0 || currentRmssd <= 0) return;
    
    // Calculate deviation percentages
    final hrDeviation = ((currentHr - _demoBaselineHr!) / _demoBaselineHr!) * 100;
    final rmssdDeviation = ((_demoBaselineRmssd! - currentRmssd) / _demoBaselineRmssd!) * 100;
    
    // Check if either exceeds 3% threshold (HR up or RMSSD down)
    final isStressed = hrDeviation >= DemoConfig.stressThresholdPercent || 
                       rmssdDeviation >= DemoConfig.stressThresholdPercent;
    
    if (isStressed) {
      print('Demo Stress Detected! HR deviation: ${hrDeviation.toStringAsFixed(1)}%, '
            'RMSSD deviation: ${rmssdDeviation.toStringAsFixed(1)}%');
      _startBiosignalAdaptiveMeditation();
    }
  }

  void _startBiosignalAdaptiveMeditation() {
    _demoPhaseTimer?.cancel();
    setState(() {
      _demoPhase = DemoPhase.meditationSession;
    });
    
    // The LlmMeditationWidget will handle the meditation with demo settings
    // It will be configured to use 4 segments max based on demo mode
  }

  void _onDemoMeditationComplete() {
    setState(() {
      _demoPhase = DemoPhase.analytics;
    });
    
    // Show analytics for a few seconds, then return to demo selection
    Timer(const Duration(seconds: 5), () {
      if (mounted && _demoPhase == DemoPhase.analytics) {
        _resetDemoMode();
        _openDemoModePage(); // Return to demo mode selection
      }
    });
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
    return PopScope(
      canPop: !_earStreamActivated,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }

        if (_earStreamActivated) {
          final shouldContinue = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Exit Meditation?'),
              content: const Text(
                'Your biosignals are being monitored. Do you want to continue monitoring in the background?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Stop Monitoring'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Continue in Background'),
                ),
              ],
            ),
          );

          if (shouldContinue == false && mounted) {
            _deactivateEarStream();
          }

          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(
                        'lib/apps/meditation/assets/earstream_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        const SizedBox(height: 4),
                        Text(
                          'Meditation Mode: ${_getModeLabel(_selectedMode)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                        ),
                      ],
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
                leading: const Icon(Icons.verified_outlined),
                title: const Text('OpenEarable 2.0 Seal Check'),
                onTap: () => _closeDrawerAnd(_openSealCheckPage),
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

                          // Demo Phase Indicator
                          if (_demoPhase != DemoPhase.none && 
                              _demoPhase != DemoPhase.modeSelection)
                            _buildDemoPhaseIndicator(),
                          if (_demoPhase != DemoPhase.none && 
                              _demoPhase != DemoPhase.modeSelection)
                            const SizedBox(height: 12),

                          HrHrvDisplayNew(
                            hr: _currentHr,
                            hrv: _currentHrv,
                            hrHistory: _hrHistory,
                            isHrStable: _hrIsStable,
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
                            showMonitoring: _selectedMode == MeditationAppMode.normal && 
                                _earStreamActivated,
                          ),
                          const SizedBox(height: 16),

                          if (_sensor != null &&
                              (_selectedMode != MeditationAppMode.test || 
                               _demoPhase == DemoPhase.meditationSession) &&
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
                              demoMode: _demoSubMode,
                              demoPreferences: _demoPreferences,
                              demoBaselineHr: _demoBaselineHr,
                              demoBaselineRmssd: _demoBaselineRmssd,
                              onDemoComplete: () {
                                if (_demoPhase == DemoPhase.meditationSession) {
                                  _onDemoMeditationComplete();
                                }
                              },
                            ),

                          const SizedBox(height: 16),

                          if (_selectedMode != MeditationAppMode.test) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _sensor == null
                                    ? null
                                    : _toggleEarStream,
                                child: Text(
                                  _earStreamActivated
                                      ? 'Stop ${EarStreamStyle.appName}'
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
    ), // Scaffold
  ); // PopScope
  }

  @override
  void dispose() {
    _timerModeTimer?.cancel();
    _measurementTimer?.cancel();
    _demoPhaseTimer?.cancel();
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _connectionSubscription?.cancel();
    _sensor?.dispose();
    // _audioPlayer.dispose(); // Removed
    super.dispose();
  }
}

// ================================================================================
// DEMO PREFERENCES DIALOG
// ================================================================================

class _DemoPreferencesDialog extends StatefulWidget {
  @override
  State<_DemoPreferencesDialog> createState() => _DemoPreferencesDialogState();
}

class _DemoPreferencesDialogState extends State<_DemoPreferencesDialog> {
  String _selectedStyle = 'Mindfulness';
  String _selectedVoiceTone = 'Calm';
  int _durationMinutes = 5;
  bool _useBackgroundSounds = true;

  void _surpriseMe() {
    final randomPrefs = DemoMeditationPreferences.random();
    setState(() {
      _selectedStyle = randomPrefs.meditationStyle;
      _selectedVoiceTone = randomPrefs.voiceTone;
      _durationMinutes = randomPrefs.durationMinutes;
      _useBackgroundSounds = randomPrefs.useBackgroundSounds;
    });
  }

  void _confirm() {
    final preferences = DemoMeditationPreferences(
      meditationStyle: _selectedStyle,
      voiceTone: _selectedVoiceTone,
      durationMinutes: _durationMinutes,
      useBackgroundSounds: _useBackgroundSounds,
    );
    Navigator.of(context).pop(preferences);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.tune, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Meditation Preferences'),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Surprise Me Button
              Center(
                child: OutlinedButton.icon(
                  onPressed: _surpriseMe,
                  icon: const Icon(Icons.casino),
                  label: const Text('Surprise Me'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              
              // Meditation Style
              Text(
                'Meditation Style',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: DemoConfig.availableStyles.map((style) {
                  final isSelected = style == _selectedStyle;
                  return ChoiceChip(
                    label: Text(style),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedStyle = style);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              
              // Voice Tone
              Text(
                'Voice Tone',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: DemoConfig.availableVoiceTones.map((tone) {
                  final isSelected = tone == _selectedVoiceTone;
                  return ChoiceChip(
                    label: Text(tone),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedVoiceTone = tone);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              
              // Duration
              Text(
                'Duration: $_durationMinutes minutes',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Slider(
                value: _durationMinutes.toDouble(),
                min: 3,
                max: 10,
                divisions: 7,
                label: '$_durationMinutes min',
                onChanged: (value) {
                  setState(() => _durationMinutes = value.round());
                },
              ),
              const SizedBox(height: 8),
              
              // Background Sounds
              SwitchListTile(
                title: const Text('Background Sounds'),
                subtitle: const Text('Ambient nature sounds'),
                value: _useBackgroundSounds,
                onChanged: (value) {
                  setState(() => _useBackgroundSounds = value);
                },
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Start Meditation'),
        ),
      ],
    );
  }
}
