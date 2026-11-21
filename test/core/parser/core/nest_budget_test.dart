import 'package:misskey_mfm_parser/src/ast.dart';
import 'package:misskey_mfm_parser/src/parser/core/nest.dart';
import 'package:misskey_mfm_parser/src/parser/parser.dart';
import 'package:petitparser/petitparser.dart';
import 'package:test/test.dart';

void main() {
  group('NestState.enter（mfm.jsのnestableに相当）', () {
    test('予算がなければ深さの制限だけを見る', () {
      final state = NestState(limit: 3);
      expect(state.enter(), isTrue); // depth 1
      expect(state.enter(), isTrue); // depth 2
      expect(state.enter(), isFalse); // depth 3 >= limit
      expect(state.budget, isNull);
    });

    test('入るたびに予算を1つ消費し、0になると入れない', () {
      final state = NestState(budget: 2);
      expect(state.enter(), isTrue);
      expect(state.enter(), isTrue);
      expect(state.budget, 0);
      expect(state.enter(), isFalse);
      expect(state.budget, 0);
    });

    test('深さの制限で拒否されたときも予算は消費される', () {
      final state = NestState(limit: 1, budget: 5);
      expect(state.enter(), isFalse);
      expect(state.budget, 4);
    });

    test('depthは成否にかかわらず加算される', () {
      final state = NestState(budget: 0);
      expect(state.enter(), isFalse);
      expect(state.depth, 1);
    });
  });

  group('nest（予算）', () {
    Parser<MfmNode> build(NestState state) {
      final inner = char('a').map<MfmNode>((_) => const TextNode('inner'));
      return nest(inner, state: state);
    }

    test('予算が残っていればinnerを実行する', () {
      final state = NestState(limit: 20, budget: 1);
      final result = build(state).parse('a');
      expect((result as Success<MfmNode>).value, const TextNode('inner'));
      expect(state.depth, 0);
    });

    test('予算が尽きていればfallbackの1文字テキストになる', () {
      final state = NestState(limit: 20, budget: 0);
      final result = build(state).parse('a');
      expect((result as Success<MfmNode>).value, const TextNode('a'));
      expect(state.depth, 0);
    });
  });

  group('withNestBudget', () {
    test('予算は input.length * 20 + 1000 で、パースごとに初期化される', () {
      final state = NestState(limit: 20);
      final parser = withNestBudget(any().star(), state);
      int budgetAfterParsing(String input) {
        parser.parse(input);
        return state.budget!;
      }

      expect(budgetAfterParsing('abc'), 3 * 20 + 1000);

      // 前回のパースで予算を使い切っていても影響しない
      state.budget = 0;
      expect(budgetAfterParsing('abcde'), 5 * 20 + 1000);
    });
  });

  group('括弧内の予算消費（mfm.js 0.28.0と同じ結果）', () {
    // 括弧内の各要素と終端の試行が予算を消費するため、予算が尽きた後の
    // 末尾の #a(b(c)) は括弧を含められない。結果はmfm.js 0.28.0で確認した値。
    test('URLの括弧で予算を使い切ると、後続のハッシュタグの括弧がテキストになる', () {
      final input = 'https://a(' * 100 + ' z **tail** #a(b(c))';
      final result =
          MfmParser().build(nestLimit: 100).parse(input)
              as Success<List<MfmNode>>;
      expect(result.value.sublist(result.value.length - 3), const [
        TextNode(' '),
        HashtagNode('a'),
        TextNode('(b(c))'),
      ]);
    });

    test('予算が残っていれば括弧を含むハッシュタグになる', () {
      final result =
          MfmParser().build().parse('#a(b(c))') as Success<List<MfmNode>>;
      expect(result.value, const [HashtagNode('a(b(c))')]);
    });
  });

  group('MfmParser', () {
    test('同じパーサーを繰り返し使っても予算が尽きない', () {
      final parser = MfmParser().build();
      const input = '**a** <b>b</b> \$[x c] #tag(d) https://example.com/(e)';
      final first = (parser.parse(input) as Success<List<MfmNode>>).value;
      for (var i = 0; i < 500; i++) {
        expect((parser.parse(input) as Success<List<MfmNode>>).value, first);
      }
    });
  });
}
