import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/changelog.dart';

/// Shows the currently installed app version plus a per-version list of
/// what changed, newest first — see [kChangelog].
class ChangelogScreen extends StatefulWidget {
  const ChangelogScreen({super.key});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _info == null
                ? 'Loading version…'
                : 'Currently on version ${_info!.version} (build ${_info!.buildNumber})',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 20),
          for (final entry in kChangelog) _ChangelogSection(entry: entry),
        ],
      ),
    );
  }
}

class _ChangelogSection extends StatelessWidget {
  const _ChangelogSection({required this.entry});

  final ChangelogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'v${entry.version}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(entry.date, style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          for (final change in entry.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('•  $change', style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}
