import 'package:flutter/material.dart';

/// Parses the `"<base> [<label>]"` naming convention used for a
/// "different machine" variant of an exercise — e.g. `'Leg press [blue
/// machine]'` -> `(base: 'Leg press', label: 'blue machine')`. An exercise
/// with no label (the common case) returns `(base: name, label: null)`.
({String base, String? label}) splitMachineLabel(String name) {
  final match = RegExp(r'^(.*) \[(.+)\]$').firstMatch(name);
  if (match == null) return (base: name, label: null);
  return (base: match.group(1)!, label: match.group(2));
}

/// Every distinct machine label previously used for [baseName], scanned
/// from [allExerciseNames] (every exercise name known across all years).
List<String> pastMachineLabelsForBaseName(
  String baseName,
  List<String> allExerciseNames,
) {
  final labels = <String>{};
  for (final name in allExerciseNames) {
    final split = splitMachineLabel(name);
    if (split.label != null &&
        split.base.toLowerCase() == baseName.toLowerCase()) {
      labels.add(split.label!);
    }
  }
  return labels.toList()..sort();
}

/// Lets the user pick (or type) a machine-variant label for
/// [baseExerciseName], from a free-text field or a chip per entry in
/// [pastLabels]. Returns the chosen label, or `''` to clear back to the
/// plain base exercise, or `null` if cancelled.
Future<String?> showMachineLabelDialog(
  BuildContext context, {
  required String baseExerciseName,
  required List<String> pastLabels,
  String? initialLabel,
}) {
  final controller = TextEditingController(text: initialLabel ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text('Different machine: $baseExerciseName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Machine label (e.g. "blue machine")',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (pastLabels.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final label in pastLabels)
                      ActionChip(
                        label: Text(label),
                        onPressed: () => setState(() => controller.text = label),
                      ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            if (initialLabel != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(''),
                child: const Text('Clear'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}
