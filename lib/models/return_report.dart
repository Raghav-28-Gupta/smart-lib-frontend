/// What a student can say is wrong with a copy when they return it. These are the
/// three categories the server takes for a copy (`damaged`, `missing_pages`,
/// `other`); the seat and room categories are not offered here.
enum ReportCategory {
  damaged('damaged'),
  missingPages('missing_pages'),
  other('other');

  const ReportCategory(this.wireName);

  /// How the server spells it.
  final String wireName;
}

/// A problem the student reports with the copy they are returning. It travels in
/// the same request as the return (`POST /loans/:id/return { report }`), so the
/// two succeed or fail together. Sent only; the server's answer is unchanged.
class ReturnReport {
  const ReturnReport({required this.category, this.note});

  final ReportCategory category;

  /// What the student wrote, already trimmed, or null when they wrote nothing.
  /// The server takes at most 300 characters and requires one for `other`.
  final String? note;

  /// A null note is left out, never sent as `null` or as an empty string.
  Map<String, dynamic> toJson() => {
        'category': category.wireName,
        if (note != null) 'note': note,
      };
}
