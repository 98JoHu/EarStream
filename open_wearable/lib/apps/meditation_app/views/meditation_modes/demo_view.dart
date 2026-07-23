import 'package:flutter/material.dart';
import '../../model/user_account.dart'
    show Gender, SpeakingSpeed, MeditationType, MeditationEnvironment;
import '../../widgets/custom_dropdown.dart';

enum Step {
  settings(
    content: SettingsView(),
  ),
  sealCheck(
    content: Text(
      "Seal check step content goes here. This is a placeholder for the actual seal check view.",
      style: TextStyle(
        fontSize: 16,
        height: 1.5,
      ),
    ),
  ),
  meditation(
    content: Text(
      "Meditation step content goes here. This is a placeholder for the actual meditation view.",
      style: TextStyle(
        fontSize: 16,
        height: 1.5,
      ),
    ),
  );

  final Widget content;

  const Step({required this.content});
}

enum DemoMode {
  biosignalAdaptive(steps: [Step.settings, Step.sealCheck, Step.meditation]),
  personalizedOnly(steps: [Step.settings, Step.meditation]);

  final List<Step> steps;

  const DemoMode({required this.steps});
}

class DemoView extends StatefulWidget {
  const DemoView({super.key});

  @override
  State<DemoView> createState() => _DemoViewState();
}

class _DemoViewState extends State<DemoView> {
  DemoMode? _selectedMode;
  int _currentStepIndex = 0;

  List<Step> get _steps => _selectedMode!.steps;
  Step get _currentStep => _steps[_currentStepIndex];

  void _selectMode(DemoMode mode) {
    setState(() {
      _selectedMode = mode;
      _currentStepIndex = 0;
    });
  }

  void _continue() {
    if (_currentStepIndex < _steps.length - 1) {
      setState(() {
        _currentStepIndex++;
      });
    }
  }

  void _skip() {
    if (_currentStep == Step.sealCheck) {
      setState(() {
        _currentStepIndex++;
      });
    }
  }

  void _back() {
    if (_currentStepIndex > 0) {
      setState(() {
        _currentStepIndex--;
      });
    } else {
      setState(() {
        _selectedMode = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: _selectedMode == null ? _selection() : _stepContent()),
    );
  }

  Widget _selection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              // TODO: Scale image accordingly
              child: Image.asset(
                "lib/apps/meditation_app/assets/ubicomp_logo.png",
                width: 40,
                height: 40,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                "ACM UbiComp 2026 Demo",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        Text(
          "Welcome to EarStream! This demo lets you experience a closed-loop earable system for stress-adaptive meditation. Please choose between two demo modes to start your experience.",
          style: TextStyle(
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => {
              _selectMode(DemoMode.biosignalAdaptive),
            },
            icon: const Icon(Icons.monitor_heart_outlined),
            label: const Text('Biosignal-Adaptive Demo'),
            style: ElevatedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _selectMode(DemoMode.personalizedOnly),
            icon: const Icon(Icons.account_circle_outlined),
            label: const Text('Personalized Meditation Only'),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepContent() {
    if (_currentStep == Step.meditation) {
      return Text(
        "Meditation session in progress... (This is a placeholder for the actual meditation session view.)",
        style: TextStyle(
          fontSize: 16,
          height: 1.5,
        ),
      );
    }
    // Return content for other steps as needed
    return Column(
      children: [
        _currentStep.content,
        const SizedBox(height: 24),
        _navigationButtons(),
      ],
    );
  }

  Widget _navigationButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        OutlinedButton(
          onPressed: _back,
          child: const Text('Back'),
        ),
        if (_currentStep == Step.sealCheck)
          OutlinedButton(onPressed: _skip, child: const Text('Skip')),
        ElevatedButton(
          onPressed: _continue,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.spa_outlined,
                    color: Theme.of(context).colorScheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Meditation Preferences',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Text(
            'Please put in your preferences for your upcoming personalized meditation.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              // TODO: add functionality to randomize preferences
              onPressed: () {},
              icon: const Icon(Icons.casino_outlined),
              label: const Text('Surprise me'),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Voice Gender',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          VoiceGenderDropdown(
            initialSelection: Gender.female,
            onSelected: (value) {
              // TODO: Handle voice gender
            },
          ),
          const SizedBox(height: 24),
          const Text('Speaking Speed',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SpeakingSpeedDropdown(
            initialSelection: SpeakingSpeed.slow,
            onSelected: (value) {
              // TODO: Handle speaking speed
            },
          ),
          const SizedBox(height: 24),
          const Text('Meditation Type',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          MeditationTypeDropdown(
            initialSelection: MeditationType.mindfulness,
            onSelected: (value) {
              // TODO: Handle meditation type
            },
          ),
          const SizedBox(height: 24),
          const Text('Meditation Environment',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          MeditationEnvironmentDropdown(
            initialSelection: MeditationEnvironment.nature,
            onSelected: (value) {
              // TODO: Handle meditation environment
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
