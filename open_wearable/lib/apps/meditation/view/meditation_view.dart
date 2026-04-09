import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import '../model/mock_hr_sensor.dart';
import '../model/earable_hr_sensor.dart';
import '../model/hr_sensor_interface.dart';
import '../model/activity_detector.dart';
import '../widgets/hr_hrv_display_new.dart';
import '../widgets/llm_meditation_widget.dart';
import '../model/user_account.dart';
import '../widgets/user_onboarding_screen.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

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

class _MeditationViewState extends State<MeditationView> {
  HrSensorInterface? _sensor;
  bool _useMockSensor = true;
  Key? _meditationWidgetKey = UniqueKey(); // Generate new key when sensor changes to force rebuild
  
  double _currentHr = 75.0;
  double _currentHrv = -1.0; // -1 means no data yet (RMSSD)
  double _currentSdnn = -1.0; // -1 means no data yet (SDNN - comparable to Apple Health)
  bool _hrvIsStable = false; // Track if HRV measurements are reliable
  int _hrvMeasurementCount = 0; // Count HRV measurements received
  int _measurementDurationSeconds = 0; // Track how long we've been measuring
  Timer? _measurementTimer; // Timer to track measurement duration
  
  StreamSubscription<double>? _hrSubscription;
  StreamSubscription<Map<String, double>>? _hrvSubscription;
  StreamSubscription<bool>? _connectionSubscription; // Monitor connection state
  
  String _stressLevel = 'normal'; // Track stress level: 'relaxed', 'normal', or 'stressed'
  
  @override
  void initState() {
    super.initState();
    _initializeSensor();
  }
  
  Future<void> _initializeSensor() async {
    // Don't reinitialize if sensor is already set
    // (e.g., after switching to earable sensor)
    if (_sensor != null) {
      print('Sensor already initialized ($_sensor.runtimeType), skipping initialization');
      return;
    }
    
    // Always start with mock sensor
    // User can manually switch to earable by pressing "Use Earable" button
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
        configProvider.addSensorConfigurationOption(configuration, StreamSensorConfigOption());
        print('Added stream configuration option');
      }

