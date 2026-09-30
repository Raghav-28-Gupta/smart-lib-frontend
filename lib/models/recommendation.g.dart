// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recommendation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecommendationSection _$RecommendationSectionFromJson(
        Map<String, dynamic> json) =>
    RecommendationSection(
      title: json['title'] as String,
      caption: json['caption'] as String,
      books: (json['books'] as List<dynamic>)
          .map((e) => Book.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

RecommendationsData _$RecommendationsDataFromJson(Map<String, dynamic> json) =>
    RecommendationsData(
      note: json['note'] as String,
      sections: (json['sections'] as List<dynamic>)
          .map((e) => RecommendationSection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
