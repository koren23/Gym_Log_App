import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sheet_data_providers.dart';

class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(snapshotProvider).value?.pendingCount ?? 0;
    if (pendingCount == 0) return const SizedBox.shrink();

    return ActionChip(
      avatar: const Icon(Icons.cloud_off, size: 18),
      label: Text('$pendingCount not synced'),
      onPressed: () async {
        await ref.read(snapshotProvider.notifier).retryPendingSyncs();
      },
    );
  }
}
