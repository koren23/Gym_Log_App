import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/sheet_data_providers.dart';
import '../../services/sheets/spreadsheet_id_extractor.dart';
import '../../widgets/app_snack_bar.dart';

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

  /// Connects the sheet (always succeeds if the URL parses), then signs
  /// in if needed and runs the "sheet wins" import pass — both
  /// best-effort, since the sheet itself is an optional backup: a failure
  /// in either still leaves [SpreadsheetIdNotifier.setSpreadsheet] done,
  /// and the user can retry sign-in/import later from Settings.
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

    var authState = ref.read(authStateProvider);
    if (!authState.isSignedIn || !authState.hasSheetsAccess) {
      await ref.read(authStateProvider.notifier).signInInteractively();
      authState = ref.read(authStateProvider);
    }

    String? importError;
    if (authState.isSignedIn && authState.hasSheetsAccess) {
      try {
        await ref.read(snapshotProvider.notifier).importFromSheet();
      } catch (e) {
        importError = e.toString();
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (!authState.isSignedIn) {
      showAppSnackBar(
        context,
        'Sheet connected, but sign-in was skipped — finish signing in from '
        'Settings to sync with it.',
        isError: true,
      );
    } else if (importError != null) {
      showAppSnackBar(
        context,
        'Sheet connected, but the initial sync failed: $importError. It '
        'will retry later.',
        isError: true,
      );
    } else {
      showAppSnackBar(context, 'Sheet connected and synced.');
    }
    Navigator.of(context).pop();
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
