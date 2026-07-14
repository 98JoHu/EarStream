import 'package:flutter/material.dart';
import 'drawer_page.dart';
import '../../model/user_account.dart';
import '../../widgets/emojis.dart';
import '../../widgets/custom_dropdown.dart';

class PreferencesPage extends StatefulWidget implements DrawerPage {
  final UserAccount userAccount;
  const PreferencesPage({super.key, required this.userAccount});

  @override
  String get label => "Meditation Preferences";

  @override
  IconData get icon => Icons.spa_outlined;

  @override
  IconData get selectedIcon => Icons.spa;

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _additionalPreferencesController;
  late String _voiceGender;
  late String _speakingSpeed;
  late String _meditationType;
  late MeditationEnvironment _meditationEnvironment;
  late double _stressThreshold;

  static const genderOptions = [
    DropdownMenuEntry(
      value: 'female',
      label: '${AppEmojis.female} Female',
    ),
    DropdownMenuEntry(
      value: 'male',
      label: '${AppEmojis.male} Male',
    ),
  ];
  static const speakingSpeedOptions = [
    DropdownMenuEntry(
      value: 'very slow',
      label: '${AppEmojis.snail} Very Slow',
    ),
    DropdownMenuEntry(
      value: 'slow',
      label: '${AppEmojis.turtle} Slow (Recommended)',
    ),
    DropdownMenuEntry(
      value: 'medium',
      label: '${AppEmojis.walkingPerson} Medium',
    ),
    DropdownMenuEntry(
      value: 'fast',
      label: '${AppEmojis.runningPerson} Fast',
    ),
  ];
  static const meditationTypeOptions = [
    DropdownMenuEntry(
      value: 'mindfulness',
      label: '${AppEmojis.meditatingPerson} Mindfulness',
    ),
    DropdownMenuEntry(
      value: 'breathing',
      label: '${AppEmojis.breathing} Breathing',
    ),
    DropdownMenuEntry(
      value: 'body_scan',
      label: '${AppEmojis.bodyScan} Body Scan',
    ),
    DropdownMenuEntry(
      value: 'visualization_journey',
      label: '${AppEmojis.visualizationJourney} Visualization Journey',
    ),
  ];
  static const meditationEnvironmentOptions = [
    DropdownMenuEntry(
      value: MeditationEnvironment.nature,
      label: '${AppEmojis.tree} Peaceful nature',
    ),
    DropdownMenuEntry(
      value: MeditationEnvironment.ocean,
      label: '${AppEmojis.wave} Ocean beach',
    ),
    DropdownMenuEntry(
      value: MeditationEnvironment.mountain,
      label: '${AppEmojis.mountain} Mountain',
    ),
    DropdownMenuEntry(
      value: MeditationEnvironment.forest,
      label: '${AppEmojis.forest} Forest',
    ),
    DropdownMenuEntry(
      value: MeditationEnvironment.garden,
      label: '${AppEmojis.cherryBlossom} Garden',
    ),
  ];
  static const stressThresholdOptions = [
    DropdownMenuEntry(
      value: 0.05,
      label: '${AppEmojis.chart} 5% - Very Sensitive',
    ),
    DropdownMenuEntry(
      value: 0.10,
      label: '${AppEmojis.chart} 10% - Recommended',
    ),
    DropdownMenuEntry(
      value: 0.15,
      label: '${AppEmojis.chart} 15% - Moderate',
    ),
    DropdownMenuEntry(
      value: 0.20,
      label: '${AppEmojis.chart} 20% - Less Sensitive',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _additionalPreferencesController = TextEditingController(
      text: widget.userAccount.additionalPreferences ?? '',
    );
    _voiceGender = widget.userAccount.voiceGender ?? 'female';
    _speakingSpeed = widget.userAccount.speakingSpeed ?? 'slow';
    _meditationType = widget.userAccount.meditationType ?? 'mindfulness';
    _meditationEnvironment = widget.userAccount.meditationEnvironment ??
        MeditationEnvironment.nature;
    _stressThreshold = widget.userAccount.stressThreshold ?? 0.10;
  }

  @override
  void dispose() {
    _additionalPreferencesController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        widget.userAccount.voiceGender = _voiceGender;
        widget.userAccount.speakingSpeed = _speakingSpeed;
        widget.userAccount.meditationType = _meditationType;
        widget.userAccount.meditationEnvironment = _meditationEnvironment;
        widget.userAccount.additionalPreferences =
            _additionalPreferencesController.text;
        widget.userAccount.stressThreshold = _stressThreshold;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix the errors in the form before saving.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Card(
          margin: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose the meditation experience',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'These settings stay optional at startup, but they shape the generated script, ambience, and voice delivery once a session begins.',
                    style: TextStyle(color: Colors.grey[700], height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Voice Gender',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FormDropdown<String>(
                    initialSelection: _voiceGender,
                    entries: genderOptions,
                    onSelected: (value) =>
                        setState(() => _voiceGender = value!),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Speaking Speed',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FormDropdown<String>(
                    initialSelection: _speakingSpeed,
                    entries: speakingSpeedOptions,
                    onSelected: (value) =>
                        setState(() => _speakingSpeed = value!),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Meditation Type',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FormDropdown<String>(
                    initialSelection: _meditationType,
                    entries: meditationTypeOptions,
                    onSelected: (value) =>
                        setState(() => _meditationType = value!),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Meditation Environment',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  FormDropdown<MeditationEnvironment>(
                    initialSelection: _meditationEnvironment,
                    entries: meditationEnvironmentOptions,
                    onSelected: (value) =>
                        setState(() => _meditationEnvironment = value!),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Additional Preferences',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _additionalPreferencesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText:
                          'e.g., "Focus on gratitude" or "Include affirmations"',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Stress Detection Threshold',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'How much must your heart rate increase (and HRV decrease) above baseline to be considered stressed?',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FormDropdown<double>(
                    initialSelection: _stressThreshold,
                    entries: stressThresholdOptions,
                    onSelected: (value) =>
                        setState(() => _stressThreshold = value!),
                  ),
                  const SizedBox(height: 24),
                  // TODO: Add eleven labs voice selection
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    onPressed: _saveProfile,
                    child: const Text(
                      'Save Profile',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
}
