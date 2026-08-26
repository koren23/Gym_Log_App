import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_providers.dart';
import '../../services/sheets/spreadsheet_id_extractor.dart';

class SheetUrlEntryScreen extends ConsumerStatefulWidget {
  const SheetUrlEntryScreen({super.key});

  @override
  ConsumerState<SheetUrlEntryScreen> createState() =>
      _SheetUrlEntryScreenState();
}

class _SheetUrlEntryScreenState extends ConsumerState<SheetUrlEntryScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final id = extractSpreadsheetId(_controller.text);
    if (id == null) {
      setState(() => _error = "That doesn't look like a Google Sheets URL.");
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    await ref
        .read(spreadsheetIdProvider.notifier)
        .setSpreadsheet(id: id, url: _controller.text.trim());
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect your sheet')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Paste the URL of your workout-tracking Google Sheet. '
              'The app will read and write to this one spreadsheet.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Google Sheets URL',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _continue,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
