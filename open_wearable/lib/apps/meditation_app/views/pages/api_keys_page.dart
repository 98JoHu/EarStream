import 'package:flutter/material.dart';
import '../../model/user_account.dart';
import 'drawer_page.dart';
import '../../widgets/status_field.dart';
import '../../widgets/secret_field.dart';
import '../../widgets/custom_dropdown.dart';

class ApiKeysPage extends StatefulWidget implements DrawerPage {
  final UserAccount userAccount;
  const ApiKeysPage({super.key, required this.userAccount});

  @override
  String get label => "API Keys";

  @override
  IconData get icon => Icons.key_outlined;

  @override
  IconData get selectedIcon => Icons.key;

  @override
  State<ApiKeysPage> createState() => _ApiKeysPageState();
}

class _ApiKeysPageState extends State<ApiKeysPage> {
  late final DeepseekManager _deepseekManager;
  late final ElevenLabsManager _elevenLabsManager;
  late final TencentTtsManager _tencentManager;

  @override
  void initState() {
    super.initState();
    _deepseekManager = DeepseekManager(userAccount: widget.userAccount);
    _elevenLabsManager = ElevenLabsManager(userAccount: widget.userAccount);
    _tencentManager = TencentTtsManager(userAccount: widget.userAccount);
    _deepseekManager.addListener(_refreshFromServiceState);
    _elevenLabsManager.addListener(_refreshFromServiceState);
    _tencentManager.addListener(_refreshFromServiceState);
  }

  void _refreshFromServiceState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _deepseekManager.removeListener(_refreshFromServiceState);
    _elevenLabsManager.removeListener(_refreshFromServiceState);
    _tencentManager.removeListener(_refreshFromServiceState);
    _deepseekManager.dispose();
    _elevenLabsManager.dispose();
    _tencentManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elevenLabsVoices = widget.userAccount.availableElevenLabsVoices;
    return Card(
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voice & Service Configuration',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Credentials loaded from the bundled demo configuration or entered here apply to the current app session. Choose which cloud voice service EarStreAM should use.',
                style: TextStyle(color: Colors.grey[700], height: 1.4),
              ),
              const SizedBox(height: 24),
              const Text(
                'TTS Provider',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TtsProviderDropdown(
                key: ValueKey(widget.userAccount.ttsProvider),
                initialSelection: widget.userAccount.ttsProvider,
                onSelected: (value) {
                  if (value == null) return;
                  setState(() => widget.userAccount.ttsProvider = value);
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Default Voice',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Select the male or female voice configured in the app. An explicitly selected ElevenLabs voice overrides this default.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              VoiceGenderDropdown(
                key: ValueKey(widget.userAccount.voiceGender),
                initialSelection:
                    widget.userAccount.voiceGender ?? Gender.female,
                onSelected: (value) {
                  if (value == null) return;
                  setState(() => widget.userAccount.voiceGender = value);
                  widget.userAccount.hasValidTencentKey = false;
                  _tencentManager.markUnverified();
                },
              ),
              if (widget.userAccount.ttsProvider ==
                      TtsProviderOption.elevenLabs &&
                  widget.userAccount.hasValidElevenLabsKey &&
                  elevenLabsVoices != null &&
                  elevenLabsVoices.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'ElevenLabs Voice',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ElevenLabsVoiceDropdown(
                  key: ValueKey(widget.userAccount.elevenLabsVoiceId),
                  voices: elevenLabsVoices,
                  initialSelection: widget.userAccount.elevenLabsVoiceId,
                  onSelected: (value) {
                    setState(() {
                      widget.userAccount.elevenLabsVoiceId = value;
                    });
                  },
                ),
              ],
              const SizedBox(height: 24),
              StatusField(
                connectionManager: _deepseekManager,
                neighbourWidget: SecretField(
                  title: "Deepseek API Key",
                  description:
                      "Provide a Deepseek API key to enable personal stress-adaptive session generation. Keys are stored only on this device.",
                  onChanged: (value) {
                    widget.userAccount.deepseekApiKey = value;
                    widget.userAccount.hasValidDeepseekKey = false;
                    _deepseekManager.markUnverified();
                  },
                  initialValue: widget.userAccount.deepseekApiKey ?? '',
                ),
              ),
              const SizedBox(height: 24),
              StatusField(
                connectionManager: _elevenLabsManager,
                neighbourWidget: SecretField(
                  title: "ElevenLabs API Key",
                  description:
                      "Provide an ElevenLabs API key to enable voice synthesis features. Keys are stored only on this device.",
                  onChanged: (value) {
                    widget.userAccount.elevenLabsApiKey = value;
                    widget.userAccount.hasValidElevenLabsKey = false;
                    _elevenLabsManager.markUnverified();
                  },
                  initialValue: widget.userAccount.elevenLabsApiKey ?? '',
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Tencent processing region',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TencentTtsRegionDropdown(
                key: ValueKey(widget.userAccount.tencentTtsRegion),
                initialSelection: widget.userAccount.tencentTtsRegion,
                onSelected: (value) {
                  if (value == null) return;
                  setState(() {
                    widget.userAccount.tencentTtsRegion = value;
                    widget.userAccount.hasValidTencentKey = false;
                  });
                  _tencentManager.markUnverified();
                },
              ),
              const SizedBox(height: 8),
              Text(
                widget.userAccount.tencentTtsRegion ==
                        TencentTtsRegion.internationalSingapore
                    ? 'Uses Tencent Cloud International with TTS processing in Singapore. Select this for international accounts and EU demos.'
                    : 'Uses Tencent Cloud mainland with TTS processing in Guangzhou. This requires TTS activated on a mainland China account.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SecretField(
                title: 'Tencent SecretId',
                description:
                    'Enter the SecretId from the Tencent Cloud API key pair.',
                onChanged: (value) {
                  widget.userAccount.tencentSecretId = value;
                  widget.userAccount.hasValidTencentKey = false;
                  _tencentManager.markUnverified();
                },
                initialValue: widget.userAccount.tencentSecretId ?? '',
              ),
              const SizedBox(height: 12),
              StatusField(
                connectionManager: _tencentManager,
                neighbourWidget: SecretField(
                  title: 'Tencent SecretKey',
                  description:
                      'Enter the SecretKey paired with the Tencent SecretId.',
                  onChanged: (value) {
                    widget.userAccount.tencentSecretKey = value;
                    widget.userAccount.hasValidTencentKey = false;
                    _tencentManager.markUnverified();
                  },
                  initialValue: widget.userAccount.tencentSecretKey ?? '',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
