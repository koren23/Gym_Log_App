import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/semantic_colors.dart';

void main() {
  test('fixed hues stay the same across light and dark backgrounds', () {
    final light = semanticTrendColors(const Color(0xFFFFFFFF));
    final dark = semanticTrendColors(const Color(0xFF10151C));

    double hueOf(Color c) => HSLColor.fromColor(c).hue;

    expect(hueOf(light.improving), closeTo(130, 0.5));
    expect(hueOf(dark.improving), closeTo(130, 0.5));
    expect(hueOf(light.stuck), closeTo(4, 0.5));
    expect(hueOf(dark.stuck), closeTo(4, 0.5));
    expect(hueOf(light.steady), closeTo(40, 0.5));
    expect(hueOf(dark.steady), closeTo(40, 0.5));
  });

  test(
    'lightness/saturation differ between a light and a dark background '
    '(so the stripe reads correctly against either)',
    () {
      final light = semanticTrendColors(const Color(0xFFFFFFFF));
      final dark = semanticTrendColors(const Color(0xFF10151C));

      final lightHsl = HSLColor.fromColor(light.improving);
      final darkHsl = HSLColor.fromColor(dark.improving);

      expect(lightHsl.lightness, isNot(closeTo(darkHsl.lightness, 0.01)));
      expect(lightHsl.saturation, isNot(closeTo(darkHsl.saturation, 0.01)));
    },
  );

  test('the three trend colors are visibly distinct from each other', () {
    final colors = semanticTrendColors(const Color(0xFFFFFFFF));
    expect(colors.improving, isNot(colors.stuck));
    expect(colors.improving, isNot(colors.steady));
    expect(colors.stuck, isNot(colors.steady));
  });
}
