import 'dart:convert';

import 'package:misskey_mfm_parser/misskey_mfm_parser.dart';
import 'package:petitparser/petitparser.dart';
import 'package:test/test.dart';

import '../../support/ast_json.dart';

void main() {
  // Expected ASTs were checked against mfm.js 0.28.0 parse/parseSimple.
  for (final simple in [false, true]) {
    group(simple ? 'simple empty input' : 'full empty input', () {
      final parser = simple ? MfmParser().buildSimple() : MfmParser().build();

      test('empty input succeeds with an empty AST', () {
        final result = parser.parse('');
        expect(result, isA<Success<List<MfmNode>>>());
        expect(result.position, 0);
        expect(serializeMfmAst(result.value), isEmpty);
      });

      for (final input in [
        ' ',
        '   ',
        '\t',
        '\n',
        '\n\n',
        '\r',
        '\r\n',
        ' \t\n ',
        '\u3000',
        '\u00a0',
      ]) {
        test('whitespace is preserved: ${jsonEncode(input)}', () {
          final result = parser.parse(input);
          expect(result, isA<Success<List<MfmNode>>>());
          expect(result.position, input.length);
          expect(serializeMfmAst(result.value), [
            {
              'type': 'text',
              'props': {'text': input},
              'children': <Object?>[],
            },
          ]);
        });
      }

      test('reusing the parser around empty input preserves nonempty ASTs', () {
        const input = 'Hello **bold** :wave: 😀';
        final expected = <MfmNode>[
          if (simple)
            const TextNode('Hello **bold** ')
          else ...[
            const TextNode('Hello '),
            const BoldNode([TextNode('bold')]),
            const TextNode(' '),
          ],
          const EmojiCodeNode('wave'),
          const TextNode(' '),
          const UnicodeEmojiNode('😀'),
        ];

        expect(parser.parse(input).value, expected);
        expect(parser.parse('').value, isEmpty);
        expect(parser.parse(input).value, expected);
        expect(parser.parse('').value, isEmpty);
      });
    });
  }

  test('full empty input succeeds with an explicit nesting limit', () {
    for (final nestLimit in [0, 1, 20, 100]) {
      final result = MfmParser().build(nestLimit: nestLimit).parse('');
      expect(result, isA<Success<List<MfmNode>>>());
      expect(result.position, 0);
      expect(result.value, isEmpty);
    }
  });
}
