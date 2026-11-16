import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/settings_providers.dart';
import '../services/settings/app_settings_service.dart';

final _dateFormat = DateFormat.yMMMd();

/// True when at least one of the four fields the Stats tab's BMI/
/// maintenance-calorie cards depend on is still unset.
bool profileIsIncomplete(AppSettingsService settings) =>
    settings.heightCm == null ||
    settings.trainingStartDate == null ||
    settings.biologicalSex == null ||
    settings.birthDate == null;

/// Shown once per cold start (gated by
/// `AppSettingsService.hasDismissedProfilePrompt`) whenever
/// [profileIsIncomplete] — lets the user fill in whatever's missing right
/// away instead of discovering blank BMI/calorie cards on the Stats tab
/// later. "Skip for now" dismisses it for good; every field here stays
/// editable any time from Settings → Profile.
Future<void> showProfileInfoPrompt(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _ProfileInfoPromptDialog(),
  );
}

class _ProfileInfoPromptDialog extends ConsumerStatefulWidget {
  const _ProfileInfoPromptDialog();

  @override
  ConsumerState<_ProfileInfoPromptDialog> createState() =>
      _ProfileInfoPromptDialogState();
}

class _ProfileInfoPromptDialogState
    extends ConsumerState<_ProfileInfoPromptDialog> {
  Future<void> _editHeight() async {
    final settings = ref.read(appSettingsServiceProvider);
    final controller = TextEditingController(
      text: settings.heightCm == null
          ? ''
          : settings.heightCm!.toStringAsFixed(0),
    );
    final result = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Height'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(suffixText: 'cm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await settings.setHeightCm(result > 0 ? result : null);
    setState(() {});
  }

  Future<void> _editTrainingStartDate() async {
    final settings = ref.read(appSettingsServiceProvider);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: settings.trainingStartDate ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
      helpText: 'When did you start working out?',
    );
    if (picked == null || !mounted) return;
    await settings.setTrainingStartDate(picked);
    setState(() {});
  }

  Future<void> _editSex() async {
    final settings = ref.read(appSettingsServiceProvider);
    final result = await showDialog<BiologicalSex?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sex'),
        children: [
          for (final sex in BiologicalSex.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(sex),
              child: Text(sex == BiologicalSex.male ? 'Male' : 'Female'),
            ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    await settings.setBiologicalSex(result);
    setState(() {});
  }

  Future<void> _editBirthDate() async {
    final settings = ref.read(appSettingsServiceProvider);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: settings.birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'When were you born?',
    );
    if (picked == null || !mounted) return;
    await settings.setBirthDate(picked);
    setState(() {});
  }

  Future<void> _dismiss() async {
    await ref.read(appSettingsServiceProvider).setHasDismissedProfilePrompt(true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsServiceProvider);
    return AlertDialog(
      title: const Text('A few details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "These power the Stats tab's BMI and maintenance-calorie "
              'cards. Fill in what you know now — you can change or skip '
              'any of it later from Settings.',
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Height'),
              subtitle: Text(
                settings.heightCm == null
                    ? 'Not set'
                    : '${settings.heightCm!.toStringAsFixed(0)} cm',
              ),
              leading: const Icon(Icons.straighten),
              onTap: _editHeight,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Training since'),
              subtitle: Text(
                settings.trainingStartDate == null
                    ? 'Not set'
                    : _dateFormat.format(settings.trainingStartDate!),
              ),
              leading: const Icon(Icons.calendar_today_outlined),
              onTap: _editTrainingStartDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sex'),
              subtitle: Text(
                switch (settings.biologicalSex) {
                  null => 'Not set',
                  BiologicalSex.male => 'Male',
                  BiologicalSex.female => 'Female',
                },
              ),
              leading: const Icon(Icons.wc),
              onTap: _editSex,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Birth date'),
              subtitle: Text(
                settings.birthDate == null
                    ? 'Not set'
                    : _dateFormat.format(settings.birthDate!),
              ),
              leading: const Icon(Icons.cake_outlined),
              onTap: _editBirthDate,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _dismiss, child: const Text('Skip for now')),
        FilledButton(onPressed: _dismiss, child: const Text('Done')),
      ],
    );
  }
}
