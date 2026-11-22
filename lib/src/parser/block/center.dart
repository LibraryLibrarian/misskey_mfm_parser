import 'package:petitparser/petitparser.dart';

import '../../ast.dart';
import '../common/utils.dart';
import '../core/guards.dart';
import '../core/nest.dart';
import '../core/scan_cache.dart';

/// 中央寄せブロックパーサー
///
/// "&lt;center&gt;…&lt;/center&gt;" で囲まれたブロックを解析
///
/// mfm-js仕様:
/// - `<center>` は行頭でなければならない（入力先頭または直前が改行）
/// - `</center>` は行末でなければならない（入力末尾または直後が改行）
/// - 前後の改行はブロック構文として消費される
class CenterParser {
  final _cache = FailedScanCache();

  Parser<T> withSearchCache<T>(Parser<T> parser) =>
      _cache.withSearchCache(parser);

  /// center タグ（基本版）
  Parser<MfmNode> build() {
    final lineBreak = newline();
    final start = string('<center>');
    final end = string('</center>');
    final inner = ((lineBreak.optional() & end).not() & any())
        .pick(1)
        .plus()
        .flatten()
        .map<MfmNode>(TextNode.new);

    // mfm-js仕様: 行頭/行末チェック、前後の改行消費
    return (lineBreak.optional() &
            lineBegin() &
            start &
            lineBreak.optional() &
            inner &
            lineBreak.optional() &
            end &
            lineEnd() &
            lineBreak.optional())
        .map<MfmNode>((result) {
          final content = result[4] as MfmNode;
          return CenterNode(mergeAdjacentTextNodes([content]));
        });
  }

  /// center タグ（再帰合成版）
  /// [state] ネスト状態（共有される）
  ///
  /// mfm-js仕様:
  /// - `<center>` は行頭でなければならない
  /// - `</center>` は行末でなければならない
  /// - 開始タグ前/終了タグ後の改行はブロック構文として消費される
  /// - 開始タグ直後/終了タグ直前の改行はトリミングされる
  Parser<MfmNode> buildWithInner(Parser<MfmNode> inline, {NestState? state}) {
    final lineBreak = newline();
    final start = string('<center>');
    final end = string('</center>');

    // 開始タグ直後の改行を削除
    final optionalNewlineAfterStart = lineBreak.optional();

    // 内容: 終了タグが出現するまでのインラインノード
    // mfm-js:
    //  P.seq(
    //    P.notMatch(
    //      P.seq(newLine.option(), close)
    //    ), nest(r.inline)
    //   ).select(1).many(1)
    final inner = seq2(
      (lineBreak.optional() & end).not(),
      nest(inline, state: state),
    ).map((r) => r.$2);

    // 終了タグ直前の改行チェック
    final optionalNewlineBeforeEnd = lineBreak.optional();

    // mfm-js仕様に基づくパーサー構造:
    // [改行?, 行頭, <center>, 改行?, 内容, 改行?, </center>, 行末, 改行?]
    final after =
        optionalNewlineBeforeEnd & end & lineEnd() & lineBreak.optional();
    final body = _CenterBody(inner, after, _cache, state);
    return (lineBreak.optional() &
            lineBegin() &
            start &
            optionalNewlineAfterStart &
            body)
        .pick(4)
        .cast<MfmNode>();
  }
}

class _CenterBody extends Parser<MfmNode> {
  _CenterBody(this.inner, this.after, this.cache, this.state);
  final Parser<MfmNode> inner;
  final Parser<dynamic> after;
  final FailedScanCache cache;
  final NestState? state;

  @override
  Result<MfmNode> parseOn(Context context) {
    // 行頭条件と開始タグを満たした後の内容部分だけをキャッシュする。
    final scan = cache.start(context.buffer, state, this);
    final children = <MfmNode>[];
    var current = context;
    while (true) {
      final cachedFailure = scan?.replay(current.position);
      if (cachedFailure != null) {
        scan?.fail(cachedFailure);
        return context.failure(cachedFailure);
      }
      scan?.visit(current.position);
      final result = inner.parseOn(current);
      if (result is Failure) break;
      children.add(result.value);
      current = Context(context.buffer, result.position);
    }
    if (children.isEmpty) return context.failure('center content expected');
    final result = after.parseOn(current);
    if (result is Failure) {
      scan?.fail(result.message);
      return result;
    }
    return context.success(
      CenterNode(mergeAdjacentTextNodes(children)),
      result.position,
    );
  }

  @override
  _CenterBody copy() => _CenterBody(inner, after, cache, state);
}
