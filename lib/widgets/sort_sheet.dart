import 'package:flutter/material.dart';

import '../models/sort_option.dart';

/// Bottom sheet for choosing the library sort field and direction.
///
/// Tapping the field that is already selected flips the direction, which is the
/// gesture people expect from a sorted list header.
class SortSheet extends StatelessWidget {
  const SortSheet({required this.current, required this.onChanged, super.key});

  final SortOption current;
  final ValueChanged<SortOption> onChanged;

  static Future<void> show(
    BuildContext context, {
    required SortOption current,
    required ValueChanged<SortOption> onChanged,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SortSheet(current: current, onChanged: onChanged),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Sort by', style: theme.textTheme.titleMedium),
          ),
          for (final field in SortField.values)
            ListTile(
              title: Text(field.label),
              selected: field == current.field,
              leading: Icon(
                field == current.field
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: field == current.field
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              trailing: field == current.field
                  ? Icon(
                      current.ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () {
                onChanged(
                  field == current.field
                      ? current.copyWith(ascending: !current.ascending)
                      : SortOption(field: field),
                );
                Navigator.of(context).pop();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
