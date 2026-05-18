import 'package:flutter/material.dart';
import 'package:open_wearable/apps/meditation/ui/shared/earstream_style.dart';

import '../../../config/meditation_config.dart';
import '../../../core/meditation/outlook_meeting_blocker.dart';
import '../../../models/user_account.dart';

enum EarStreamAccountSection {
  personalInfo,
  meditationPreferences,
  outlookCalendar,
  apiKeys,
}

class EarStreamAccountSectionPage extends StatefulWidget {
  final UserAccount account;
  final EarStreamAccountSection section;

  const EarStreamAccountSectionPage({
    super.key,
    required this.account,
    required this.section,
  });

  @override
  State<EarStreamAccountSectionPage> createState() =>
      _EarStreamAccountSectionPageState();
}

class _EarStreamAccountSectionPageState
    extends State<EarStreamAccountSectionPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _geminiApiKeyController;
  late final TextEditingController _elevenLabsApiKeyController;
  late final TextEditingController _microsoftGraphTokenController;
  late final TextEditingController _additionalPreferencesController;

  late String _gender;
  late String _fitnessLevel;
  late String _meditationType;
  late String _meditationEnvironment;
  late String _voiceGender;
  late String _speakingSpeed;
  late double _stressThreshold;
  late bool _usePremiumVoice;
  late String _selectedElevenLabsVoiceId;

  bool _isSaving = false;
  bool _showGeminiApiKey = false;
  bool _showElevenLabsApiKey = false;
  bool _showMicrosoftGraphToken = false;
  bool _isCheckingOutlook = false;
  String? _outlookStatusMessage;
  bool _outlookCheckSucceeded = false;

  static const List<Map<String, String>> _elevenLabsStandardVoices = [
    {'id': 'hpp4J3VqNfWAUOO0d1Us', 'name': 'Bella (female, warm)'},
    {'id': 'CwhRBWXzGAHq8TQ4Fs17', 'name': 'Roger (male, resonant)'},
  ];

  @override
  void initState() {
    super.initState();

    final account = widget.account;
    _nameController = TextEditingController(text: account.name);
    _ageController = TextEditingController(
      text: account.age > 0 ? account.age.toString() : '',
    );
    _geminiApiKeyController = TextEditingController(text: account.geminiApiKey);
    _elevenLabsApiKeyController =
        TextEditingController(text: account.elevenLabsApiKey);
    _microsoftGraphTokenController =
        TextEditingController(text: account.microsoftGraphAccessToken);
    _additionalPreferencesController =
        TextEditingController(text: account.additionalPreferences);

    _gender = account.gender;
    _fitnessLevel = account.fitnessLevel;
    _meditationType = account.meditationType;
    _meditationEnvironment = account.meditationEnvironment;
    _voiceGender = account.voiceGender;
    _speakingSpeed = account.speakingSpeed;
    _stressThreshold = account.stressThreshold;
    _usePremiumVoice = account.usePremiumVoice;

    final savedVoiceId = account.elevenLabsVoiceId;
    final hasSavedVoice =
        _elevenLabsStandardVoices.any((voice) => voice['id'] == savedVoiceId);
    _selectedElevenLabsVoiceId =
        hasSavedVoice ? savedVoiceId : _elevenLabsStandardVoices.first['id']!;

    _geminiApiKeyController.addListener(_handleLiveFieldChange);
    _elevenLabsApiKeyController.addListener(_handleLiveFieldChange);
    _microsoftGraphTokenController.addListener(_handleLiveFieldChange);
  }

  @override
  void dispose() {
    _geminiApiKeyController.removeListener(_handleLiveFieldChange);
    _elevenLabsApiKeyController.removeListener(_handleLiveFieldChange);
    _microsoftGraphTokenController.removeListener(_handleLiveFieldChange);
    _nameController.dispose();
    _ageController.dispose();
    _geminiApiKeyController.dispose();
    _elevenLabsApiKeyController.dispose();
    _microsoftGraphTokenController.dispose();
    _additionalPreferencesController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.section) {
      case EarStreamAccountSection.personalInfo:
        return 'Personal Info';
      case EarStreamAccountSection.meditationPreferences:
        return 'Meditation Preferences';
      case EarStreamAccountSection.outlookCalendar:
        return 'Outlook Calendar Integration';
      case EarStreamAccountSection.apiKeys:
        return 'API Keys';
    }
  }

  void _handleLiveFieldChange() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (widget.section == EarStreamAccountSection.personalInfo &&
        !_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final updatedAccount = UserAccount.fromJson(widget.account.toJson());
    updatedAccount.name = _nameController.text.trim();

    final parsedAge = int.tryParse(_ageController.text.trim());
    if (parsedAge != null) {
      updatedAccount.age = parsedAge;
    }

    updatedAccount.gender = _gender;
    updatedAccount.fitnessLevel = _fitnessLevel;
    updatedAccount.meditationType = _meditationType;
    updatedAccount.meditationEnvironment = _meditationEnvironment;
    updatedAccount.voiceGender = _voiceGender;
    updatedAccount.speakingSpeed = _speakingSpeed;
    updatedAccount.additionalPreferences =
        _additionalPreferencesController.text.trim();
    updatedAccount.stressThreshold = _stressThreshold;
    updatedAccount.usePremiumVoice = _usePremiumVoice;
    updatedAccount.elevenLabsVoiceId = _selectedElevenLabsVoiceId;
    updatedAccount.geminiApiKey = _geminiApiKeyController.text.trim();
    updatedAccount.elevenLabsApiKey = _elevenLabsApiKeyController.text.trim();
    updatedAccount.microsoftGraphAccessToken =
        _microsoftGraphTokenController.text.trim();

    await updatedAccount.save();

    if (!mounted) {
      return;
    }

    Navigator.pop(context, updatedAccount);
  }

  Future<void> _checkOutlookStatus() async {
    setState(() {
      _isCheckingOutlook = true;
      _outlookStatusMessage = null;
    });

    final blocker = OutlookMeetingBlocker(
      accessToken: _microsoftGraphTokenController.text.trim(),
    );

    try {
      final status = await blocker.refreshNow();
      if (!mounted) {
        return;
      }

      final hasLocalToken =
          _microsoftGraphTokenController.text.trim().isNotEmpty;
      final usingEnvFallback =
          !hasLocalToken && MeditationConfig.hasValidMicrosoftGraphToken;

      setState(() {
        _outlookCheckSucceeded = true;
        if (!blocker.hasValidConfiguration) {
          _outlookStatusMessage =
              'No valid Outlook token is configured yet. Save a token here or rely on the bundled .env fallback.';
        } else if (status.isInMeeting) {
          final endsAt = status.endsAt?.toLocal().toString() ?? 'soon';
          _outlookStatusMessage =
              'Meeting suppression is active right now. Current event: ${status.subject ?? "Busy"} until $endsAt.';
        } else {
          _outlookStatusMessage = usingEnvFallback
              ? 'Outlook connection succeeded using the bundled .env fallback token. No meeting is active right now.'
              : 'Outlook connection succeeded. No meeting is active right now.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _outlookCheckSucceeded = false;
        _outlookStatusMessage = 'Outlook check failed: $error';
      });
    } finally {
      blocker.dispose();
      if (mounted) {
        setState(() {
          _isCheckingOutlook = false;
        });
      }
    }
  }

  bool _looksLikeGeminiKey(String value) => value.trim().startsWith('AIza');

  bool _hasPremiumVoiceKey(String value) => value.trim().length > 20;

  Widget _buildStatusCard({
    required String title,
    required String status,
    required String description,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecretField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required bool isVisible,
    required VoidCallback onToggleVisibility,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: !isVisible,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            hintText: hintText,
            suffixIcon: IconButton(
              tooltip: isVisible ? 'Hide value' : 'Show value',
              onPressed: onToggleVisibility,
              icon: Icon(
                isVisible ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWhiteCard({required Widget child}) {
    return EarStreamStyle.surfaceCard(
      context,
      padding: const EdgeInsets.all(24),
      child: child,
    );
  }

  Widget _buildOptionButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFitnessOption({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
  }) {
    final selected = _fitnessLevel == value;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => setState(() => _fitnessLevel = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.45)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.2),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalInfoPage() {
    return _buildWhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell EarStream about the user',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'These values feed the personalized baseline and stress-threshold logic before a meditation session starts.',
            style: TextStyle(color: Colors.grey[700], height: 1.4),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'Enter the participant name',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a name before starting a meditation.';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Age',
              hintText: 'Enter the age in years',
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (value) {
              final age = int.tryParse(value?.trim() ?? '');
              if (age == null || age < 13 || age > 120) {
                return 'Please enter a valid age between 13 and 120.';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Gender',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildOptionButton(
                  label: 'Male',
                  icon: Icons.man,
                  selected: _gender == 'male',
                  onTap: () => setState(() => _gender = 'male'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildOptionButton(
                  label: 'Female',
                  icon: Icons.woman,
                  selected: _gender == 'female',
                  onTap: () => setState(() => _gender = 'female'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildOptionButton(
                  label: 'Other',
                  icon: Icons.person,
                  selected: _gender == 'other',
                  onTap: () => setState(() => _gender = 'other'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          const Text(
            'Fitness level',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _buildFitnessOption(
            title: 'Sedentary',
            subtitle: 'Little to no exercise',
            value: 'sedentary',
            icon: Icons.weekend,
          ),
          _buildFitnessOption(
            title: 'Moderate',
            subtitle: 'Exercise 1-3 times per week',
            value: 'moderate',
            icon: Icons.directions_walk,
          ),
          _buildFitnessOption(
            title: 'Active',
            subtitle: 'Exercise 4-5 times per week',
            value: 'active',
            icon: Icons.directions_run,
          ),
          _buildFitnessOption(
            title: 'Athlete',
            subtitle: 'Daily intense training',
            value: 'athlete',
            icon: Icons.fitness_center,
          ),
        ],
      ),
    );
  }

  Widget _buildMeditationPreferencesPage() {
    return _buildWhiteCard(
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
          DropdownButtonFormField<String>(
            value: _voiceGender,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 'female',
                child: Text('👩 Female'),
              ),
              DropdownMenuItem(
                value: 'male',
                child: Text('👨 Male'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _voiceGender = value);
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Speaking Speed',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _speakingSpeed,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 'very_slow',
                child: Text('🐌 Very Slow'),
              ),
              DropdownMenuItem(
                value: 'slow',
                child: Text('🐢 Slow (Recommended)'),
              ),
              DropdownMenuItem(
                value: 'medium',
                child: Text('🚶 Medium'),
              ),
              DropdownMenuItem(
                value: 'fast',
                child: Text('🏃 Fast'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _speakingSpeed = value);
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Meditation Type',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _meditationType,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 'mindfulness',
                child: Text('🧘 Mindfulness'),
              ),
              DropdownMenuItem(
                value: 'breathing',
                child: Text('🌬️ Breathing'),
              ),
              DropdownMenuItem(
                value: 'body_scan',
                child: Text('💆 Body Scan'),
              ),
              DropdownMenuItem(
                value: 'visualization_journey',
                child: Text('🌅 Visualization Journey'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _meditationType = value);
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Meditation Environment',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _meditationEnvironment,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 'peaceful nature',
                child: Text('🌳 Peaceful nature'),
              ),
              DropdownMenuItem(
                value: 'calm ocean beach',
                child: Text('🌊 Ocean beach'),
              ),
              DropdownMenuItem(
                value: 'quiet mountain',
                child: Text('⛰️ Mountain'),
              ),
              DropdownMenuItem(
                value: 'serene forest',
                child: Text('🌲 Forest'),
              ),
              DropdownMenuItem(
                value: 'gentle garden',
                child: Text('🌸 Garden'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _meditationEnvironment = value);
            },
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
              hintText: 'e.g., "Focus on gratitude" or "Include affirmations"',
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
          DropdownButtonFormField<double>(
            value: _stressThreshold,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 0.05,
                child: Text('📊 5% - Very Sensitive'),
              ),
              DropdownMenuItem(
                value: 0.10,
                child: Text('📊 10% - Recommended'),
              ),
              DropdownMenuItem(
                value: 0.15,
                child: Text('📊 15% - Moderate'),
              ),
              DropdownMenuItem(
                value: 0.20,
                child: Text('📊 20% - Less Sensitive'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _stressThreshold = value);
            },
          ),
          const SizedBox(height: 28),
          /* Premium voice toggle commented out
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Premium voice',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'If enabled, EarStream will try ElevenLabs first and fall back to device TTS if no valid key is available.',
                      style: TextStyle(
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _usePremiumVoice,
                onChanged: (value) {
                  setState(() => _usePremiumVoice = value);
                },
              ),
            ],
          ),
          */
          ...[
            const SizedBox(height: 20),
            const Text(
              'ElevenLabs voice',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedElevenLabsVoiceId,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              items: _elevenLabsStandardVoices
                  .map(
                    (voice) => DropdownMenuItem<String>(
                      value: voice['id'],
                      child: Text(voice['name']!),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedElevenLabsVoiceId = value);
              },
            ),
          ],
          // _buildStatusCard(
          //   title: 'Premium voice readiness',
          //   status: _usePremiumVoice ? 'Enabled' : 'Disabled',
          //   description: _usePremiumVoice
          //       ? 'Add or update the ElevenLabs API key in the API Keys page if you want premium voice generation to work immediately.'
          //       : 'EarStream will use the device TTS fallback until premium voice is enabled.',
          //   color: _usePremiumVoice ? Colors.indigo : Colors.grey,
          // ),
        ],
      ),
    );
  }

  Widget _buildOutlookCalendarPage() {
    final hasLocalToken = _microsoftGraphTokenController.text.trim().isNotEmpty;
    final hasFallbackToken = MeditationConfig.hasValidMicrosoftGraphToken;
    final statusColor =
        hasLocalToken || hasFallbackToken ? Colors.indigo : Colors.orange;

    return _buildWhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Outlook suppression token',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'EarStream polls Microsoft Graph to avoid firing stress prompts during meetings. Tokens are stored only on this device.',
            style: TextStyle(color: Colors.grey[700], height: 1.4),
          ),
          const SizedBox(height: 24),
          _buildSecretField(
            label: 'Microsoft Graph access token',
            controller: _microsoftGraphTokenController,
            hintText: 'Paste an OAuth access token for Microsoft Graph',
            isVisible: _showMicrosoftGraphToken,
            onToggleVisibility: () {
              setState(() {
                _showMicrosoftGraphToken = !_showMicrosoftGraphToken;
              });
            },
          ),
          _buildStatusCard(
            title: 'Current source',
            status: hasLocalToken
                ? 'In-app token'
                : hasFallbackToken
                    ? '.env fallback'
                    : 'Missing',
            description: hasLocalToken
                ? 'EarStream will use the token saved in this page.'
                : hasFallbackToken
                    ? 'No local token is saved, so EarStream will fall back to the bundled .env configuration.'
                    : 'Meeting suppression is disabled until a valid token is provided.',
            color: statusColor,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _isCheckingOutlook ? null : _checkOutlookStatus,
            icon: _isCheckingOutlook
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(
              _isCheckingOutlook
                  ? 'Checking Outlook...'
                  : 'Check Outlook Status',
            ),
          ),
          if (_outlookStatusMessage != null)
            _buildStatusCard(
              title: 'Outlook check',
              status: _outlookCheckSucceeded ? 'Updated' : 'Failed',
              description: _outlookStatusMessage!,
              color:
                  _outlookCheckSucceeded ? Colors.green : Colors.red.shade700,
            ),
        ],
      ),
    );
  }

  Widget _buildApiKeysPage() {
    final geminiValue = _geminiApiKeyController.text.trim();
    final elevenLabsValue = _elevenLabsApiKeyController.text.trim();

    final geminiStatus = geminiValue.isNotEmpty
        ? (_looksLikeGeminiKey(geminiValue) ? 'In-app key' : 'Check value')
        : MeditationConfig.hasValidGeminiKey
            ? '.env fallback'
            : 'Missing';

    final elevenLabsStatus = elevenLabsValue.isNotEmpty
        ? (_hasPremiumVoiceKey(elevenLabsValue) ? 'In-app key' : 'Check value')
        : MeditationConfig.hasValidTtsKey
            ? '.env fallback'
            : 'Missing';

    return _buildWhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service credentials',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Keys saved here take effect at runtime for EarStream. The bundled .env file remains a fallback source, but it cannot be edited safely from the UI at runtime.',
            style: TextStyle(color: Colors.grey[700], height: 1.4),
          ),
          const SizedBox(height: 24),
          _buildSecretField(
            label: 'Gemini API key',
            controller: _geminiApiKeyController,
            hintText: 'Paste a Gemini API key',
            isVisible: _showGeminiApiKey,
            onToggleVisibility: () {
              setState(() {
                _showGeminiApiKey = !_showGeminiApiKey;
              });
            },
          ),
          _buildStatusCard(
            title: 'Gemini',
            status: geminiStatus,
            description: geminiValue.isNotEmpty
                ? 'This value will override the bundled .env key for EarStream content generation.'
                : 'Leave this empty if you want EarStream to keep using the bundled .env key instead.',
            color: geminiStatus == 'Missing'
                ? Colors.orange
                : geminiStatus == 'Check value'
                    ? Colors.red.shade700
                    : Colors.indigo,
          ),
          const SizedBox(height: 20),
          _buildSecretField(
            label: 'ElevenLabs API key',
            controller: _elevenLabsApiKeyController,
            hintText: 'Paste an ElevenLabs API key',
            isVisible: _showElevenLabsApiKey,
            onToggleVisibility: () {
              setState(() {
                _showElevenLabsApiKey = !_showElevenLabsApiKey;
              });
            },
          ),
          _buildStatusCard(
            title: 'ElevenLabs',
            status: elevenLabsStatus,
            description: elevenLabsValue.isNotEmpty
                ? 'This value will override the bundled .env key for premium voice generation.'
                : 'Leave this empty if you want EarStream to keep using the bundled .env key instead.',
            color: elevenLabsStatus == 'Missing'
                ? Colors.orange
                : elevenLabsStatus == 'Check value'
                    ? Colors.red.shade700
                    : Colors.indigo,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBody() {
    switch (widget.section) {
      case EarStreamAccountSection.personalInfo:
        return _buildPersonalInfoPage();
      case EarStreamAccountSection.meditationPreferences:
        return _buildMeditationPreferencesPage();
      case EarStreamAccountSection.outlookCalendar:
        return _buildOutlookCalendarPage();
      case EarStreamAccountSection.apiKeys:
        return _buildApiKeysPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EarStreamStyle.appBar(
        context,
        title: _title,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EarStreamStyle.pagePadding(context),
            children: [
              _buildSectionBody(),
            ],
          ),
        ),
      ),
    );
  }
}
