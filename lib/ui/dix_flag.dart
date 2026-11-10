import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

/// The same clipped flag treatment in server lists and dashboard cards.
class DixFlag extends StatelessWidget {
  final String countryCode;
  final double width;
  final double height;
  final double radius;

  const DixFlag({
    super.key,
    required this.countryCode,
    this.width = 26,
    this.height = 19,
    this.radius = 4,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: CountryFlag.fromCountryCode(
      countryCode,
      theme: ImageTheme(width: width, height: height),
    ),
  );
}
