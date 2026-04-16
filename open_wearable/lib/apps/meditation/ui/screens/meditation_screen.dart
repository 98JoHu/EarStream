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
  bool _isMeditationSessionActive = false; // True when a meditation is actively running
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
  bool _isDemoModeActive = false;
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
      // Activate demo mode when test mode is selected
      if (mode == MeditationAppMode.test) {
        _isDemoModeActive = true;
        _demoPhase = DemoPhase.modeSelection;
      } else {
        _isDemoModeActive = false;
        _resetDemoMode();
      }
    });
  }

  void _clearTimerModeSchedule() {
    _timerModeTimer?.cancel();
    _timerModeTimer = null;
    _timerModeScheduledTime = null;
  }

  Future<void> _activateEarStream() async {
    if (_earStreamActivated) return;

    setState(() {
      _earStreamActivated = true;
    });

    if (_hasEarableSensorAvailable && !_useMockSensor) {
      // Configure the PPG hardware: sends BLE config and starts the physical
      // PPG data stream on the earable device (first time only).
      await _configurePpgSensor();

      // Read back the actual sample frequency selected by the config system.
      double sampleFreq = BiosignalConfig.ppgSamplingFrequency;
      if (widget.sensorConfigProvider != null) {
        for (final config in widget.ppgSensor!.relatedConfigurations) {
          final value =
              widget.sensorConfigProvider!.getSelectedConfigurationValue(config);
          if (value is SensorFrequencyConfigurationValue) {
            sampleFreq = value.frequencyHz;
            break;
          }
        }
      }

      // Dispose the placeholder created at init and recreate with correct freq.
      _hrSubscription?.cancel();
      _hrvSubscription?.cancel();
      _connectionSubscription?.cancel();
      _sensor?.dispose();
      _sensor = EarableHrSensor(
        ppgSensor: widget.ppgSensor!,
        wearable: widget.wearable!,
        sensorManager: widget.sensorManager,
        sampleFreq: sampleFreq,
        configProvider: widget.sensorConfigProvider,
      );
    }

    _startMonitoring();
  }

  void _deactivateEarStream() {
    _stopSensorStreams();
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

  /// Stops active sensor measurements and cancels stream subscriptions.
  /// The sensor object itself is kept alive so it can be restarted later.
  void _stopSensorStreams() {
    _hrSubscription?.cancel();
    _hrSubscription = null;
    _hrvSubscription?.cancel();
    _hrvSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _measurementTimer?.cancel();
    _measurementTimer = null;
    _sensor?.stop();
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
      await _activateEarStream();
    }
  }

  Future<DateTime?> _scheduleTimerModeAfter(Duration delay) async {
    final scheduled = DateTime.now().add(delay);
    return _scheduleTimerModeAt(
      scheduled,
      description: 'in ${delay.inMinutes} min',
    );
  }

  /// Immediately starts a timed meditation session, bypassing stress detection.
  Future<void> _startTimerNow() async {
    final meditationState = _meditationWidgetKey.currentState;
    if (meditationState == null) {
      _showErrorDialog('Meditation widget is not ready. Please wait a moment.');
      return;
    }
    if (!meditationState.isIdle) {
      _showSuccessSnackbar('A session is already running.');
      return;
    }
    final started = await meditationState.startMeditationNowFromExternal();
    if (started && mounted) {
      _showSuccessSnackbar('Timed meditation started.');
    }
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

  // ============================================================================
  // DEMO CONTROL PANEL - Conference-ready guided experience
  // ============================================================================
  
  Widget _buildDemoControlPanel() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Phase-specific content
    String phaseTitle;
    String phaseInstructions;
    IconData phaseIcon;
    Widget? actionButton;
    Widget? statusWidget;
    
    switch (_demoPhase) {
      case DemoPhase.none:
      case DemoPhase.modeSelection:
        phaseTitle = 'ACM UbiComp 2026 Demo Mode';
        phaseInstructions = 'Welcome! Please select a demo experience to showcase EarStream\'s capabilities:';
        phaseIcon = Icons.campaign_outlined;
        
        // Mode selection buttons
        actionButton = Column(
          children: [
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _selectDemoMode(DemoConfig.modePersonalizedOnly),
                icon: const Icon(Icons.psychology_outlined),
                label: const Text('Personalized Meditation Only'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _selectDemoMode(DemoConfig.modeBiosignalAdaptive),
                icon: const Icon(Icons.sensors_outlined),
                label: const Text('Biosignal-Adaptive Demo'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        );
        break;
      
      case DemoPhase.settingPreferences:
        phaseTitle = _demoSubMode == DemoConfig.modeBiosignalAdaptive
            ? 'Step 1 of 5 · Demo Preferences'
            : 'Step 1 of 2 · Demo Preferences';
        phaseInstructions = 'Choose how the demo session should feel. '
            'Settings are session-only and won\'t change your saved profile.';
        phaseIcon = Icons.spa_outlined;

        actionButton = SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _openDemoPreferences,
            icon: const Icon(Icons.tune_outlined),
            label: const Text('Set Preferences →'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        );
        break;

      case DemoPhase.calibration:
      case DemoPhase.baselineMeasurement:
      case DemoPhase.monitoring:
      case DemoPhase.meditationSession:
        // For biosignal-adaptive active phases: show compact inline status only
        if (_demoSubMode == DemoConfig.modeBiosignalAdaptive) {
          return _buildDemoStatusChip();
        }
        // Personalized-only keeps the full card for meditationSession
        phaseTitle = 'Meditation In Progress';
        phaseInstructions = 'Enjoying personalized meditation session (3 segments)...';
        phaseIcon = Icons.self_improvement_outlined;
        break;
      
      case DemoPhase.analytics:
        phaseTitle = 'Demo Complete!';
        phaseInstructions = 'Session analytics have been displayed. Ready for another demo?';
        phaseIcon = Icons.check_circle;
        
        actionButton = SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _returnToDemoSelection(),
            icon: const Icon(Icons.replay),
            label: const Text('Start New Demo'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        );
        break;
      
      default:
        return const SizedBox.shrink();
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(phaseIcon, color: colorScheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    phaseTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              phaseInstructions,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.5,
              ),
            ),
            if (statusWidget != null) ...[
              const SizedBox(height: 16),
              statusWidget,
            ],
            if (actionButton != null) ...[
              const SizedBox(height: 20),
              actionButton,
            ],
          ],
        ),
      ),
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

  /// Compact status pill shown in biosignal-adaptive demo during active phases
  /// (calibration, baseline, monitoring, meditation).
  Widget _buildDemoStatusChip() {
    final theme = Theme.of(context);
    IconData icon;
    String label;
    Color color;
    Widget? trailing;

    switch (_demoPhase) {
      case DemoPhase.calibration:
        icon = Icons.settings_outlined;
        label = 'Calibration';
        color = Colors.orange;
        if (_demoPhaseStartTime != null) {
          final elapsed = DateTime.now().difference(_demoPhaseStartTime!);
          final progress = (elapsed.inMilliseconds /
                  DemoConfig.calibrationDuration.inMilliseconds)
              .clamp(0.0, 1.0);
          trailing = SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: progress,
              color: color,
              backgroundColor: color.withOpacity(0.2),
            ),
          );
        }
        break;
      case DemoPhase.baselineMeasurement:
        icon = Icons.straighten_outlined;
        label = 'Baseline Measurement';
        color = Colors.blue;
        if (_demoPhaseStartTime != null) {
          final elapsed = DateTime.now().difference(_demoPhaseStartTime!);
          final progress = (elapsed.inMilliseconds /
                  DemoConfig.baselineDuration.inMilliseconds)
              .clamp(0.0, 1.0);
          trailing = SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: progress,
              color: color,
              backgroundColor: color.withOpacity(0.2),
            ),
          );
        }
        break;
      case DemoPhase.monitoring:
        icon = Icons.monitor_heart_outlined;
        label = 'Monitoring';
        color = Colors.green;
        break;
      case DemoPhase.meditationSession:
        icon = Icons.self_improvement_outlined;
        label = 'Meditation';
        color = Colors.purple;
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
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
      // Only create the sensor object — the PPG hardware is NOT configured here.
      // _configurePpgSensor() and sensor.start() are deferred to _activateEarStream()
      // so no physical PPG stream starts until the user explicitly requests it.
      print('Earable available — creating sensor object (PPG not yet started)');
      try {
        _sensor = EarableHrSensor(
          ppgSensor: widget.ppgSensor!,
          wearable: widget.wearable!,
          sensorManager: widget.sensorManager,
          sampleFreq: BiosignalConfig.ppgSamplingFrequency,
          configProvider: widget.sensorConfigProvider,
        );
        setState(() {
          _useMockSensor = false;
        });
        return;
      } catch (e) {
        print('Earable sensor creation failed: $e — falling back to mock');
      }
    }

    // Fallback to mock sensor when no earable is available.
    print('Starting with mock sensor (created, not yet started)');
    _sensor = MockHrSensor();
    _useMockSensor = true;
    // Sensor will be started when EarStream is activated.
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

      // Only start measurements if EarStream is already active
      // (e.g. user swaps from mock to earable mid-session).
      if (_earStreamActivated) {
        print('=== STARTING EARABLE SENSOR (EarStream already active) ===');
        await _sensor!.start();
        _startMonitoring();
        print('✓ Earable sensor started and monitoring resumed');
      } else {
        print('✓ Earable sensor created — measurements start when EarStream is activated');
      }

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

    // Only restart measurements if EarStream was active.
    if (_earStreamActivated) {
      print('>>> Starting mock sensor (reset)...');
      await _sensor!.start();
      _startMonitoring();
      print('✓ Mock sensor started (reset)');
    }

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
                // Demo is managed on the main screen — close this page and return
                if (mode == MeditationAppMode.test) {
                  Navigator.of(context).pop();
                  return;
                }
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
                            Navigator.of(context).pop();
                            await _startTimerNow();
                          },
                        ),
                      if (localSelectedMode == MeditationAppMode.test)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Demo mode is active on the main screen. Return there to start a demo.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.4,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
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

  void _selectDemoMode(String mode) {
    setState(() {
      _demoSubMode = mode;
      // Both modes start with preference selection
      _demoPhase = DemoPhase.settingPreferences;
    });
  }

  Future<void> _openDemoPreferences() async {
    final prefs = await Navigator.push<DemoMeditationPreferences>(
      context,
      MaterialPageRoute(
        builder: (context) => _DemoPreferencesPage(
          isBiosignalAdaptive:
              _demoSubMode == DemoConfig.modeBiosignalAdaptive,
        ),
      ),
    );

    if (prefs == null || !mounted) return;

    setState(() {
      _demoPreferences = prefs;
    });

    if (_demoSubMode == DemoConfig.modePersonalizedOnly) {
      _startPersonalizedOnlyMeditation();
    } else {
      await _proceedToSealCheck();
    }
  }

  Future<void> _proceedToSealCheck() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _SealCheckPage(wearable: widget.wearable),
      ),
    );
    if (!mounted) return;
    // Start calibration after returning from the seal check page
    _proceedToCalibration();
  }

  void _proceedToCalibration() {
    setState(() {
      _demoPhase = DemoPhase.calibration;
      _demoPhaseStartTime = DateTime.now();
    });

    // Automatically activate EarStream monitoring
    if (!_earStreamActivated && _sensor != null) {
      _activateEarStream();
    }

    // Auto-advance to baseline when calibration finishes
    _demoPhaseTimer?.cancel();
    _demoPhaseTimer = Timer(DemoConfig.calibrationDuration, () {
      if (mounted && _demoPhase == DemoPhase.calibration) {
        _proceedToBaselineMeasurement();
      }
    });
  }

  void _proceedToBaselineMeasurement() {
    setState(() {
      _demoPhase = DemoPhase.baselineMeasurement;
      _demoPhaseStartTime = DateTime.now();
      _demoBaselineHr = null;
      _demoBaselineRmssd = null;
    });

    // Auto-advance to monitoring when baseline finishes
    _demoPhaseTimer?.cancel();
    _demoPhaseTimer = Timer(DemoConfig.baselineDuration, () {
      if (mounted && _demoPhase == DemoPhase.baselineMeasurement) {
        final capturedHr = _currentHr > 0 ? _currentHr : DemoConfig.fallbackBaselineHr;
        final capturedRmssd = _currentHrv > 0 ? _currentHrv : DemoConfig.fallbackBaselineRmssd;
        setState(() {
          _demoBaselineHr = capturedHr;
          _demoBaselineRmssd = capturedRmssd;
        });
        _proceedToMonitoring();
      }
    });
  }

  void _proceedToMonitoring() {
    setState(() {
      _demoPhase = DemoPhase.monitoring;
      _demoPhaseStartTime = DateTime.now();
    });
    
    // Start periodic stress checking (every 3 seconds) with auto-detection
    _demoPhaseTimer?.cancel();
    _demoPhaseTimer = Timer.periodic(DemoConfig.monitoringCheckInterval, (timer) {
      _checkDemoStressLevel();
    });
    
    // Also trigger automatically after maxMonitoringDuration so every attendee
    // experiences the full demo even when stress threshold is not met.
    Timer(DemoConfig.maxMonitoringDuration, () {
      if (mounted && _demoPhase == DemoPhase.monitoring) {
        print('Demo: Max monitoring duration reached — auto-triggering meditation');
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
    
    // Both HR elevation AND HRV decrease must exceed threshold to trigger meditation
    final isStressed = hrDeviation >= DemoConfig.stressThresholdPercent &&
                       rmssdDeviation >= DemoConfig.stressThresholdPercent;
    
    if (isStressed) {
      print('Demo Auto-Stress Detected! HR deviation: ${hrDeviation.toStringAsFixed(1)}%, '
            'RMSSD deviation: ${rmssdDeviation.toStringAsFixed(1)}%');
      _startBiosignalAdaptiveMeditation();
    }
  }

  void _manuallyTriggerMeditation() {
    print('Demo: Manual meditation trigger');
    _startBiosignalAdaptiveMeditation();
  }

  void _startPersonalizedOnlyMeditation() {
    print('[EARSTREAM] _startPersonalizedOnlyMeditation() — earStreamActivated=$_earStreamActivated, sensor=$_sensor');
    setState(() {
      _demoPhase = DemoPhase.meditationSession;
    });
    
    // Ensure sensor and monitoring are active
    if (!_earStreamActivated && _sensor != null) {
      _activateEarStream();
    }
  }

  void _startBiosignalAdaptiveMeditation() {
    print('[EARSTREAM] _startBiosignalAdaptiveMeditation() — earStreamActivated=$_earStreamActivated, sensor=$_sensor');
    _demoPhaseTimer?.cancel();
    setState(() {
      _demoPhase = DemoPhase.meditationSession;
    });
  }

  void _onDemoMeditationComplete() {
    setState(() {
      _demoPhase = DemoPhase.analytics;
    });
    
    // Show analytics briefly, then wait for manual reset
    // (Analytics are shown by the meditation widget automatically)
  }

  void _returnToDemoSelection() {
    _resetDemoMode();
    setState(() {
      _isDemoModeActive = true;
      _demoPhase = DemoPhase.modeSelection;
    });
  }

  /// Called after the demo mood emoji is tapped.
  /// Stops sensor streams, deactivates EarStream, and returns to demo selection.
  void _onDemoSessionEnd() {
    _demoPhaseTimer?.cancel();
    _deactivateEarStream();
    _returnToDemoSelection();
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

  // ============================================================================
  // LEGACY DEMO MODE FLOWS (TO BE REMOVED)
  // ============================================================================

  Future<void> _startPersonalizedOnlyDemo() async {
    // Legacy method - replaced by _selectDemoMode and manual flow
    _selectDemoMode(DemoConfig.modePersonalizedOnly);
  }

  Future<void> _startBiosignalAdaptiveDemo() async {
    // Legacy method - replaced by _selectDemoMode and manual flow
    _selectDemoMode(DemoConfig.modeBiosignalAdaptive);
  }

  Future<DemoMeditationPreferences?> _showDemoPreferencesDialog() async {
    // Legacy method - now using existing preferences UI
    return DemoMeditationPreferences.defaults();
  }

  void _startCalibrationPhase() {
    // Legacy method - now using manual flow with _proceedToCalibration
    _proceedToCalibration();
  }

  void _startBaselineMeasurementPhase() {
    // Legacy method - now using manual flow with _proceedToBaselineMeasurement
    _proceedToBaselineMeasurement();
  }

  void _captureBaselineAndStartMonitoring() {
    // Legacy method - baseline capture now happens in timer callback
    // Monitoring starts with _proceedToMonitoring
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

                          // Demo Control Panel - Shown when demo mode active
                          if (_isDemoModeActive && _demoPhase != DemoPhase.none)
                            _buildDemoControlPanel(),
                          if (_isDemoModeActive && _demoPhase != DemoPhase.none)
                            const SizedBox(height: 16),

                          // HR/HRV Display — only rendered once EarStream is active.
                          // Never shown in personalized-only demo mode or during
                          // mode selection.
                          if (_earStreamActivated &&
                              (!_isDemoModeActive ||
                                  (_demoPhase != DemoPhase.none &&
                                      _demoPhase != DemoPhase.modeSelection &&
                                      _demoSubMode !=
                                          DemoConfig.modePersonalizedOnly)))
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
                              showMonitoring: _selectedMode == MeditationAppMode.normal && _earStreamActivated,
                              isMeditationSessionActive: _isMeditationSessionActive,
                            ),
                          if (!_isDemoModeActive || 
                              (_demoPhase != DemoPhase.none && _demoPhase != DemoPhase.modeSelection))
                            const SizedBox(height: 16),

                          // Meditation Widget - Only shown during meditation session
                          if (_sensor != null &&
                              _demoPhase == DemoPhase.meditationSession &&
                              _earStreamActivated)
                            LlmMeditationWidget(
                              key: _meditationWidgetKey,
                              sensor: _sensor!,
                              onBeforeStartMeditation:
                                  _ensureMeditationCanStart,
                              stressDetectionEnabled:
                                  _demoSubMode == DemoConfig.modeBiosignalAdaptive,
                              onReset: _onDemoSessionEnd,
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
                          
                          // Normal mode meditation widget
                          if (_sensor != null &&
                              !_isDemoModeActive &&
                              _selectedMode != MeditationAppMode.test &&
                              (_earStreamActivated || _selectedMode == MeditationAppMode.timer))
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
                              onMeditationSessionActive: (active) {
                                if (mounted) {
                                  setState(() {
                                    _isMeditationSessionActive = active;
                                  });
                                }
                              },
                              demoMode: DemoConfig.modeNone,
                              demoPreferences: null,
                              demoBaselineHr: null,
                              demoBaselineRmssd: null,
                              onDemoComplete: null,
                            ),

                          const SizedBox(height: 16),

                          // Timer mode card — shown inline on main screen when Timed mode is selected
                          if (!_isDemoModeActive && _selectedMode == MeditationAppMode.timer)
                            _buildTimerModeCard(
                              scheduledTime: _timerModeScheduledTime,
                              onScheduleAfter: (delay) async {
                                final scheduled = await _scheduleTimerModeAfter(delay);
                                if (scheduled != null && mounted) {
                                  setState(() {}); // Refresh to show scheduled time
                                  _showSuccessSnackbar(
                                    'Timer meditation scheduled in ${delay.inMinutes} minutes.',
                                  );
                                }
                              },
                              onPickTime: () async {
                                final scheduled = await _pickAndScheduleTimerModeTime();
                                if (scheduled != null && mounted) {
                                  setState(() {});
                                  _showSuccessSnackbar(
                                    'Timer meditation scheduled for ${_formatScheduledTime(scheduled)}.',
                                  );
                                }
                              },
                              onCancelSchedule: () {
                                _clearTimerModeSchedule();
                                setState(() {});
                                _showSuccessSnackbar('Scheduled timer cleared.');
                              },
                              onStartNow: () => unawaited(_startTimerNow()),
                            ),
                          if (!_isDemoModeActive && _selectedMode == MeditationAppMode.timer)
                            const SizedBox(height: 8),

                          if (!_isDemoModeActive && _selectedMode != MeditationAppMode.test && _selectedMode != MeditationAppMode.timer) ...[
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

                          if (!_isDemoModeActive)
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

class _DemoPreferencesPage extends StatefulWidget {
  final bool isBiosignalAdaptive;
  const _DemoPreferencesPage({required this.isBiosignalAdaptive});

  @override
  State<_DemoPreferencesPage> createState() => _DemoPreferencesPageState();
}

class _DemoPreferencesPageState extends State<_DemoPreferencesPage> {
  String _meditationType = 'mindfulness';
  String _voiceGender = 'female';
  String _speakingSpeed = 'slow';
  String _environment = 'peaceful nature';

  static const _types = [
    ('mindfulness', '🧘 Mindfulness'),
    ('breathing', '🌬️ Breathing'),
    ('body_scan', '💆 Body Scan'),
    ('visualization_journey', '🌅 Visualization Journey'),
  ];
  static const _environments = [
    ('peaceful nature', '🌳 Peaceful Nature'),
    ('calm ocean beach', '🌊 Ocean Beach'),
    ('quiet mountain', '⛰️ Mountain'),
    ('serene forest', '🌲 Forest'),
    ('gentle garden', '🌸 Garden'),
  ];

  void _surpriseMe() {
    final prefs = DemoMeditationPreferences.random();
    setState(() {
      _meditationType = prefs.meditationStyle;
      _voiceGender = prefs.voiceGender;
      _speakingSpeed = prefs.speakingSpeed;
      _environment = prefs.meditationEnvironment;
    });
  }

  void _confirm() {
    Navigator.of(context).pop(DemoMeditationPreferences(
      meditationStyle: _meditationType,
      voiceGender: _voiceGender,
      speakingSpeed: _speakingSpeed,
      meditationEnvironment: _environment,
    ));
  }

  static InputDecoration _dropdownDecoration() => InputDecoration(
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextLabel = widget.isBiosignalAdaptive
        ? 'Proceed to Seal Check →'
        : 'Start Meditation →';

    return Scaffold(
      appBar: EarStreamStyle.appBar(context, title: 'Demo Preferences'),
      body: ListView(
        padding: EarStreamStyle.pagePadding(context),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose your demo meditation experience',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'These settings are session-only and won\'t affect your saved preferences.',
                    style: TextStyle(color: Colors.grey[700], height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _surpriseMe,
                      icon: const Icon(Icons.casino_outlined),
                      label: const Text('🎲  Surprise me!'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Voice Gender',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _voiceGender,
                    decoration: _dropdownDecoration(),
                    items: const [
                      DropdownMenuItem(value: 'female', child: Text('👩 Female')),
                      DropdownMenuItem(value: 'male', child: Text('👨 Male')),
                    ],
                    onChanged: (v) => setState(() => _voiceGender = v!),
                  ),
                  const SizedBox(height: 20),
                  const Text('Speaking Speed',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _speakingSpeed,
                    decoration: _dropdownDecoration(),
                    items: const [
                      DropdownMenuItem(value: 'very_slow', child: Text('🐌 Very Slow')),
                      DropdownMenuItem(value: 'slow', child: Text('🐢 Slow (Recommended)')),
                      DropdownMenuItem(value: 'medium', child: Text('🚶 Medium')),
                      DropdownMenuItem(value: 'fast', child: Text('🏃 Fast')),
                    ],
                    onChanged: (v) => setState(() => _speakingSpeed = v!),
                  ),
                  const SizedBox(height: 20),
                  const Text('Meditation Type',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _meditationType,
                    decoration: _dropdownDecoration(),
                    items: _types
                        .map((t) => DropdownMenuItem(
                            value: t.$1, child: Text(t.$2)))
                        .toList(),
                    onChanged: (v) => setState(() => _meditationType = v!),
                  ),
                  const SizedBox(height: 20),
                  const Text('Environment',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _environment,
                    decoration: _dropdownDecoration(),
                    items: _environments
                        .map((e) => DropdownMenuItem(
                            value: e.$1, child: Text(e.$2)))
                        .toList(),
                    onChanged: (v) => setState(() => _environment = v!),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.arrow_forward),
              label: Text(nextLabel),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ================================================================================
// SEAL CHECK PAGE (Biosignal-Adaptive demo — Step 2 of 5)
// ================================================================================

class _SealCheckPage extends StatefulWidget {
  final Wearable? wearable;
  const _SealCheckPage({required this.wearable});

  @override
  State<_SealCheckPage> createState() => _SealCheckPageState();
}

class _SealCheckPageState extends State<_SealCheckPage> {
  bool _sealCheckRan = false;

  Future<void> _runSealCheck() async {
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

    final audioManager =
        widget.wearable!.requireCapability<AudioResponseManager>();
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
    if (mounted) {
      setState(() => _sealCheckRan = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: EarStreamStyle.appBar(context, title: 'Step 2 of 5 · Seal Check'),
      body: ListView(
        padding: EarStreamStyle.pagePadding(context),
        children: [
          // Why seal check
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_outlined,
                          color: colorScheme.primary, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Why run a seal check?',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A good acoustic seal is essential for accurate heart rate and HRV measurements. '
                    'The seal check plays a brief tone through the earable and analyses the acoustic '
                    'response to confirm that the earable sits correctly in your ear.',
                    style: TextStyle(color: Colors.grey[700], height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Run seal check action
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Run the seal check',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Put on the OpenEarable, then tap the button below. '
                    'A short tone will be played — stay still during the measurement. '
                    'You can run the check as many times as needed.',
                    style: TextStyle(color: Colors.grey[700], height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _runSealCheck,
                      icon: const Icon(Icons.hearing_outlined),
                      label: const Text('Run Seal Check'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_sealCheckRan) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.green.shade600, size: 20),
                        const SizedBox(width: 8),
                        const Text('Seal check completed successfully.'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Primary CTA
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.sensors_outlined),
              label: const Text('Start EarStream →'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Skip seal check'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

