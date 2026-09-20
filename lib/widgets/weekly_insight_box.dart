import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analysis_result.dart';
import '../providers/analysis_providers.dart';
import 'suggestion_card.dart';

/// A compact "last few weeks" summary box for the home screen: the top 3
/// improving exercises and top 3 stuck ones (each just a name + trend
/// icon, no detail text — keeps it small). Built from
/// [proactiveFindingsProvider] (on-device rule-based trend/plateau
/// analysis over the last [AnalysisEngine.proactiveScanWindowWeeks]).
/// Falls back to steady (flat) exercises when nothing's improving or
/// stuck, so it only shows the empty-state line when there's genuinely no
/// data yet. Sized entirely by the parent (Home animates its height) —
/// content scrolls internally if it doesn't fit.
///
/// [minimized] collapses this down to just its title (no findings list) —
/// used while a Push/Pull/Legs day is expanded below, so there's room for
/// that without the page needing to scroll.
class WeeklyInsightBox extends ConsumerWidget {
  const WeeklyInsightBox({super.key, this.minimized = false});

  final bool minimized;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final findings = ref.watch(proactiveFindingsProvider);
    final theme = Theme.of(context);

    final improving = findings
        .where((f) => f.weightTrend == TrendDirection.up && !f.isPlateaued)
        .take(3)
        .toList();
    final stuck = findings.where((f) => f.isPlateaued).take(3).toList();
    final steady = findings
        .where((f) => !f.isPlateaued && f.weightTrend != TrendDirection.up)
        .take(3)
        .toList();
    final showSteadyFallback =
        improving.isEmpty && stuck.isEmpty && steady.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: minimized ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Text(
            'Last few weeks',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!minimized) ...[
            const SizedBox(height: 8),
            if (findings.isEmpty)
              Text(
                'Not enough recent history yet — log a few more sessions to see trends here.',
                style: theme.textTheme.bodyMedium,
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (improving.isNotEmpty) ...[
                        _SectionHeader(emoji: '💪', label: 'Improving'),
                        for (final f in improving)
                          _FindingRow(
                            finding: f,
                            icon: Icons.trending_up,
                            iconColor: Colors.green,
                          ),
                        if (stuck.isNotEmpty) const SizedBox(height: 8),
                      ],
                      if (stuck.isNotEmpty) ...[
                        _SectionHeader(emoji: '🎯', label: 'Stuck'),
                        for (final f in stuck)
                          _FindingRow(
                            finding: f,
                            icon: Icons.trending_flat,
                            iconColor: Colors.orange,
                          ),
                      ],
                      if (showSteadyFallback) ...[
                        _SectionHeader(emoji: '📊', label: 'Steady'),
                        for (final f in steady)
                          _FindingRow(
                            finding: f,
                            icon: Icons.horizontal_rule,
                            iconColor: Colors.blueGrey,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.emoji, required this.label});

  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$emoji $label',
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A compact row for one finding — tapping opens the full [SuggestionCard]
/// (with its Do this/Not now actions, if any) in a bottom sheet, so the box
/// itself stays small while still surfacing actionable suggestions.
class _FindingRow extends StatelessWidget {
  const _FindingRow({
    required this.finding,
    required this.icon,
    required this.iconColor,
  });

  final AnalysisFinding finding;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SuggestionCard(finding: finding),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                finding.subjectName,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (finding.kind != SuggestionKind.none)
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.outline,
              ),
          ],
        ),
      ),
    );
  }
}
