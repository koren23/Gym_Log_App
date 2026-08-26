import 'package:flutter/material.dart';

/// Half-star rating input, 0.0 to 5.0 in 0.5 steps — tap or drag directly
/// across the stars themselves to set the value.
class StarRatingInput extends StatefulWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  final _starsKey = GlobalKey();

  void _handleGesture(Offset globalPosition) {
    final box = _starsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final raw = (local.dx / box.size.width) * 5;
    final rounded = ((raw * 2).round() / 2).clamp(0.0, 5.0);
    widget.onChanged(rounded);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: GestureDetector(
            onTapDown: (d) => _handleGesture(d.globalPosition),
            onHorizontalDragUpdate: (d) => _handleGesture(d.globalPosition),
            child: Row(
              key: _starsKey,
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                final starValue = i + 1;
                IconData icon;
                if (value >= starValue) {
                  icon = Icons.star;
                } else if (value >= starValue - 0.5) {
                  icon = Icons.star_half;
                } else {
                  icon = Icons.star_border;
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(icon, size: 36, color: Colors.amber),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${value.toStringAsFixed(1)} / 5.0',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}
