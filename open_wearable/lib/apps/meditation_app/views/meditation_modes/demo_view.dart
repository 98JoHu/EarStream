import 'package:flutter/material.dart';
import '../../model/user_account.dart';
import '../../model/measurement.dart';
import '../../model/meditation.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/meditation_tile.dart';
import 'package:provider/provider.dart';

enum Step {
  settings,
  sealCheck,
  meditation,
}

enum DemoMode {
  biosignalAdaptive(steps: [Step.settings, Step.sealCheck, Step.meditation]),
  personalizedOnly(steps: [Step.settings, Step.meditation]);

  final List<Step> steps;

  const DemoMode({required this.steps});
}

abstract class DemoStepView extends StatefulWidget {
  final UserAccount userAccount;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback? onSkip;

  const DemoStepView({
    super.key,
    required this.userAccount,
    required this.onBack,
    required this.onContinue,
    this.onSkip,
  });
}

class DemoView extends StatefulWidget {
  const DemoView({super.key});

  @override
  State<DemoView> createState() => _DemoViewState();
}

class _DemoViewState extends State<DemoView> {
  DemoMode? _selectedMode;
  int _currentStepIndex = 0;
  Meditation? _personalizedMeditation;

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

  void _finish() {
    print("Meditation completed. Returning to demo selection.");
    setState(() {
      _selectedMode = null;
      _currentStepIndex = 0;
    });
  }

  @override
  void dispose() {
    _personalizedMeditation?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: _selectedMode == null
            ? DemoSelection(onSelectMode: _selectMode)
            : _stepContent(),
      ),
    );
  }

  Widget _stepContent() {
    switch (_currentStep) {
      case Step.settings:
        return SettingsView(
          userAccount: context.read<Measurement>().userAccount,
          onBack: _back,
          onContinue: _continue,
          onSkip: _skip,
        );
      case Step.sealCheck:
        return SealCheckView(
          userAccount: context.read<Measurement>().userAccount,
          onBack: _back,
          onContinue: _continue,
          onSkip: _skip,
        );
      case Step.meditation:
        // Depending on the selected mode, start the meditation session with or without biosignal adaptation.
        if (_selectedMode == DemoMode.biosignalAdaptive) {
          return const Text("Biosignal-Adaptive Meditation Session");
        } else {
          final meditation = _personalizedMeditation ??
              Meditation(
                userAccount: context.read<Measurement>().userAccount,
              )
            ..start();
          return MeditationTile(
            meditation: ValueNotifier<Meditation?>(meditation),
            onMeditationComplete: _finish,
          );
        }
    }
  }
}

class DemoSelection extends StatelessWidget {
  final Function(DemoMode) onSelectMode;

  const DemoSelection({super.key, required this.onSelectMode});

  @override
  Widget build(BuildContext context) {
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
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.5,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => onSelectMode(DemoMode.biosignalAdaptive),
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
            onPressed: () => onSelectMode(DemoMode.personalizedOnly),
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
}

class DemoNavBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback? onSkip;
  final bool canContinue;

  const DemoNavBar({
    super.key,
    required this.onBack,
    required this.onContinue,
    this.onSkip,
    this.canContinue = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        OutlinedButton(
          onPressed: onBack,
          child: const Text('Back'),
        ),
        if (onSkip != null)
          OutlinedButton(onPressed: onSkip, child: const Text('Skip')),
        ElevatedButton(
          onPressed: canContinue ? onContinue : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class SettingsView extends DemoStepView {
  const SettingsView({
    super.key,
    required super.userAccount,
    required super.onBack,
    required super.onContinue,
    super.onSkip,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
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
                child: Icon(
                  Icons.spa_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
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
          DemoNavBar(
            onBack: widget.onBack,
            onContinue: widget.onContinue,
            onSkip: null, // No skip option for settings
          ),
        ],
      ),
    );
  }
}

class SealCheckView extends DemoStepView {
  const SealCheckView({
    super.key,
    required super.userAccount,
    required super.onBack,
    required super.onContinue,
    super.onSkip,
  });

  @override
  State<SealCheckView> createState() => _SealCheckViewState();
}

class _SealCheckViewState extends State<SealCheckView> {
  bool _isCheckCompleted = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.verified_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Seal Check',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        const Divider(height: 24),
        Text(
          'Confirm the earable has a good acoustic seal before calibration starts.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.5,
              ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.hearing_outlined,
                color: Theme.of(context).colorScheme.primary, size: 24),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Run the seal check',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Put on the OpenEarable, then tap the button below. A short tone will be played and analysed to confirm a good acoustic seal.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            // TODO: Implement seal check functionality
            onPressed: () {},
            icon: const Icon(Icons.play_arrow),
            label: Text('Run Seal Check'),
          ),
        ),
        const SizedBox(height: 24),
        DemoNavBar(
          onBack: widget.onBack,
          onContinue: widget.onContinue,
          onSkip: widget.onSkip,
          canContinue:
              _isCheckCompleted, // Enable continue only if check is completed
        ),
        // TODO: Add visual feedback for seal check result (success/failure)
      ],
    );
  }
}
