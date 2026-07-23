import 'package:flutter/material.dart';
import '../model/user_account.dart'
    show Gender, SpeakingSpeed, MeditationType, MeditationEnvironment;
import '../widgets/emojis.dart';

final voiceGenderOptions = [
  DropdownMenuEntry(
    value: Gender.female,
    label: '${AppEmojis.female} Female',
  ),
  DropdownMenuEntry(
    value: Gender.male,
    label: '${AppEmojis.male} Male',
  ),
];
final speakingSpeedOptions = SpeakingSpeed.values.map((option) {
  return DropdownMenuEntry(
    value: option,
    label:
        '${option.emoji} ${option.label} ${option.isRecommended ? "(Recommended)" : ""}',
  );
}).toList();
final meditationTypeOptions = MeditationType.values.map((type) {
  return DropdownMenuEntry(
    value: type,
    label: '${type.emoji} ${type.label}',
  );
}).toList();
final meditationEnvironmentOptions = MeditationEnvironment.values.map((env) {
  return DropdownMenuEntry(
    value: env,
    label: '${env.emoji} ${env.label}',
  );
}).toList();
final stressThresholdOptions = [
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

class FormDropdown<T> extends StatelessWidget {
  final T initialSelection;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onSelected;

  const FormDropdown({
    super.key,
    required this.initialSelection,
    required this.entries,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<T>(
      initialSelection: initialSelection,
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: entries,
      onSelected: (T? value) {
        if (value != null) {
          onSelected(value);
        }
      },
    );
  }
}

class VoiceGenderDropdown extends StatelessWidget {
  final Gender initialSelection;
  final ValueChanged<Gender?> onSelected;

  const VoiceGenderDropdown({
    super.key,
    required this.initialSelection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => FormDropdown<Gender>(
        initialSelection: initialSelection,
        entries: voiceGenderOptions,
        onSelected: onSelected,
      );
}

class SpeakingSpeedDropdown extends StatelessWidget {
  final SpeakingSpeed initialSelection;
  final ValueChanged<SpeakingSpeed?> onSelected;

  const SpeakingSpeedDropdown({
    super.key,
    required this.initialSelection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => FormDropdown<SpeakingSpeed>(
        initialSelection: initialSelection,
        entries: speakingSpeedOptions,
        onSelected: onSelected,
      );
}

class MeditationTypeDropdown extends StatelessWidget {
  final MeditationType initialSelection;
  final ValueChanged<MeditationType?> onSelected;

  const MeditationTypeDropdown({
    super.key,
    required this.initialSelection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => FormDropdown<MeditationType>(
        initialSelection: initialSelection,
        entries: meditationTypeOptions,
        onSelected: onSelected,
      );
}

class MeditationEnvironmentDropdown extends StatelessWidget {
  final MeditationEnvironment initialSelection;
  final ValueChanged<MeditationEnvironment?> onSelected;

  const MeditationEnvironmentDropdown({
    super.key,
    required this.initialSelection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => FormDropdown<MeditationEnvironment>(
        initialSelection: initialSelection,
        entries: meditationEnvironmentOptions,
        onSelected: onSelected,
      );
}

class StressThresholdDropdown extends StatelessWidget {
  final double initialSelection;
  final ValueChanged<double?> onSelected;

  const StressThresholdDropdown({
    super.key,
    required this.initialSelection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => FormDropdown<double>(
        initialSelection: initialSelection,
        entries: stressThresholdOptions,
        onSelected: onSelected,
      );
}
