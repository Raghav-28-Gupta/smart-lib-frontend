import 'book.dart';

class RecommendationSection {
  const RecommendationSection(
      {required this.title, required this.caption, required this.books});

  final String title;
  final String caption;
  final List<Book> books;
}

class RecommendationsData {
  const RecommendationsData({required this.note, required this.sections});

  final String note;
  final List<RecommendationSection> sections;
}
