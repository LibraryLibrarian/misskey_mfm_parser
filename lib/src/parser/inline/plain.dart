import 'package:petitparser/petitparser.dart';

import '../../ast.dart';

/// plain 構文パーサー
///
/// "&lt;plain&gt;…&lt;/plain&gt;" で囲まれた内容を解析
/// 内部はパースせず、TextNodeとしてそのまま扱う（パース無効化が目的）
///
/// mfm-js仕様:
/// - 開始タグ `<plain>` と終了タグ `</plain>` で囲む
/// - 内部の改行は許可される
/// - 内容はTextNodeとして扱われる（MFM構文は解釈されない）
class PlainParser {
  Map<String, _PlainSearchSpan>? _searchSpans;

  /// [parser] の1回の解析中だけ、閉じタグの探索結果を共有する。
  ///
  /// 引用内の再パースなどで使う別バッファは、同一性で区別する。
  /// 最上位のパーサーだけを包み、解析後は入力への参照も破棄する。
  Parser<T> withSearchCache<T>(Parser<T> parser) =>
      _PlainSearchCacheParser<T>(parser, this);

  int _findClose(String buffer, int start) {
    final spans = _searchSpans;
    final span = spans?[buffer];
    if (span != null &&
        start >= span.start &&
        (span.close < 0 || start <= span.close)) {
      return span.close;
    }
    final close = buffer.indexOf('</plain>', start);
    spans?[buffer] = _PlainSearchSpan(start, close);
    return close;
  }

  /// plain タグパーサー
  ///
  /// 内部はパースせず、TextNodeとしてそのまま扱う
  Parser<MfmNode> build() {
    final open = string('<plain>');
    final close = string('</plain>');
    final lineBreak = newline();

    // 内容: </plain>が出現するまでの任意の文字（改行も含む）
    // pick(1)で実際の文字のみ取得し、flatten()で結合
    final content = ((lineBreak.optional() & close).not() & any())
        .pick(1)
        .plus()
        .flatten();

    // seq5で型安全なシーケンスパース
    final parser =
        seq5(
          open,
          lineBreak.optional(),
          content,
          lineBreak.optional(),
          close,
        ).map5((openTag, leadingNewline, text, trailingNewline, closeTag) {
          // PlainNodeは子ノードとしてTextNodeのリストを持つ
          return PlainNode([TextNode(text)]);
        });
    return _PlainCloseGuard(parser, this);
  }
}

class _PlainSearchSpan {
  _PlainSearchSpan(this.start, this.close);
  final int start;
  final int close;
}

class _PlainSearchCacheParser<T> extends DelegateParser<T, T> {
  _PlainSearchCacheParser(super.delegate, this.plain);
  final PlainParser plain;

  @override
  Result<T> parseOn(Context context) {
    final previous = plain._searchSpans;
    plain._searchSpans = Map<String, _PlainSearchSpan>.identity();
    try {
      return delegate.parseOn(context);
    } finally {
      plain._searchSpans = previous;
    }
  }

  @override
  _PlainSearchCacheParser<T> copy() =>
      _PlainSearchCacheParser<T>(delegate, plain);
}

class _PlainCloseGuard extends DelegateParser<MfmNode, MfmNode> {
  _PlainCloseGuard(super.delegate, this.plain);
  final PlainParser plain;

  @override
  Result<MfmNode> parseOn(Context context) {
    final buffer = context.buffer;
    final position = context.position;
    if (buffer.startsWith('<plain>', position) &&
        plain._findClose(buffer, position + '<plain>'.length) < 0) {
      // 未閉じでも入力を消費せず、既存の通常構文へのフォールバックを保つ。
      return context.failure('"</plain>" expected', buffer.length);
    }
    return delegate.parseOn(context);
  }

  @override
  _PlainCloseGuard copy() => _PlainCloseGuard(delegate, plain);
}
