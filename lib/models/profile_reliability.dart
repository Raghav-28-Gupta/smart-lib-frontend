enum ActivityDot { ok, miss }

class ProfileReliability {
  const ProfileReliability({
    required this.tier,
    required this.ringFraction,
    required this.note,
    required this.history,
  });

  final String tier;
  final double ringFraction;
  final String note;
  final List<ActivityDot> history;
}
