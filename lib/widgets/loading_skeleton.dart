import 'package:flutter/material.dart';

/// A pulsing placeholder box for skeleton loading states. Hand-rolled with
/// a looping opacity tween instead of pulling in a shimmer package, since
/// this one widget covers every skeleton layout in the app.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(
            base,
            base.withValues(alpha: 0.35),
            _controller.value,
          ),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

/// Skeleton shown while [HomeTab] is waiting on its first Sheets fetch —
/// mirrors the shape of the real insight box + "this week" list so the
/// loading state doesn't jump/reflow once data arrives.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShimmerBox(height: 140, borderRadius: 16),
          const SizedBox(height: 16),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ShimmerBox(height: 64, borderRadius: 12),
            ),
        ],
      ),
    );
  }
}

/// Skeleton for Graphs/History while the initial snapshot is still loading
/// (as opposed to having loaded and genuinely being empty).
class ChartScreenSkeleton extends StatelessWidget {
  const ChartScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShimmerBox(height: 48, borderRadius: 12),
          const SizedBox(height: 16),
          const ShimmerBox(height: 260, borderRadius: 16),
        ],
      ),
    );
  }
}
