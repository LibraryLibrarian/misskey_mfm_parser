import 'package:misskey_mfm_parser/src/ast.dart';
import 'package:misskey_mfm_parser/src/parser/parser.dart';
import 'package:petitparser/petitparser.dart';
import 'package:test/test.dart';

import '../../../support/ast_json.dart';

Map<String, Object?> _text(String text) => {
  'type': 'text',
  'props': {'text': text},
  'children': <Object?>[],
};

Map<String, Object?> _element(
  String type,
  List<Map<String, Object?>> children, {
  Map<String, Object?> props = const {},
}) => {'type': type, 'props': props, 'children': children};

void main() {
  final parser = MfmParser().build();
  const url = <String, Object?>{
    'type': 'url',
    'props': {'url': 'http://a', 'brackets': false},
    'children': <Object?>[],
  };

  // mfm.js 0.28.0 の実出力を確認した期待値。
  // 葉の children: []、コンテナの props: {}、url の brackets: false は
  // test/support/ast_json.dart の比較形式に合わせて補完する。
  for (final (newlineName, newline) in [
    ('LF', '\n'),
    ('CR', '\r'),
    ('CRLF', '\r\n'),
  ]) {
    for (final silent in [false, true]) {
      final open = silent ? '?[' : '[';
      group('$newlineName / silent=$silent', () {
        final rejected = [
          (
            name: '通常テキスト途中の改行',
            label: 'a$newline',
            beforeUrl: [_text('${open}a$newline](')],
          ),
          (
            name: '複数行の通常テキスト',
            label: 'a${newline}next',
            beforeUrl: [_text('${open}a${newline}next](')],
          ),
          (
            name: 'ラベル先頭の改行',
            label: newline,
            beforeUrl: [_text('$open$newline](')],
          ),
          (
            name: '太字と通常テキストの後の改行',
            label: '**a**text$newline',
            beforeUrl: [
              _text(open),
              _element('bold', [_text('a')]),
              _text('text$newline]('),
            ],
          ),
          (
            name: '絵文字コードと通常テキストの後の改行',
            label: ':smile: text$newline',
            beforeUrl: [
              _text(open),
              _element('emojiCode', [], props: {'name': 'smile'}),
              _text(' text$newline]('),
            ],
          ),
          (
            name: 'Unicode絵文字と通常テキストの後の改行',
            label: '😀text$newline',
            beforeUrl: [
              _text(open),
              _element('unicodeEmoji', [], props: {'emoji': '😀'}),
              _text('text$newline]('),
            ],
          ),
          (
            name: 'fnと通常テキストの後の改行',
            label: '\$[x a]text$newline',
            beforeUrl: [
              _text(open),
              _element('fn', [_text('a')], props: {'name': 'x', 'args': {}}),
              _text('text$newline]('),
            ],
          ),
          (
            name: '入れ子のタグと通常テキストの後の改行',
            label: '<b><i>a</i></b>text$newline',
            beforeUrl: [
              _text(open),
              _element('bold', [
                _element('italic', [_text('a')]),
              ]),
              _text('text$newline]('),
            ],
          ),
          (
            name: '太字内部とラベル直下の両方に改行',
            label: '**a$newline**text$newline',
            beforeUrl: [
              _text(open),
              _element('bold', [_text('a$newline')]),
              _text('text$newline]('),
            ],
          ),
        ];

        for (final example in rejected) {
          test('${example.name}はリンクにしない', () {
            final input = '$open${example.label}](http://a)';
            final result = parser.parse(input);
            expect(result, isA<Success<List<MfmNode>>>());
            expect(result.position, input.length);
            expect(serializeMfmAst(result.value), [
              ...example.beforeUrl,
              url,
              _text(')'),
            ]);
          });
        }

        // 改行はラベル要素の境界で拒否する。構文内部で消費する改行は許可する。
        final accepted = [
          (
            name: '太字内部の改行',
            label: '**a${newline}b**',
            children: [
              _element('bold', [_text('a${newline}b')]),
            ],
          ),
          (
            name: 'fn内部の改行',
            label: '\$[x a${newline}b]',
            children: [
              _element(
                'fn',
                [_text('a${newline}b')],
                props: {'name': 'x', 'args': {}},
              ),
            ],
          ),
          (
            name: '入れ子のタグ内部の改行',
            label: '<b><i>a${newline}b</i></b>',
            children: [
              _element('bold', [
                _element('italic', [_text('a${newline}b')]),
              ]),
            ],
          ),
          (
            name: 'fnと太字の入れ子内部の改行',
            label: '\$[x <b>a${newline}b</b>]',
            children: [
              _element(
                'fn',
                [
                  _element('bold', [_text('a${newline}b')]),
                ],
                props: {'name': 'x', 'args': {}},
              ),
            ],
          ),
        ];

        for (final example in accepted) {
          test('${example.name}はリンクにする', () {
            final input = '$open${example.label}](http://a)';
            final result = parser.parse(input);
            expect(result, isA<Success<List<MfmNode>>>());
            expect(result.position, input.length);
            expect(serializeMfmAst(result.value), [
              _element(
                'link',
                example.children,
                props: {'silent': silent, 'url': 'http://a'},
              ),
            ]);
          });
        }
      });
    }
  }
}
