import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'package:open_wearable/view_models/sensor_configuration_provider.dart';

abstract class DrawerPage extends StatelessWidget {
  const DrawerPage({super.key});

  String get label;
  IconData get icon;
  IconData get selectedIcon;
}

class MeditationView extends StatefulWidget {
  final Sensor? ppgSensor;
  final SensorConfigurationProvider? sensorConfigProvider;
  final SensorManager? sensorManager;
  final Wearable? wearable;

  const MeditationView({
    super.key,
    this.ppgSensor,
    this.sensorConfigProvider,
    this.sensorManager,
    this.wearable,
  });

  @override
  State<MeditationView> createState() => _MeditationViewState();
}

class _MeditationViewState extends State<MeditationView> {
  int _selectedIndex = 0;

  final List<DrawerPage> _pages = [
    const MeditationPage(),
    const ProfilePage(),
    const PreferencesPage(),
    const WeeklyAnalyticsPage(),
    const CalendarIntegrationPage(),
    const SealCheckPage(),
    const ApiKeysPage(),
    const DebugInfoPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("EarStreAM"),
      ),
      endDrawer: SafeArea(
        child: NavigationDrawer(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (int index) {
            setState(() {
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
          children: [
            ..._pages.map((DrawerPage page) {
              return NavigationDrawerDestination(
                icon: Icon(page.icon),
                label: Text(page.label),
              );
            }),
          ],
        ),
      ),
      body: _pages[_selectedIndex],
    );
  }
}
