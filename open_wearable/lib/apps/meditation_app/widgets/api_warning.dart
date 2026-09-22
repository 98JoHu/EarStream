import 'package:flutter/material.dart';

class APIWarning extends StatelessWidget {
  final String serviceName;

  /// Whether the unavailable service runs on the phone. A local voice has no
  /// credentials to add, so pointing at the API Keys page would be wrong.
  final bool isLocalModel;

  const APIWarning({
    super.key,
    required this.serviceName,
    this.isLocalModel = false,
  });

  String get _title =>
      isLocalModel ? 'Voice Model Not Installed' : 'API Not Configured';

  String get _message => isLocalModel
      ? 'The on-device $serviceName voice model was not found in this build. '
          'It has no credentials; the model itself has to be bundled, as '
          'described in the in-app README. EarStreAM will use its device '
          'fallback voice until then.'
      : 'No valid $serviceName credentials were found. Add them on the API '
          'Keys page and check the connection. EarStreAM will use its local '
          'fallback until then.';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    _message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
