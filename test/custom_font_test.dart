import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lm_chat/custom_font.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('font file names cannot escape the fonts directory', () {
    expect(CustomFontService.isValidFileName('custom_1.ttf'), isTrue);
    expect(CustomFontService.isValidFileName('My_Font-2.ttf'), isTrue);

    for (final name in [
      '',
      '.',
      '..',
      '../custom_1.ttf',
      r'..\custom_1.ttf',
      'nested/custom_1.ttf',
      r'nested\custom_1.ttf',
      '/etc/passwd',
      'custom_1.ttf.exe',
      'custom_1',
      'custom_1.otf',
      '..hidden.ttf',
      'a..b.ttf',
    ]) {
      expect(
        CustomFontService.isValidFileName(name),
        isFalse,
        reason: 'accepted unsafe name: $name',
      );
    }
  });

  test('FontLoader registers a runtime TTF font', () async {
    final file = File('assets/fonts/JetBrainsMono.ttf');
    final bytes = await file.readAsBytes();
    final loader = FontLoader('LmTestMono')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();

    double widthOf(String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontFamily: 'LmTestMono', fontSize: 20),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    // JetBrains Mono has an advance width of 0.6em, so four glyphs at 20 px
    // occupy 48 px. A fallback proportional font would give different widths
    // for "WWWW" and "iiii", and the Ahem test font would give 80 px.
    expect(widthOf('WWWW'), equals(widthOf('iiii')));
    expect(widthOf('WWWW'), closeTo(48, 1));
  });
}
