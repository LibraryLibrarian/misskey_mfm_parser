import 'package:petitparser/petitparser.dart';

import '../../ast.dart';

/// ネスト状態
///
/// [depth]現在の深さ / [limit]上限（nullなら無制限）/
/// [budget]残りのネスト試行回数（nullなら無制限）
///
/// [budget]はmfm-jsの`nestBudget`に相当する。入力が1回パースされる間に、
/// ネスト構文を試す回数を制限して、解析にかかる計算量を抑える。
/// 0になるとそれ以降のネスト構文はテキストとして扱われる。
class NestState {
  NestState({this.depth = 0, this.limit, this.budget});
  int depth;
  final int? limit;
  int? budget;

  /// ネストに入り、さらに解析を続けてよいかを返す。
  ///
  /// mfm-js互換: depth++は制限チェックの前に実行し、予算は深さの判定より先に
  /// 確認・消費する。呼び出し側は終了時にdepth--する。
  bool enter() {
    depth++;
    final remaining = budget;
    if (remaining != null) {
      if (remaining <= 0) return false;
      budget = remaining - 1;
    }
    final max = limit;
    return max == null || depth < max;
  }
}

class _NestParser extends Parser<MfmNode> {
  _NestParser(this.inner, this.fallback, this.state);
  final Parser<MfmNode> inner;
  final Parser<MfmNode> fallback;
  final NestState? state;

  @override
  Result<MfmNode> parseOn(Context context) {
    final used = state ?? NestState();
    // mfm-js互換: depth < limit かつ予算が残っている場合のみinnerを実行、
    // それ以外はfallback
    if (!used.enter()) {
      final result = fallback.parseOn(context);
      used.depth--;
      return result;
    }
    final result = inner.parseOn(context);
    used.depth--;
    if (result is Success) return result;
    return fallback.parseOn(context);
  }

  @override
  Parser<MfmNode> copy() => _NestParser(inner, fallback, state);
}

/// ネスト可能合成（状態付き）
///
/// [inline]ネスト対象のパーサー
/// [state]ネスト状態（nullの場合は無制限）
/// [fallback]失敗時の代替（未指定は1文字テキスト）
Parser<MfmNode> nest(
  Parser<MfmNode> inline, {
  NestState? state,
  Parser<MfmNode>? fallback,
}) {
  final oneChar = any().map<MfmNode>(
    (dynamic c) => TextNode(c as String),
  );
  final fb = fallback ?? oneChar;
  return _NestParser(inline, fb, state);
}

class _NestBudgetParser<T> extends DelegateParser<T, T> {
  _NestBudgetParser(super.delegate, this.state);
  final NestState state;

  @override
  Result<T> parseOn(Context context) {
    // mfm-js互換: 予算は入力の長さから決め、1回のパースごとに初期化する
    state.budget = context.buffer.length * 20 + 1000;
    return delegate.parseOn(context);
  }

  @override
  _NestBudgetParser<T> copy() => _NestBudgetParser<T>(delegate, state);
}

/// 入力全体のパースごとにネスト予算を初期化する。
///
/// 予算は`input.length * 20 + 1000`で、mfm-jsの`nestBudget`と同じ。
/// 最上位のパーサーだけを包むこと（引用内の再パースなどは同じ予算を共有する）。
Parser<T> withNestBudget<T>(Parser<T> parser, NestState state) =>
    _NestBudgetParser<T>(parser, state);
