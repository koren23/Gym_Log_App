import 'package:flutter/material.dart';

import '../models/analysis_result.dart';

class InsightBanner extends StatelessWidget {
  const InsightBanner({super.key, required this.finding, this.onDismiss});

  final AnalysisFinding finding;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final needsAttention = finding.isPlateaued;
    // A friendly "coach tip" framing for every insight — never an alarm.
    final colors = needsAttention
        ? const [Color(0xFFFFB84D), Color(0xFFFF8A5B)] // warm amber -> coral
        : const [Color(0xFF6DD5A8), Color(0xFF3FB68A)]; // fresh green

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💡', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    finding.message,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                  if (finding.suggestion != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      finding.suggestion!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.white),
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }
}
