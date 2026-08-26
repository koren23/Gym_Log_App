class BodyWeightEntry {
  const BodyWeightEntry({
    required this.date,
    required this.weightKg,
    required this.rowIndex,
  });

  final DateTime date;
  final double weightKg;

  /// 0-based row index in the BodyWeight tab (needed to edit/delete this
  /// entry).
  final int rowIndex;
}
