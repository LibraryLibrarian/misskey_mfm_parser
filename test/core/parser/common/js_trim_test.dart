import 'package:misskey_mfm_parser/src/parser/common/js_trim.dart';
import 'package:test/test.dart';

void main() {
  group('jsTrim', () {
    // Node.js v22.13.0のString.prototype.trimでBMP全域を走査した結果。
    const jsWhitespace = [
      0x0009,
      0x000a,
      0x000b,
      0x000c,
      0x000d,
      0x0020,
      0x00a0,
      0x1680,
      0x2000,
      0x2001,
      0x2002,
      0x2003,
      0x2004,
      0x2005,
      0x2006,
      0x2007,
      0x2008,
      0x2009,
      0x200a,
      0x2028,
      0x2029,
      0x202f,
      0x205f,
      0x3000,
      0xfeff,
    ];

    test('BMP全域の除去対象がJavaScriptの実測結果と一致する', () {
      expect([
        for (var unit = 0; unit <= 0xffff; unit++)
          if (jsTrim(String.fromCharCode(unit)).isEmpty) unit,
      ], jsWhitespace);
    });

    test('全空白の混在した前後を除去し、内側の空白を保持する', () {
      final whitespace = String.fromCharCodes(jsWhitespace);
      expect(
        jsTrim('${whitespace}j${whitespace}s$whitespace'),
        'j${whitespace}s',
      );
      expect(jsTrim(whitespace), '');
      expect(jsTrim(''), '');
    });

    test('U+0085・U+180E・U+200B・サロゲートを保持する', () {
      for (final value in [
        '\u0085',
        '\u180e',
        '\u200b',
        '😀',
        '\ud800',
        '\udfff',
      ]) {
        expect(jsTrim('\ufeff $value\u00a0'), value);
        expect(jsTrim(value), value);
      }
    });
  });
}
