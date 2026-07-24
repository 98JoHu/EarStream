import 'package:flutter/material.dart';
import 'package:open_earable_flutter/open_earable_flutter.dart';
import 'drawer_page.dart';
import '../../widgets/seal_check.dart';

class SealCheckPage extends StatelessWidget implements DrawerPage {
  final Wearable? wearable;

  const SealCheckPage({super.key, this.wearable});

  @override
  String get label => "OpenEarable 2.0 Seal Check";

  @override
  IconData get icon => Icons.verified_outlined;

  @override
  IconData get selectedIcon => Icons.verified;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SealCheck(wearable: wearable, showResponsePoints: true),
      ),
    );
  }
}
