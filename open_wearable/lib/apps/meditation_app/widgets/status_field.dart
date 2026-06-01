import 'package:flutter/material.dart';

enum Status { missing, checking, error, ok }

class StatusField extends StatefulWidget {
  final Widget? neighbourWidget;
  const StatusField({super.key, this.neighbourWidget});

  @override
  State<StatusField> createState() => _StatusFieldState();
}

class _StatusFieldState extends State<StatusField> {
  final Status _status = Status.missing;
  Color get color {
    switch (_status) {
      case Status.missing:
        return Colors.grey;
      case Status.checking:
        return Colors.blue;
      case Status.error:
        return Colors.red;
      case Status.ok:
        return Colors.green;
    }
  }

  String get statusText {
    switch (_status) {
      case Status.missing:
        return "Not set";
      case Status.checking:
        return "Checking...";
      case Status.error:
        return "Error";
      case Status.ok:
        return "OK";
    }
  }

  String get description {
    switch (_status) {
      case Status.missing:
        return "No source selected. Please choose a source to enable stress detection.";
      case Status.checking:
        return "Checking the connection to the source. This may take a few seconds.";
      case Status.error:
        return "Failed to connect to the source. Please check your settings and try again.";
      case Status.ok:
        return "Successfully connected to the source. Stress detection is active.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.neighbourWidget ?? const SizedBox.shrink(),
        if (widget.neighbourWidget != null) const SizedBox(height: 8),
        Container(
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
                    "Current Source",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
