import 'dart:convert';

import 'package:misskey_mfm_parser/src/parser/inline/generated/unicode_emoji_regex.dart';
import 'package:test/test.dart';

import '../../tool/update_unicode_emoji_regex.dart';

void main() {
  group('Unicode emoji regex source integrity', () {
    final sourceBytes = utf8.encode(
      'const emojiRegex = /$unicodeEmojiRegexPattern/g;',
    );

    test('extracts the pattern from the regex.mjs source', () {
      expect(
        extractPattern(utf8.decode(sourceBytes)),
        unicodeEmojiRegexPattern,
      );
      expect(
        () => extractPattern('export {};'),
        throwsA(isA<FormatException>()),
      );
    });

    test('keeps the pinned source size and rejects other bytes', () async {
      expect(sourceBytes.length, lessThan(expectedSourceBytes));
      await expectLater(
        validateSourceBytes(sourceBytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a same-length one-byte modification', () async {
      final modified = List<int>.filled(expectedSourceBytes, 0x20);
      modified[0] ^= 1;

      await expectLater(
        validateSourceBytes(modified),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Git blob SHA-1'),
          ),
        ),
      );
    });
  });
}
