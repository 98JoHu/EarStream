import 'package:flutter/material.dart';

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
