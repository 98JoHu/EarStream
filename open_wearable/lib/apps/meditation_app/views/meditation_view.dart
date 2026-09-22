import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';
import '../model/user_account.dart';
import '../model/meditation_analytics.dart';
import '../model/screen_wakelock.dart';
import 'pages/drawer_page.dart';
import 'pages/meditation_page.dart';
import 'pages/profile_page.dart';
import 'pages/preferences_page.dart';
import 'pages/weekly_analytics_page.dart';
import 'pages/seal_check_page.dart';
import 'pages/api_keys_page.dart';

class MeditationView extends StatefulWidget {
  final Sensor ppgSensor;
  final Sensor accelerometerSensor;
  final Sensor gyroscopeSensor;
  final SensorConfigurationProvider sensorConfigProvider;
  final Wearable? wearable;

  const MeditationView({
    super.key,
    required this.ppgSensor,
    required this.accelerometerSensor,
    required this.gyroscopeSensor,
    required this.sensorConfigProvider,
    this.wearable,
  });

  @override
  State<MeditationView> createState() => _MeditationViewState();
}

class _MeditationViewState extends State<MeditationView> {
  int _selectedIndex = 0;
  MeditationMode? _selectedMode;
  late final UserAccount _userAccount;
  late final MeditationAnalyticsStore _analyticsStore;

  @override
  void initState() {
    super.initState();
    _userAccount = UserAccount.fromEnvironment(dotenv.env);
    _analyticsStore = MeditationAnalyticsStore()..load();
    // A session waits minutes on DeepSeek and text-to-speech with no touch
    // input; Android suspends those requests once the screen turns off.
    unawaited(ScreenWakelock.acquire());
  }

  List<DrawerPage> get _pages => [
        MeditationPage(
          ppgSensor: widget.ppgSensor,
          accelerometerSensor: widget.accelerometerSensor,
          gyroscopeSensor: widget.gyroscopeSensor,
          sensorConfigProvider: widget.sensorConfigProvider,
          userAccount: _userAccount,
          analyticsStore: _analyticsStore,
          wearable: widget.wearable,
          selectedMode: _selectedMode,
          onModeSelected: (mode) => setState(() => _selectedMode = mode),
        ),
        ProfilePage(userAccount: _userAccount),
        PreferencesPage(userAccount: _userAccount),
        WeeklyAnalyticsPage(analyticsStore: _analyticsStore),
        SealCheckPage(wearable: widget.wearable),
        ApiKeysPage(userAccount: _userAccount),
      ];

  @override
  void dispose() {
    unawaited(ScreenWakelock.release());
    _analyticsStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;

    return Scaffold(
      appBar: AppBar(
        title: const Text("EarStreAM"),
      ),
      endDrawer: SafeArea(
        child: NavigationDrawer(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            setState(() {
              if (index == 0) {
                // Always land back on the mode picker, even if the meditation
                // page was already the selected one. Clearing this also
                // unmounts the running mode view, disposing its measurement.
                _selectedMode = null;
              }
              _selectedIndex = index;
            });
            // Close the drawer after selecting a destination
            Navigator.of(context).pop();
          },
          header: DrawerHeader(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
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
                    'lib/apps/meditation_app/assets/earstream_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                Text(
                  'EarStreAM',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Stress-adaptive meditation sessions',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              ],
            ),
          ),
          children: pages.map((DrawerPage page) {
            return NavigationDrawerDestination(
              icon: Icon(page.icon),
              label: Text(page.label),
              selectedIcon: Icon(page.selectedIcon),
            );
          }).toList(),
        ),
      ),
      body: SafeArea(child: pages[_selectedIndex]),
    );
  }
}
