import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/body_weight_entry.dart';
import '../../providers/sheet_data_providers.dart';

class BodyWeightHistoryScreen extends ConsumerWidget {
  const BodyWeightHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = [...ref.watch(bodyWeightEntriesProvider)]
      ..sort((a, b) => b.date.compareTo(a.date));
    final dateFormat = DateFormat('EEE, MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Body weight history')),
      body: entries.isEmpty
          ? const Center(child: Text('No body weight entries yet.'))
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return ListTile(
                  title: Text('${entry.weightKg.toStringAsFixed(1)} kg'),
                  subtitle: Text(dateFormat.format(entry.date)),
                  onTap: () => _editEntry(context, ref, entry),
                );
              },
            ),
    );
  }

  Future<void> _editEntry(
    BuildContext context,
    WidgetRef ref,
    BodyWeightEntry entry,
  ) async {
    final controller = TextEditingController(text: entry.weightKg.toString());
    var date = entry.date;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit body weight'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(DateFormat('MMM d, yyyy').format(date)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
              ),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('delete'),
              child: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    final notifier = ref.read(snapshotProvider.notifier);
    bool ok;
    if (action == 'delete') {
      ok = await notifier.deleteBodyWeightEntry(entry);
    } else {
      final weight = double.tryParse(controller.text);
      if (weight == null) return;
      ok = await notifier.updateBodyWeightEntry(
        entry,
        date: date,
        weightKg: weight,
      );
    }

    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save — check your connection and try again.',
          ),
        ),
      );
    }
  }
}
