// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'book.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Book _$BookFromJson(Map<String, dynamic> json) => Book(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String,
      genre: json['genre'] as String? ?? '',
      description: json['description'] as String? ?? '',
      totalCopies: (json['totalCopies'] as num).toInt(),
      availableCopies: (json['availableCopies'] as num).toInt(),
      waitlistCount: (json['waitlistCount'] as num).toInt(),
    );
