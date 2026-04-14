import 'package:flutter/material.dart';

import '../model/meditation_config.dart';
import '../model/outlook_meeting_blocker.dart';
import '../model/user_account.dart';

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

  late String _gender;
  late String _fitnessLevel;
  late String _meditationStyle;
  late String _environment;
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
    _geminiApiKeyController =
        TextEditingController(text: account.geminiApiKey);
    _elevenLabsApiKeyController =
        TextEditingController(text: account.elevenLabsApiKey);
    _microsoftGraphTokenController =
        TextEditingController(text: account.microsoftGraphAccessToken);

    _gender = account.gender;
    _fitnessLevel = account.fitnessLevel;
    _meditationStyle = account.meditationStyle;
    _environment = account.preferredEnvironment;
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

  String get _subtitle {
    switch (widget.section) {
      case EarStreamAccountSection.personalInfo:
        return 'Profile data used for personalized stress detection.';
      case EarStreamAccountSection.meditationPreferences:
        return 'How EarStream should sound and feel during a session.';
      case EarStreamAccountSection.outlookCalendar:
        return 'Suppress meditation prompts while Outlook meetings are active.';
      case EarStreamAccountSection.apiKeys:
        return 'Store service keys locally so non-programmers can configure EarStream in-app.';
    }
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
    updatedAccount.meditationStyle = _meditationStyle;
    updatedAccount.preferredEnvironment = _environment;
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

      final hasLocalToken = _microsoftGraphTokenController.text.trim().isNotEmpty;
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
                style: const TextStyle(fontWeight: FontWeight.w700),
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
            style: TextStyle(
              color: Colors.grey[700],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600),
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
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
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
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildOptionButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6366F1) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey[700]),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey[700],
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

    return GestureDetector(
      onTap: () => setState(() => _fitnessLevel = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6366F1).withValues(alpha: 0.1)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF6366F1) : Colors.grey[200]!,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF6366F1) : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : Colors.grey[600],
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
                      color:
                          selected ? const Color(0xFF6366F1) : Colors.grey[800],
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Color(0xFF6366F1)),
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
            'Meditation style',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _meditationStyle,
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
                value: 'calm and empathetic',
                child: Text('Calm and empathetic'),
              ),
              DropdownMenuItem(
                value: 'gentle and soothing',
                child: Text('Gentle and soothing'),
              ),
              DropdownMenuItem(
                value: 'warm and compassionate',
                child: Text('Warm and compassionate'),
              ),
              DropdownMenuItem(
                value: 'peaceful and mindful',
                child: Text('Peaceful and mindful'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _meditationStyle = value);
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Preferred environment',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _environment,
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
                child: Text('Peaceful nature'),
              ),
              DropdownMenuItem(
                value: 'calm ocean beach',
                child: Text('Ocean beach'),
              ),
              DropdownMenuItem(
                value: 'quiet mountain',
                child: Text('Mountain'),
              ),
              DropdownMenuItem(
                value: 'serene forest',
                child: Text('Forest'),
              ),
              DropdownMenuItem(
                value: 'gentle garden',
                child: Text('Garden'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _environment = value);
            },
          ),
          const SizedBox(height: 28),
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
          if (_usePremiumVoice) ...[
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
          _buildStatusCard(
            title: 'Premium voice readiness',
            status: _usePremiumVoice ? 'Enabled' : 'Disabled',
            description: _usePremiumVoice
                ? 'Add or update the ElevenLabs API key in the API Keys page if you want premium voice generation to work immediately.'
                : 'EarStream will use the device TTS fallback until premium voice is enabled.',
            color: _usePremiumVoice ? Colors.indigo : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildOutlookCalendarPage() {
    final hasLocalToken = _microsoftGraphTokenController.text.trim().isNotEmpty;
    final hasFallbackToken = MeditationConfig.hasValidMicrosoftGraphToken;
    final statusColor = hasLocalToken || hasFallbackToken
        ? Colors.indigo
        : Colors.orange;

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
              _isCheckingOutlook ? 'Checking Outlook...' : 'Check Outlook Status',
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
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE), Color(0xFFDDD6FE)],
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _subtitle,
                    style: TextStyle(
                      color: Colors.grey[800],
                      height: 1.4,
                    ),
                  ),
                ),
                _buildSectionBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
