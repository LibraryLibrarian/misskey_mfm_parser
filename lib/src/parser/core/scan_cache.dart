import 'package:petitparser/petitparser.dart';

import 'nest.dart';

/// 失敗した反復の接尾辞を、入力・深さ・予算切れの有無ごとに記録する。
///
/// 予算消費も再生するため、キャッシュの有無で後続構文の解釈を変えない。
/// 予算が途中で尽きた結果は、同じ残予算の場合だけ再利用できる。
class FailedScanCache {
  Map<String, Map<(Object, int, int?), _FailuresByBudget>>? _buffers;
  (String, int, int)? _textSpan;

  Parser<T> withSearchCache<T>(Parser<T> parser) => _ScanScope(parser, this);

  /// 通常テキストの内部から開始しても、同じ1要素になる区間を追跡する。
  /// [parser] は状態や直前文字に依存しない通常テキストに限る。
  Parser<T> trackText<T>(Parser<T> parser) => _TrackText(parser, this);

  FailedScan? start(String buffer, NestState? state, Object parser) {
    final buffers = _buffers;
    final budget = state?.budget;
    if (buffers == null || state == null || budget == null) return null;
    final states = buffers.putIfAbsent(buffer, () => {});
    final failures = states.putIfAbsent(
      (parser, state.depth, state.limit),
      _FailuresByBudget.new,
    );
    return FailedScan._(this, buffer, state, failures);
  }
}

class FailedScan {
  FailedScan._(this.cache, this.buffer, this.state, this._failures);
  final FailedScanCache cache;
  final String buffer;
  final NestState state;
  final _FailuresByBudget _failures;
  final _visits = <({int start, int end, int budget})>[];

  /// 接尾辞の失敗が確定済みなら、走査を省略して同じ予算を消費する。
  String? replay(int position) {
    final remaining = state.budget!;
    final failure = (remaining == 0
        ? _failures.zero
        : _failures.positive)[position];
    if (failure == null ||
        (failure.exhausted
            ? remaining != failure.cost
            : remaining <= failure.cost)) {
      return null;
    }
    state.budget = remaining - failure.cost;
    return failure.message;
  }

  void visit(int position) {
    _visits.add((start: position, end: position + 1, budget: state.budget!));
  }

  void text(int start, int end) {
    final span = cache._textSpan;
    if (_visits.isEmpty ||
        span == null ||
        !identical(span.$1, buffer) ||
        span.$2 != start ||
        span.$3 != end) {
      return;
    }
    final visit = _visits.last;
    // nest が通常テキストを1要素として解析した場合だけ、内部位置も登録。
    if (visit.budget - state.budget! == 1) {
      _visits[_visits.length - 1] = (
        start: visit.start,
        end: end,
        budget: visit.budget,
      );
    }
  }

  void fail(String message) {
    final remaining = state.budget!;
    for (final visit in _visits) {
      final failures = visit.budget == 0 ? _failures.zero : _failures.positive;
      final failure = _ScanFailure(
        visit.budget - remaining,
        message,
        exhausted: remaining == 0,
      );
      for (var position = visit.start; position < visit.end; position++) {
        // link の改行チェックはテキスト走査より先に行われる。
        if (position != visit.start &&
            (buffer[position] == '\n' || buffer[position] == '\r')) {
          continue;
        }
        failures[position] = failure;
      }
    }
  }
}

class _FailuresByBudget {
  final positive = <int, _ScanFailure>{};
  final zero = <int, _ScanFailure>{};
}

class _ScanFailure {
  _ScanFailure(this.cost, this.message, {required this.exhausted});
  final int cost;
  final bool exhausted;
  final String message;
}

class _ScanScope<T> extends DelegateParser<T, T> {
  _ScanScope(super.delegate, this.cache);
  final FailedScanCache cache;

  @override
  Result<T> parseOn(Context context) {
    final previous = cache._buffers;
    final previousText = cache._textSpan;
    cache._buffers = Map.identity();
    cache._textSpan = null;
    try {
      return delegate.parseOn(context);
    } finally {
      cache._buffers = previous;
      cache._textSpan = previousText;
    }
  }

  @override
  _ScanScope<T> copy() => _ScanScope(delegate, cache);
}

class _TrackText<T> extends DelegateParser<T, T> {
  _TrackText(super.delegate, this.cache);
  final FailedScanCache cache;

  @override
  Result<T> parseOn(Context context) {
    final result = delegate.parseOn(context);
    if (result is Success && cache._buffers != null) {
      cache._textSpan = (context.buffer, context.position, result.position);
    }
    return result;
  }

  @override
  _TrackText<T> copy() => _TrackText(delegate, cache);
}
