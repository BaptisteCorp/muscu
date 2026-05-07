class BodyweightEntry {
  /// 'YYYY-MM-DD'
  final String date;
  final double weightKg;
  final String? note;
  final DateTime updatedAt;

  const BodyweightEntry({
    required this.date,
    required this.weightKg,
    required this.updatedAt,
    this.note,
  });

  BodyweightEntry copyWith({
    double? weightKg,
    String? note,
    bool clearNote = false,
    DateTime? updatedAt,
  }) {
    return BodyweightEntry(
      date: date,
      weightKg: weightKg ?? this.weightKg,
      note: clearNote ? null : (note ?? this.note),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 'YYYY-MM-DD' formatter for a [DateTime].
  static String formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Inverse of [formatDate].
  static DateTime parseDate(String s) {
    final parts = s.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]),
        int.parse(parts[2]));
  }
}
