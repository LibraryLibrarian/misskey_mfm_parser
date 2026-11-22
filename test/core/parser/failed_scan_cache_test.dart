import 'package:misskey_mfm_parser/src/ast.dart';
import 'package:misskey_mfm_parser/src/parser/block/center.dart';
import 'package:misskey_mfm_parser/src/parser/common/utils.dart';
import 'package:misskey_mfm_parser/src/parser/core/nest.dart';
import 'package:misskey_mfm_parser/src/parser/inline/bold.dart';
import 'package:misskey_mfm_parser/src/parser/inline/link.dart';
import 'package:misskey_mfm_parser/src/parser/parser.dart';
import 'package:petitparser/petitparser.dart';
import 'package:test/test.dart';

import '../../support/ast_json.dart';

void main() {
  final parser = MfmParser().build();

  void expectAst(String input, List<MfmNode> expected) {
    final result = parser.parse(input) as Success<List<MfmNode>>;
    expect(result.position, input.length);
    expect(serializeMfmAst(result.value), serializeMfmAst(expected));
  }

  // These expected ASTs were captured before introducing the scan caches.
  group('failed scan AST compatibility', () {
    test('ordinary and silent links with nested formatting', () {
      expectAst(
        '[a](https://example.com) ?[a **b**](https://example.com)',
        const [
          LinkNode(
            silent: false,
            url: 'https://example.com',
            children: [TextNode('a')],
          ),
          TextNode(' '),
          LinkNode(
            silent: true,
            url: 'https://example.com',
            children: [
              TextNode('a '),
              BoldNode([TextNode('b')]),
            ],
          ),
        ],
      );
    });

    test('a closing bracket in plain is not the label terminator', () {
      expectAst('[<plain>]x</plain>](https://example.com)', const [
        LinkNode(
          silent: false,
          url: 'https://example.com',
          children: [
            PlainNode([TextNode(']x')]),
          ],
        ),
      ]);
    });

    test('a close in the middle leaves an unclosed link suffix', () {
      expectAst('[a[a](https://example.com)[a[a', const [
        LinkNode(
          silent: false,
          url: 'https://example.com',
          children: [TextNode('a[a')],
        ),
        TextNode('[a[a'),
      ]);
    });

    test('empty and invalid links do not hide a later valid link', () {
      expectAst('[][a](no)[b](https://example.com)', const [
        TextNode('[][a](no)'),
        LinkNode(
          silent: false,
          url: 'https://example.com',
          children: [TextNode('b')],
        ),
      ]);
    });

    test('math uses the first close and leaves an unclosed suffix', () {
      expectAst(r'\(\(a\)\(', const [
        MathInlineNode(r'\(a'),
        TextNode(r'\('),
      ]);
    });

    for (final newline in ['\n', '\r', '\r\n']) {
      test('math search stops at ${newline.codeUnits}', () {
        expectAst('\\(a$newline\\(b\\)', [
          TextNode('\\(a$newline'),
          const MathInlineNode('b'),
        ]);
      });
      test('center trims ${newline.codeUnits}', () {
        expectAst('<center>${newline}a$newline</center>', const [
          CenterNode([TextNode('a')]),
        ]);
      });
    }

    test('center opening tags in the body are ordinary inline text', () {
      expectAst('<center>\n<center>\nx\n</center>\n<center>\n', const [
        CenterNode([TextNode('<center>\nx')]),
        TextNode('<center>\n'),
      ]);
    });

    test('center still checks both line boundaries', () {
      expectAst('x<center>\na\n</center>', const [
        TextNode('x<center>\na\n</center>'),
      ]);
      expectAst('<center>\na</center>x\n<center>\nb\n</center>', const [
        TextNode('<center>\na</center>x'),
        CenterNode([TextNode('b')]),
      ]);
    });

    test('quote buffers have independent link and center caches', () {
      expectAst('> [a[a\n\n[a](https://example.com)', const [
        QuoteNode([TextNode('[a[a')]),
        LinkNode(
          silent: false,
          url: 'https://example.com',
          children: [TextNode('a')],
        ),
      ]);
      expectAst('> <center>\na\n\n<center>\nx\n</center>', const [
        QuoteNode([TextNode('<center>')]),
        TextNode('a\n'),
        CenterNode([TextNode('x')]),
      ]);
    });

    for (final unit in ['[', '[a', r'\(', '<center>\n']) {
      for (final count in [2, 20, 70]) {
        final repeated = unit * count;
        test('$unit x$count preserves surrounding plain and bold', () {
          expectAst(
            '<plain>before</plain> **head** $repeated '
            '**tail** <plain>after</plain>',
            [
              const PlainNode([TextNode('before')]),
              const TextNode(' '),
              const BoldNode([TextNode('head')]),
              TextNode(' $repeated '),
              const BoldNode([TextNode('tail')]),
              const TextNode(' '),
              const PlainNode([TextNode('after')]),
            ],
          );
        });
        test('$unit x$count inside bold and a link label', () {
          expectAst('**$repeated**', [
            BoldNode([TextNode(repeated)]),
          ]);
          if (repeated.contains('\n')) {
            // mfm.js 0.28.0: ラベル直下に改行があるとリンクにならない。
            expectAst('[${repeated}x](https://example.com)', [
              TextNode('[${repeated}x]('),
              const UrlNode(url: 'https://example.com'),
              const TextNode(')'),
            ]);
          } else {
            expectAst('[${repeated}x](https://example.com)', [
              LinkNode(
                silent: false,
                url: 'https://example.com',
                children: [TextNode('${repeated}x')],
              ),
            ]);
          }
        });
      }
      test('5000 unclosed $unit preserve all input', () {
        final input = unit * 5000;
        expectAst(input, [TextNode(input)]);
      });
    }

    test('failed center attempts still exhaust the nesting budget', () {
      final repeated = '<center>\n' * 70;
      expectAst('$repeated **tail** #a(b(c))', [
        TextNode('$repeated '),
        const BoldNode([TextNode('tail')]),
        const TextNode(' '),
        const HashtagNode('a'),
        const TextNode('(b(c))'),
      ]);
    });

    test('reuse resets failed spans, including equal length inputs', () {
      for (var i = 0; i < 3; i++) {
        expectAst(r'\(a!!', const [TextNode(r'\(a!!')]);
        expectAst(r'\(a\)', const [MathInlineNode('a')]);
        expectAst('[a](no)', const [TextNode('[a](no)')]);
        expectAst('[a](https://a)', const [
          LinkNode(silent: false, url: 'https://a', children: [TextNode('a')]),
        ]);
        expectAst('<center>\na\nxxxxxxxxx', const [
          TextNode('<center>\na\nxxxxxxxxx'),
        ]);
        expectAst('<center>\na\n</center>', const [
          CenterNode([TextNode('a')]),
        ]);
      }
    });
  });

  group('failed scan nesting budget compatibility', () {
    for (final center in [false, true]) {
      for (final limit in [1, 2, 4, 20]) {
        test('${center ? 'center' : 'link'} depth limit $limit', () {
          final cases = center
              ? [
                  '<center>\n' * 8,
                  '${'<center>\n' * 8}**tail**',
                  '<center>\nx</center>bad\n<center>\ny\n</center>',
                ]
              : [
                  '[a' * 20,
                  '${'[a' * 20} **tail**',
                  '[a**b**[a**c**](bad)[a](https://a/(b))',
                  '?[a[a\n**b**[a',
                ];
          final cached = _buildScanParser(
            center: center,
            cached: true,
            limit: limit,
          );
          final uncached = _buildScanParser(
            center: center,
            cached: false,
            limit: limit,
          );
          for (var budget = 0; budget < 200; budget++) {
            for (final input in cases) {
              cached.state.budget = budget;
              uncached.state.budget = budget;
              final actual =
                  cached.parser.parse(input) as Success<List<MfmNode>>;
              final expected =
                  uncached.parser.parse(input) as Success<List<MfmNode>>;
              expect(
                serializeMfmAst(actual.value),
                serializeMfmAst(expected.value),
                reason: 'budget=$budget input=$input',
              );
              expect(
                cached.state.budget,
                uncached.state.budget,
                reason: 'budget=$budget input=$input',
              );
              expect(cached.state.depth, 0);
            }
          }
        });
      }
    }
  });
}

({Parser<List<MfmNode>> parser, NestState state}) _buildScanParser({
  required bool center,
  required bool cached,
  required int limit,
}) {
  final state = NestState(limit: limit);
  final links = LinkParser();
  final centers = CenterParser();
  final inline = undefined<MfmNode>();
  final bold = BoldParser().buildWithInner(inline, state: state);
  final text = links.trackLabelText(
    noneOf(']*').plus().flatten().map<MfmNode>(TextNode.new),
  );
  final oneChar = any().map<MfmNode>(TextNode.new);
  inline.set((bold | text | oneChar).cast<MfmNode>());
  final syntax = center
      ? centers.buildWithInner(inline, state: state)
      : links.buildWithFallback(inline, state: state);
  final parser = (syntax | bold | oneChar)
      .cast<MfmNode>()
      .plus()
      .map(mergeAdjacentTextNodes)
      .end();
  return (
    parser: cached
        ? links.withSearchCache(centers.withSearchCache(parser))
        : parser,
    state: state,
  );
}
