import 'package:misskey_mfm_parser/src/ast.dart';
import 'package:misskey_mfm_parser/src/parser/block/code_block.dart';
import 'package:misskey_mfm_parser/src/parser/parser.dart';
import 'package:petitparser/petitparser.dart';
import 'package:test/test.dart';

import '../../../support/ast_json.dart';

void main() {
  group('CodeBlockParser（コードブロック）', () {
    test('言語指定（dart）: ```dart\nvoid main() {}\n```', () {
      final m = MfmParser().build();
      final result = m.parse('```dart\nvoid main() {}\n```');
      expect(result is Success, isTrue);
      final nodes = (result as Success).value as List<MfmNode>;
      expect(
        nodes,
        [
          const CodeBlockNode(
            code: 'void main() {}',
            language: 'dart',
          ),
        ],
      );
    });

    group('mfm-js互換: 終了フェンスと言語指定', () {
      test('本文中の4連バッククォートを終了フェンスとして扱わない', () {
        final m = MfmParser().build();
        final result = m.parse('```js\nfoo\n````\nbar\n```\n');
        expect(result is Success, isTrue);
        final nodes = (result as Success).value as List<MfmNode>;
        expect(
          nodes,
          [
            const CodeBlockNode(
              code: 'foo\n````\nbar',
              language: 'js',
            ),
          ],
        );
      });

      test('言語指定の前後の空白を除去する', () {
        final m = MfmParser().build();
        final result = m.parse('```  js  \nfoo\n```');
        expect(result is Success, isTrue);
        final nodes = (result as Success).value as List<MfmNode>;
        expect(
          nodes,
          [
            const CodeBlockNode(
              code: 'foo',
              language: 'js',
            ),
          ],
        );
      });

      test('空白のみの言語指定をnullとして扱う', () {
        final m = MfmParser().build();
        final result = m.parse('```   \nfoo\n```');
        expect(result is Success, isTrue);
        final nodes = (result as Success).value as List<MfmNode>;
        expect(
          nodes,
          [
            const CodeBlockNode(
              code: 'foo',
            ),
          ],
        );
      });

      test('単純なコードブロックを引き続き解析できる', () {
        final m = MfmParser().build();
        final result = m.parse('```\nfoo\n```');
        expect(result is Success, isTrue);
        final nodes = (result as Success).value as List<MfmNode>;
        expect(
          nodes,
          [
            const CodeBlockNode(
              code: 'foo',
            ),
          ],
        );
      });
    });

    group('mfm-js互換: 言語指定のJS trim', () {
      final parser = MfmParser().build();

      // mfm-js 0.28.0の実出力を確認済み。CR/LFは言語指定の区切りなので除く。
      for (final trimCase in const [
        (unit: 0x0009, trims: true),
        (unit: 0x000b, trims: true),
        (unit: 0x000c, trims: true),
        (unit: 0x0020, trims: true),
        (unit: 0x0085, trims: false),
        (unit: 0x00a0, trims: true),
        (unit: 0x1680, trims: true),
        (unit: 0x180e, trims: false),
        (unit: 0x2000, trims: true),
        (unit: 0x2001, trims: true),
        (unit: 0x2002, trims: true),
        (unit: 0x2003, trims: true),
        (unit: 0x2004, trims: true),
        (unit: 0x2005, trims: true),
        (unit: 0x2006, trims: true),
        (unit: 0x2007, trims: true),
        (unit: 0x2008, trims: true),
        (unit: 0x2009, trims: true),
        (unit: 0x200a, trims: true),
        (unit: 0x2028, trims: true),
        (unit: 0x2029, trims: true),
        (unit: 0x202f, trims: true),
        (unit: 0x205f, trims: true),
        (unit: 0x3000, trims: true),
        (unit: 0xfeff, trims: true),
      ]) {
        final char = String.fromCharCode(trimCase.unit);
        final label = trimCase.unit.toRadixString(16).padLeft(4, '0');
        for (final languageCase in [
          (name: '単独', input: char, expected: trimCase.trims ? null : char),
          (
            name: '前',
            input: '${char}js',
            expected: trimCase.trims ? 'js' : '${char}js',
          ),
          (
            name: '後',
            input: 'js$char',
            expected: trimCase.trims ? 'js' : 'js$char',
          ),
          (
            name: '前後',
            input: '${char}js$char',
            expected: trimCase.trims ? 'js' : '${char}js$char',
          ),
          (name: '内側', input: 'j${char}s', expected: 'j${char}s'),
        ]) {
          test('U+$labelを言語名の${languageCase.name}に置く', () {
            final result = parser.parse('```${languageCase.input}\nfoo\n```');
            expect(result, isA<Success<List<MfmNode>>>());
            expect(
              serializeMfmAst((result as Success<List<MfmNode>>).value),
              [
                {
                  'type': 'codeBlock',
                  'props': {'code': 'foo', 'language': languageCase.expected},
                  'children': <Object?>[],
                },
              ],
            );
          });
        }
      }

      test('JS空白を除去しても内側のU+0085は言語名として保持する', () {
        final result = parser.parse('```\ufeff \u0085 \u00a0\nfoo\n```');
        expect(result, isA<Success<List<MfmNode>>>());
        expect((result as Success<List<MfmNode>>).value, const [
          CodeBlockNode(code: 'foo', language: '\u0085'),
        ]);
      });
    });

    group('mfm-js互換: 空の本文を拒否する', () {
      final codeBlockParser = CodeBlockParser().build();
      final fullParser = MfmParser().build();

      for (final newlineCase in const [
        (name: 'LF', value: '\n'),
        (name: 'CRLF', value: '\r\n'),
        (name: 'CR', value: '\r'),
      ]) {
        test('${newlineCase.name}の空コードブロックは基本パーサーで失敗する', () {
          final input = '```${newlineCase.value}${newlineCase.value}```';
          expect(codeBlockParser.parse(input), isA<Failure>());
        });

        test('${newlineCase.name}の空コードブロックは入力全体をTextにする', () {
          final input = '```${newlineCase.value}${newlineCase.value}```';
          final result = fullParser.parse(input);
          expect(result, isA<Success<List<MfmNode>>>());
          expect((result as Success<List<MfmNode>>).value, [TextNode(input)]);
        });
      }

      test('言語指定があっても空の本文は入力全体をTextにする', () {
        const input = '```dart\n\n```';
        final result = fullParser.parse(input);
        expect(result, isA<Success<List<MfmNode>>>());
        expect((result as Success<List<MfmNode>>).value, const [
          TextNode(input),
        ]);
      });

      test('空コードブロックの後でもboldを解析する', () {
        const input = '```\n\n```\n**bold**';
        final result = fullParser.parse(input);
        expect(result, isA<Success<List<MfmNode>>>());
        expect((result as Success<List<MfmNode>>).value, const [
          TextNode('```\n\n```\n'),
          BoldNode([TextNode('bold')]),
        ]);
      });

      test('本文中の空行は非空コードブロックの内容として維持する', () {
        const input = '```dart\na\n\nb\n```';
        final result = fullParser.parse(input);
        expect(result, isA<Success<List<MfmNode>>>());
        expect((result as Success<List<MfmNode>>).value, const [
          CodeBlockNode(code: 'a\n\nb', language: 'dart'),
        ]);
      });
    });

    group('mfm-js互換: 行頭・行末チェック', () {
      test('行の途中から始まるコードブロックは認識されない', () {
        final m = MfmParser().build();
        final result = m.parse('text ```\ncode\n```');
        expect(result is Success, isTrue);
        final nodes = (result as Success).value as List<MfmNode>;
        // コードブロックとして認識されない（インラインコード等になる可能性がある）
        expect(nodes.any((n) => n is CodeBlockNode), isFalse);
      });

      test('行の途中で終わるコードブロックは認識されない', () {
        final m = MfmParser().build();
        final result = m.parse('```\ncode\n``` text');
        expect(result is Success, isTrue);
        final nodes = (result as Success).value as List<MfmNode>;
        // コードブロックとして認識されない（インラインコード等になる可能性がある）
        expect(nodes.any((n) => n is CodeBlockNode), isFalse);
      });

      test('正常なコードブロックは認識される（行頭・行末）', () {
        final m = MfmParser().build();
        final result = m.parse('```\ncode\n```');
        expect(result is Success, isTrue);
        final nodes = (result as Success).value as List<MfmNode>;
        expect(
          nodes,
          [
            const CodeBlockNode(
              code: 'code',
            ),
          ],
        );
      });

      test('改行の後は行頭として認識される', () {
        final m = MfmParser().build();
        final result = m.parse('text\n```\ncode\n```');
        expect(result is Success, isTrue);
        final nodes = (result as Success).value as List<MfmNode>;
        expect(
          nodes,
          [
            const TextNode('text'),
            const CodeBlockNode(
              code: 'code',
            ),
          ],
        );
      });

      test('行末の後の改行がある場合も正常に認識される', () {
        final m = MfmParser().build();
        final result = m.parse('```\ncode\n```\n');
        expect(result is Success, isTrue);
        final nodes = (result as Success).value as List<MfmNode>;
        expect(
          nodes,
          [
            const CodeBlockNode(
              code: 'code',
            ),
          ],
        );
      });
    });
  });
}
