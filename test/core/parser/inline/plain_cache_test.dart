import 'dart:convert';

import 'package:misskey_mfm_parser/src/ast.dart';
import 'package:misskey_mfm_parser/src/parser/parser.dart';
import 'package:petitparser/petitparser.dart';
import 'package:test/test.dart';

import '../../../support/ast_json.dart';

// Expected ASTs were checked against mfm.js 0.28.0 parse/parseSimple.
// Keep the oracle output here so these tests do not depend on Node.js.
void main() {
  const commonCases = [
    (
      name: 'closed plain',
      input: '<plain>abc</plain>',
      expected: '''
        [{"type":"plain","props":{},"children":[
          {"type":"text","props":{"text":"abc"},"children":[]}
        ]}]
      ''',
    ),
    (
      name: 'nested opening tag uses the first closing tag',
      input: '<plain><plain>x</plain></plain>',
      expected: '''
        [{"type":"plain","props":{},"children":[
          {"type":"text","props":{"text":"<plain>x"},"children":[]}
        ]},{"type":"text","props":{"text":"</plain>"},"children":[]}]
      ''',
    ),
    (
      name: 'closing tag in the middle leaves an unclosed suffix',
      input: '<plain><plain>x</plain><plain>:wave:',
      expected: '''
        [{"type":"plain","props":{},"children":[
          {"type":"text","props":{"text":"<plain>x"},"children":[]}
        ]},{"type":"text","props":{"text":"<plain>"},"children":[]},
          {"type":"emojiCode","props":{"name":"wave"},"children":[]}]
      ''',
    ),
    (
      name: 'search advances beyond an earlier closing tag',
      input: '<plain>a</plain><plain>b</plain>',
      expected: '''
        [{"type":"plain","props":{},"children":[
          {"type":"text","props":{"text":"a"},"children":[]}
        ]},{"type":"plain","props":{},"children":[
          {"type":"text","props":{"text":"b"},"children":[]}
        ]}]
      ''',
    ),
    (
      name: 'empty plain fails without hiding a later valid plain',
      input: '<plain></plain><plain>x</plain>',
      expected: '''
        [{"type":"text","props":{"text":"<plain></plain>"},"children":[]},
          {"type":"plain","props":{},"children":[
            {"type":"text","props":{"text":"x"},"children":[]}
          ]}]
      ''',
    ),
    (
      name: 'newline-only content is still invalid',
      input: '<plain>\n</plain>',
      expected: r'''
        [{"type":"text","props":{"text":"<plain>\n</plain>"},"children":[]}]
      ''',
    ),
    (
      name: 'one leading and trailing CRLF are stripped',
      input: '<plain>\r\nabc\r\n</plain>',
      expected: '''
        [{"type":"plain","props":{},"children":[
          {"type":"text","props":{"text":"abc"},"children":[]}
        ]}]
      ''',
    ),
    (
      name: 'one leading and trailing CR are stripped',
      input: '<plain>\ra\r</plain>',
      expected: '''
        [{"type":"plain","props":{},"children":[
          {"type":"text","props":{"text":"a"},"children":[]}
        ]}]
      ''',
    ),
    (
      name: 'additional newlines are preserved',
      input: '<plain>\n\nabc\n\n</plain>',
      expected: r'''
        [{"type":"plain","props":{},"children":[
          {"type":"text","props":{"text":"\nabc\n"},"children":[]}
        ]}]
      ''',
    ),
    (
      name: 'backtracking to an earlier opening tag keeps its closing tag',
      input: '[<plain>:wave:](https://example.com) <plain>x</plain>',
      expected: '''
        [{"type":"text","props":{"text":"["},"children":[]},
          {"type":"plain","props":{},"children":[
            {"type":"text","props":{
              "text":":wave:](https://example.com) <plain>x"
            },"children":[]}
          ]}]
      ''',
    ),
  ];

  for (final simple in [false, true]) {
    group('plain search cache (${simple ? 'simple' : 'full'})', () {
      final parser = simple ? MfmParser().buildSimple() : MfmParser().build();

      void expectAst(String input, Object? expected) {
        final result = parser.parse(input);
        expect(result, isA<Success<List<MfmNode>>>());
        expect(result.position, input.length);
        expect(
          serializeMfmAst((result as Success<List<MfmNode>>).value),
          expected,
        );
      }

      for (final fixture in commonCases) {
        test(fixture.name, () {
          expectAst(fixture.input, jsonDecode(fixture.expected));
        });
      }

      test('3000 unclosed opening tags preserve all text', () {
        final input = '<plain>' * 3000;
        expectAst(input, [
          {
            'type': 'text',
            'props': {'text': input},
            'children': <Object?>[],
          },
        ]);
      });

      test('unclosed plain keeps subsequent syntax parsing', () {
        expectAst(
          '<plain>:wave: **bold**',
          jsonDecode(
            simple
                ? '''
                  [{"type":"text","props":{"text":"<plain>"},"children":[]},
                    {"type":"emojiCode","props":{"name":"wave"},"children":[]},
                    {"type":"text","props":{"text":" **bold**"},"children":[]}]
                '''
                : '''
                  [{"type":"text","props":{"text":"<plain>"},"children":[]},
                    {"type":"emojiCode","props":{"name":"wave"},"children":[]},
                    {"type":"text","props":{"text":" "},"children":[]},
                    {"type":"bold","props":{},"children":[
                      {"type":"text","props":{"text":"bold"},"children":[]}
                    ]}]
                ''',
          ),
        );
      });

      test('parser reuse handles present and absent closing tags', () {
        for (var i = 0; i < 3; i++) {
          expectAst(
            '<plain>:wave:',
            jsonDecode('''
            [{"type":"text","props":{"text":"<plain>"},"children":[]},
              {"type":"emojiCode","props":{"name":"wave"},"children":[]}]
          '''),
          );
          expectAst(
            '<plain>:wave:</plain>',
            jsonDecode('''
            [{"type":"plain","props":{},"children":[
              {"type":"text","props":{"text":":wave:"},"children":[]}
            ]}]
          '''),
          );
        }
      });

      test('plain inside formatting keeps the existing AST', () {
        expectAst(
          '**<plain>x</plain>**',
          jsonDecode(
            simple
                ? '''
                  [{"type":"text","props":{"text":"**"},"children":[]},
                    {"type":"plain","props":{},"children":[
                      {"type":"text","props":{"text":"x"},"children":[]}
                    ]},{"type":"text","props":{"text":"**"},"children":[]}]
                '''
                : '''
                  [{"type":"bold","props":{},"children":[
                    {"type":"plain","props":{},"children":[
                      {"type":"text","props":{"text":"x"},"children":[]}
                    ]}
                  ]}]
                ''',
          ),
        );
      });

      test('plain inside a link label keeps the existing AST', () {
        expectAst(
          '[<plain>x</plain>](https://example.com)',
          jsonDecode(
            simple
                ? '''
                  [{"type":"text","props":{"text":"["},"children":[]},
                    {"type":"plain","props":{},"children":[
                      {"type":"text","props":{"text":"x"},"children":[]}
                    ]},{"type":"text","props":{
                      "text":"](https://example.com)"
                    },"children":[]}]
                '''
                : '''
                  [{"type":"link","props":{
                    "silent":false,"url":"https://example.com"
                  },"children":[
                    {"type":"plain","props":{},"children":[
                      {"type":"text","props":{"text":"x"},"children":[]}
                    ]}
                  ]}]
                ''',
          ),
        );
      });

      test('quote buffers do not reuse outer-buffer search results', () {
        expectAst(
          '> <plain>unclosed\n\n<plain>x</plain>',
          jsonDecode(
            simple
                ? r'''
                  [{"type":"text","props":{"text":"> "},"children":[]},
                    {"type":"plain","props":{},"children":[
                      {"type":"text","props":{
                        "text":"unclosed\n\n<plain>x"
                      },"children":[]}
                    ]}]
                '''
                : '''
                  [{"type":"quote","props":{},"children":[
                    {"type":"text","props":{
                      "text":"<plain>unclosed"
                    },"children":[]}
                  ]},{"type":"plain","props":{},"children":[
                    {"type":"text","props":{"text":"x"},"children":[]}
                  ]}]
                ''',
          ),
        );
      });
    });
  }
}
