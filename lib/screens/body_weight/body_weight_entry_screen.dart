import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/body_weight_entry.dart';
import '../../providers/sheet_data_providers.dart';
import '../../services/analysis/xp_engine.dart';
import '../../widgets/app_snack_bar.dart';

class BodyWeightEntryScreen extends ConsumerStatefulWidget {
  const BodyWeightEntryScreen({super.key});

  @override
  ConsumerState<BodyWeightEntryScreen> createState() =>
      _BodyWeightEntryScreenState();
}

class _BodyWeightEntryScreenState extends ConsumerState<BodyWeightEntryScreen> {
  DateTime _date = DateTime.now();
  final _weightController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightController.text);
    if (weight == null || weight <= 0) return;

    setState(() => _saving = true);
    final priorEntries = ref.read(bodyWeightEntriesProvider);
    final outcome = await ref
        .read(snapshotProvider.notifier)
        .addBodyWeight(date: _date, weightKg: weight);
    if (!mounted) return;
    setState(() => _saving = false);

    HapticFeedback.lightImpact();

    var message = outcome == SaveOutcome.synced
        ? 'Saved.'
        : 'Saved locally — will sync when back online.';
    // The first entry ever logged is a baseline, not a PR — bodyWeightPrXp
    // already encodes that, so an empty prior history never celebrates.
    if (priorEntries.isNotEmpty) {
      final newEntry = BodyWeightEntry(
        date: _date,
        weightKg: weight,
        rowIndex: -1,
      );
      final prXp =
          bodyWeightPrXp([...priorEntries, newEntry]) -
          bodyWeightPrXp(priorEntries);
      if (prXp > 0) {
        final min = priorEntries
            .map((e) => e.weightKg)
            .reduce((a, b) => a < b ? a : b);
        message = weight < min
            ? 'New all-time low! +$prXp XP'
            : 'New all-time high! +$prXp XP';
      }
    }

    showAppSnackBar(context, message);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log body weight')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: const Text('Date'),
              subtitle: Text(
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Weight (kg)'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
