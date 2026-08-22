import 'package:flutter/material.dart';
import '../core/theme/smartlib_theme.dart';
import '../core/theme/smartlib_tokens.dart';
import '../models/book.dart';

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, required this.width, required this.height});
  final Book book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SmartLibTokens>()!;
    final colors = coverColors(book.coverPalette, tokens);
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(tokens.radiusMd)),
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.all(8),
      child: Text(book.initial, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: colors.fg)),
    );
  }
}
