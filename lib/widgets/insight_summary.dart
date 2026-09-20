import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import 'suggestion_card.dart';

/// Short, skimmable rendering of a set of [AnalysisFinding]s: what's
/// trending up and what's stuck. A finding with an actionable
/// [AnalysisFinding.kind] renders as a [SuggestionCard] (with Do this/Not
/// now buttons); a plain informational finding stays a single line — shared
/// between the "just logged" summary and the "last time" lookup.
class InsightSummaryList extends StatelessWidget {
  const InsightSummaryList({
    super.key,
    required this.findings,
    this.emptyText =
        'Nothing notable yet — keep logging to build your history.',
  });

  final List<AnalysisFinding> findings;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final improving = findings
        .where((f) => f.weightTrend == TrendDirection.up && !f.isPlateaued)
        .toList();
    final stuck = findings.where((f) => f.isPlateaued).toList();

    if (improving.isEmpty && stuck.isEmpty) {
      return Text(emptyText, style: theme.textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (improving.isNotEmpty) ...[
          const _SummaryHeader(emoji: '📈', label: 'Trending up'),
          for (final f in improving)
            _FindingLine(
              finding: f,
              icon: Icons.trending_up,
              iconColor: Colors.green,
            ),
          if (stuck.isNotEmpty) const SizedBox(height: 12),
        ],
        if (stuck.isNotEmpty) ...[
          const _SummaryHeader(emoji: '🎯', label: 'Stuck'),
          for (final f in stuck)
            _FindingLine(
              finding: f,
              icon: Icons.trending_flat,
              iconColor: Colors.orange,
            ),
        ],
      ],
    );
  }
}

class _FindingLine extends StatelessWidget {
  const _FindingLine({
    required this.finding,
    required this.icon,
    required this.iconColor,
  });

  final AnalysisFinding finding;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    if (finding.kind != SuggestionKind.none) {
      return SuggestionCard(finding: finding);
    }
    return _SummaryRow(
      icon: icon,
      iconColor: iconColor,
      text: finding.suggestion == null
          ? finding.subjectName
          : '${finding.subjectName} — ${finding.suggestion}',
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.emoji, required this.label});

  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$emoji $label',
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
