import 'package:petitparser/petitparser.dart';

import '../../ast.dart';
import '../common/utils.dart';
import '../core/nest.dart';
import '../core/scan_cache.dart';
import 'url.dart';

/// リンクパーサー
///
/// mfm-js仕様に準拠したMarkdownリンクを解析
///
/// - `[label](url)` - 通常リンク（silent=false）
/// - `?[label](url)` - サイレントリンク（silent=true）
/// - ラベル内は再帰的にインラインパースを適用
/// - ラベル内ではURL、リンク、メンションは無効（linkLabel状態）
class LinkParser {
  final _cache = FailedScanCache();

  Parser<T> withSearchCache<T>(Parser<T> parser) =>
      _cache.withSearchCache(parser);

  Parser<T> trackLabelText<T>(Parser<T> parser) => _cache.trackText(parser);

  /// リンクパーサーを構築
  ///
  /// [labelInlineParser] はラベル内のインライン構文をパースするパーサー
  /// このパーサーにはURL、リンク、メンションを除外したものを渡す必要がある
  /// [state] ネスト状態（グローバルな深度制限を共有）
  Parser<MfmNode> buildWithInner(
    Parser<MfmNode> labelInlineParser, {
    required NestState state,
  }) {
    return _LinkParserImpl(labelInlineParser, _cache, state: state);
  }

  /// フォールバック付きリンクパーサー
  ///
  /// リンクとして解析できない場合は、開始文字をテキストとして扱う
  /// [state] ネスト状態（グローバルな深度制限を共有）
  Parser<MfmNode> buildWithFallback(
    Parser<MfmNode> labelInlineParser, {
    required NestState state,
  }) {
    final completeLink = buildWithInner(labelInlineParser, state: state);

    // フォールバック: `?[` または `[` で始まるがリンクとして解析できない場合
    final fallback = (string('?[') | char('[')).flatten().map(
      (dynamic s) => TextNode(s as String),
    );

    return (completeLink | fallback).cast<MfmNode>();
  }
}

/// リンクパーサーの実装
class _LinkParserImpl extends Parser<MfmNode> {
  _LinkParserImpl(this._labelInlineParser, this.cache, {required this.state});

  final FailedScanCache cache;

  final Parser<MfmNode> _labelInlineParser;

  /// 共有ネスト状態（グローバルな深度制限を共有）
  final NestState state;

  /// URLパーサー（生URL）を取得
  Parser<MfmNode> get _urlParser => UrlParser().build(state: state);

  /// URLパーサー（ブラケット付き）を取得
  Parser<MfmNode> get _urlAltParser => UrlParser().buildAlt();

  /// mfm.js の `nest(labelInline)` と同様に、ラベルの各要素をネストとして解析する。
  late final Parser<MfmNode> _nestedLabelInlineParser = nest(
    _labelInlineParser,
    state: state,
  );

  @override
  Result<MfmNode> parseOn(Context context) {
    final buffer = context.buffer;
    var position = context.position;

    // サイレントリンクかどうかを判定
    bool silent;
    if (buffer.startsWith('?[', position)) {
      silent = true;
      position += 2;
    } else if (position < buffer.length && buffer[position] == '[') {
      silent = false;
      position += 1;
    } else {
      return context.failure('expected [ or ?[');
    }

    // ラベル部分をパース（] まで）
    final labelNodes = <MfmNode>[];
    var labelContext = Context(buffer, position);
    // silent は開始記号で確定し、ラベル以降の成否には影響しない。
    // ラベル用パーサーはこの実装ごとに固定されている。
    final scan = cache.start(buffer, state, this);

    Result<MfmNode> fail(String message) {
      scan?.fail(message);
      return context.failure(message);
    }

    while (labelContext.position < buffer.length) {
      final c = buffer[labelContext.position];

      // 閉じ括弧で終了
      if (c == ']') {
        break;
      }

      // mfm.js の manyThen と同様、ラベル要素の境界では改行を許可しない。
      // 太字や fn などの要素内部で消費される改行は、その構文の規則に従う。
      if (c == '\n' || c == '\r') {
        return fail('newline in link label');
      }

      final cachedFailure = scan?.replay(labelContext.position);
      if (cachedFailure != null) return fail(cachedFailure);
      scan?.visit(labelContext.position);

      // インラインパーサーでラベル内容をパース
      final result = _nestedLabelInlineParser.parseOn(labelContext);
      scan?.text(labelContext.position, result.position);
      labelNodes.add(result.value);
      labelContext = Context(buffer, result.position);
    }

    position = labelContext.position;

    // `]` で閉じることを確認
    if (position >= buffer.length || buffer[position] != ']') {
      return fail('expected ]');
    }
    position++;

    // `(` が続くことを確認
    if (position >= buffer.length || buffer[position] != '(') {
      return fail('expected (');
    }
    position++;

    // URL部分をパース
    final urlContext = Context(buffer, position);

    // まずブラケット付きURLを試す
    var urlResult = _urlAltParser.parseOn(urlContext);
    if (urlResult is Failure) {
      // 次に生URLを試す
      urlResult = _urlParser.parseOn(urlContext);
    }

    if (urlResult is Failure) {
      return fail('invalid URL in link');
    }

    final urlNode = urlResult.value as UrlNode;
    position = urlResult.position;

    // `)` で閉じることを確認
    if (position >= buffer.length || buffer[position] != ')') {
      return fail('expected )');
    }
    position++;

    // ラベルが空の場合は無効
    if (labelNodes.isEmpty) {
      return context.failure('empty link label');
    }

    // 隣接するTextNodeをマージ
    final mergedLabel = mergeAdjacentTextNodes(labelNodes);

    return context.success(
      LinkNode(silent: silent, url: urlNode.url, children: mergedLabel),
      position,
    );
  }

  @override
  int fastParseOn(String buffer, int position) {
    final result = parseOn(Context(buffer, position));
    return result is Success ? result.position : -1;
  }

  @override
  Parser<MfmNode> copy() =>
      _LinkParserImpl(_labelInlineParser, cache, state: state);
}
