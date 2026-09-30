import 'package:json_annotation/json_annotation.dart';
import 'book.dart';

part 'recommendation.g.dart';

@JsonSerializable(createToJson: false)
class RecommendationSection {
  const RecommendationSection(
      {required this.title, required this.caption, required this.books});

  factory RecommendationSection.fromJson(Map<String, dynamic> json) => _$RecommendationSectionFromJson(json);

  final String title;
  final String caption;

  /// Full book payloads, parsed through Book.fromJson -- so they carry the
  /// same live availability counts as the catalog.
  final List<Book> books;
}

@JsonSerializable(createToJson: false)
class RecommendationsData {
  const RecommendationsData({required this.note, required this.sections});

  factory RecommendationsData.fromJson(Map<String, dynamic> json) => _$RecommendationsDataFromJson(json);

  final String note;
  final List<RecommendationSection> sections;
}
