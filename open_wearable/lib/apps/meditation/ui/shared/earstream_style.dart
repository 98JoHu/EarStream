import 'package:flutter/material.dart';
import 'package:open_wearable/widgets/sensors/sensor_page_spacing.dart';

class EarStreamStyle {
  const EarStreamStyle._();

  static const String appName = 'EarStreAM';

  static EdgeInsets pagePadding(BuildContext context) =>
      SensorPageSpacing.pagePaddingWithBottomInset(context);

  static AppBar appBar(
    BuildContext context, {
    required String title,
    List<Widget>? actions,
  }) {
    return AppBar(
      title: Text(title),
      actions: actions,
    );
  }

  static TextStyle? sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          );

  static TextStyle? pageHeadline(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          );

  static TextStyle? supportingText(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          );

  static TextStyle? labelText(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );

  static Widget surfaceCard(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    EdgeInsetsGeometry? margin,
  }) {
    return Card(
      margin: margin,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }

  static BoxDecoration tintedPanel(
    BuildContext context, {
    Color? tint,
    double alpha = 0.08,
    double radius = 16,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedTint = tint ?? colorScheme.primary;
    return BoxDecoration(
      color: resolvedTint.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: resolvedTint.withValues(alpha: 0.16),
      ),
    );
  }

  static BoxDecoration terminalDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0A1118)
        : const Color(0xFF111A22);

    return BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: colorScheme.outline.withValues(alpha: 0.2),
      ),
    );
  }
}
