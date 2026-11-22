import 'package:petitparser/petitparser.dart';

import '../../ast.dart';

/// インライン数式パーサー
///
/// LaTeX形式のインライン数式を解析する。
///
/// mfm-js仕様:
/// - 形式: `\(formula\)`
/// - 改行を含めることはできない
/// - 空の数式は無効
class MathInlineParser {
  Map<String, (int, int)>? _spans;
  static final _terminator = RegExp(r'\\\)|[\r\n]');

  Parser<T> withSearchCache<T>(Parser<T> parser) => _MathScope(parser, this);

  int _findEnd(String buffer, int start) {
    final span = _spans?[buffer];
    if (span != null && span.$1 <= start && start <= span.$2) return span.$2;
    final matches = _terminator.allMatches(buffer, start).iterator;
    final end = matches.moveNext() ? matches.current.start : buffer.length;
    _spans?[buffer] = (start, end);
    return end;
  }

  /// インライン数式パーサー
  Parser<MfmNode> build() {
    final open = string(r'\(');
    final close = string(r'\)');
    final lineBreak = newline();

    // 数式内容: \) または改行以外の文字
    // mfm-js:
    // P.seq(
    //  P.notMatch(P.alt([close, newLine])),
    //  P.char).select(1).many(1)
    final formulaChar = (close.not() & lineBreak.not() & any()).pick(2);
    final formula = formulaChar.plus().flatten();

    // seq3で型安全なシーケンスパース
    final parser = seq3(open, formula, close).map3((
      openTag,
      formulaStr,
      closeTag,
    ) {
      return MathInlineNode(formulaStr);
    });
    return _MathCloseGuard(parser, this);
  }
}

class _MathCloseGuard extends DelegateParser<MfmNode, MfmNode> {
  _MathCloseGuard(super.delegate, this.math);
  final MathInlineParser math;

  @override
  Result<MfmNode> parseOn(Context context) {
    final buffer = context.buffer;
    final position = context.position;
    if (buffer.startsWith(r'\(', position)) {
      final end = math._findEnd(buffer, position + 2);
      if (!buffer.startsWith(r'\)', end)) {
        return context.failure('"\\)" expected', end);
      }
    }
    return delegate.parseOn(context);
  }

  @override
  _MathCloseGuard copy() => _MathCloseGuard(delegate, math);
}

class _MathScope<T> extends DelegateParser<T, T> {
  _MathScope(super.delegate, this.math);
  final MathInlineParser math;

  @override
  Result<T> parseOn(Context context) {
    final previous = math._spans;
    math._spans = Map.identity();
    try {
      return delegate.parseOn(context);
    } finally {
      math._spans = previous;
    }
  }

  @override
  _MathScope<T> copy() => _MathScope(delegate, math);
}
