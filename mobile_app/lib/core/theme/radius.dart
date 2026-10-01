import 'package:flutter/material.dart';

/// Centralized shape tokens per Design.md.
/// Restrained, operational radii avoiding excessive rounding.
abstract class AppRadius {
  /// 6px
  static const double small = 6.0;

  /// 10px
  static const double medium = 10.0;

  /// 16px
  static const double large = 16.0;

  static const Radius rSmall = Radius.circular(small);
  static const Radius rMedium = Radius.circular(medium);
  static const Radius rLarge = Radius.circular(large);

  static const BorderRadius borderSmall = BorderRadius.all(rSmall);
  static const BorderRadius borderMedium = BorderRadius.all(rMedium);
  static const BorderRadius borderLarge = BorderRadius.all(rLarge);
}