      // Konfiguration setzen - WICHTIG: Nur "stream" Modi, NICHT "off"!
      List<SensorConfigurationValue> values = configProvider.getSensorConfigurationValues(configuration, distinct: true);
      
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
        print('Found ${streamingValues.length} streaming PPG configs: $streamingValues');
        // Use the first streaming configuration
        configProvider.addSensorConfiguration(configuration, streamingValues.first);
      }
      
      SensorConfigurationValue selectedValue = configProvider.getSelectedConfigurationValue(configuration)!;
      
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
  
  Future<void> _switchToEarableSensor() async {
    if (widget.ppgSensor == null) {
      _showErrorDialog('No earable device connected. Please connect an OpenEarable device first.');
      return;
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
        final value = widget.sensorConfigProvider!.getSelectedConfigurationValue(config);
        if (value is SensorFrequencyConfigurationValue) {
          sampleFreq = value.frequencyHz;
          print('Using sample frequency: $sampleFreq Hz');
          break;
        }
      }
    }
    
    // Create real sensor
    if (widget.wearable == null) {
      _showErrorDialog('Internal Error: Wearable instance not found.');
      return;
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
        _meditationWidgetKey = UniqueKey(); // Force widget rebuild with new sensor
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
      _showErrorDialog('Failed to start earable sensor: $e');
      return;
    }
    
    // Show success message only if widget is still mounted
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSuccessSnackbar('Now using real earable data!');
        }
      });
    }
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
          print('✅ HRV measurements now stable ($_hrvMeasurementCount measurements received)');
          print('   RMSSD: ${_currentHrv.toStringAsFixed(1)} ms, SDNN: ${_currentSdnn >= 0 ? _currentSdnn.toStringAsFixed(1) : "pending"} ms');
        }
        
        // Log HRV updates for debugging
        if (_hrvMeasurementCount % 5 == 0) {
          print('📊 HRV Update #$_hrvMeasurementCount: RMSSD=${_currentHrv.toStringAsFixed(1)}ms, SDNN=${_currentSdnn >= 0 ? _currentSdnn.toStringAsFixed(1) : "pending"}ms, stable=$_hrvIsStable');
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
            duration: const Duration(days: 1), // Persistent until dismissed or reconnected
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
      print('Simulating stress: HR -> 100 BPM, HRV -> 12 ms (triggers stress detection!)');
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
      _meditationWidgetKey = UniqueKey();
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
    
    print('Reset complete! Back to mock sensor. _useMockSensor = $_useMockSensor');
    _showSuccessSnackbar('Reset to baseline (HR: 75, HRV: 120) and cleared all timers');
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
  
  Future<void> _openProfileSettings() async {
    // Load current UserAccount
    final currentAccount = await UserAccount.load();
    
    if (mounted) {
      // Navigate to onboarding screen with existing account
      final updatedAccount = await Navigator.push<UserAccount>(
        context,
        MaterialPageRoute(
          builder: (context) => UserOnboardingScreen(existingAccount: currentAccount),
        ),
      );
      
      // If account was updated, update the meditation widget directly
      if (updatedAccount != null && mounted) {
        // Note: Can't access currentState anymore since we use UniqueKey
        // await _meditationWidgetKey.currentState?.updateSettings(updatedAccount);
        _showSuccessSnackbar('Settings saved! Voice and preferences updated.');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Meditation'),
        trailingActions: [
          PlatformIconButton(
            materialIcon: const Icon(Icons.settings, color: Colors.white),
            cupertinoIcon: Icon(PlatformIcons(context).settings),
            onPressed: _openProfileSettings,
          ),
        ],
        material: (_, __) => MaterialAppBarData(
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HrHrvDisplayNew(
                            hr: _currentHr,
                            hrv: _currentHrv,
                            sdnn: _currentSdnn,
                            stressLevel: _stressLevel,
                            isHrvStable: _hrvIsStable,
                            measurementDurationSeconds: _measurementDurationSeconds,
                            activityLevel: _sensor is EarableHrSensor ? (_sensor as EarableHrSensor).activityLevel.name : null,
                            activityDescription: _sensor is EarableHrSensor ? _getActivityDescription((_sensor as EarableHrSensor).activityLevel) : null,
                          ),
                          const SizedBox(height: 16),
                          
                          // AI-Powered Meditation (always active)
                          if (_sensor != null)
                            LlmMeditationWidget(
                              key: _meditationWidgetKey,
                              sensor: _sensor!,
                              onReset: _resetToBaseline,
                              onStressLevelChanged: (level) {
                                if (mounted) {
                                  setState(() {
                                    _stressLevel = level;
                                  });
                                }
                              },
                            ),
                          
                          const SizedBox(height: 16),
                          
                          // Development/Testing Controls (always visible for testing)
                          Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    print('🔘 USE EARABLE BUTTON PRESSED');
                                    print('   ppgSensor: ${widget.ppgSensor != null ? "available" : "NULL"}');
                                    print('   _useMockSensor: $_useMockSensor');
                                    print('   wearable: ${widget.wearable != null ? "available" : "NULL"}');
                                    
                                    if (widget.ppgSensor == null) {
                                      print('   ❌ Cannot switch: ppgSensor is NULL');
                                      _showErrorDialog('PPG Sensor not available. Please ensure earable is connected.');
                                      return;
                                    }
                                    
                                    if (!_useMockSensor) {
                                      print('   ⚠️ Already using earable sensor');
                                      return;
                                    }
                                    
                                    print('   ✅ Calling _switchToEarableSensor()');
                                    _switchToEarableSensor();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _useMockSensor ? Colors.blue[100] : Colors.green[100],
                                    foregroundColor: _useMockSensor ? Colors.blue[900] : Colors.green[900],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text(_useMockSensor ? 'Use Earable' : '✓ Earable Active'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _useMockSensor && _sensor is MockHrSensor 
                                      ? _simulateStress
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange[100],
                                    foregroundColor: Colors.orange[900],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Reset'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _useMockSensor && _sensor is MockHrSensor 
                                      ? _simulateRelaxation
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green[100],
                                    foregroundColor: Colors.green[900],
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    disabledBackgroundColor: Colors.grey[300],
                                    disabledForegroundColor: Colors.grey[600],
                                  ),
                                  child: const Text('Simulate Relax'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }  @override
  void dispose() {
    _measurementTimer?.cancel();
    _hrSubscription?.cancel();
    _hrvSubscription?.cancel();
    _connectionSubscription?.cancel();
    _sensor?.dispose();
    // _audioPlayer.dispose(); // Removed
    super.dispose();
  }
}
