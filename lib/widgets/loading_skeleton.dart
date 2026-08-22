import 'package:flutter/material.dart';
import '../core/theme/smartlib_tokens.dart';

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key, this.width = double.infinity, required this.height, this.borderRadius = 0});
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<SmartLibTokens>()!;
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(color: tokens.neutral[300], borderRadius: BorderRadius.circular(borderRadius)),
    );
  }
}
