import 'package:petitparser/petitparser.dart';

import '../../ast.dart';
import 'generated/unicode_emoji_regex.dart';

/// Unicode絵文字パーサー
///
/// mfm.jsの`unicodeEmoji`と同じ正規表現で絵文字を認識する。
/// 肌色修飾子、ZWJ結合絵文字、国旗のほか、単独のregional indicatorも
/// 1つの絵文字として扱う。
///
/// 正規表現はmfm.jsが使う`@misskey-dev/emoji-data`（Unicode 17.0）から生成。
class UnicodeEmojiParser {
  /// mfm.jsと同じ絵文字の正規表現。
  ///
  /// 出典と再生成手順は生成ファイルのヘッダーを参照。パターンはUTF-16の
  /// サロゲートエスケープで書かれているため、`unicode`は有効にしない。
  ///
  /// 先頭の`(?!\uFE0F)`は、mfm.jsが単独のVS16を絵文字ではなくテキストとして
  /// 扱うことに合わせるためのもの。VS16で始まるパターンは単独のVS16だけで、
  /// 他の選択肢には影響しない。
  static final RegExp _emojiRegex = RegExp(
    '(?!\\uFE0F)(?:$unicodeEmojiRegexPattern)',
  );

  /// Unicode絵文字パーサーを構築
  Parser<MfmNode> build() {
    // PatternParserを使用して正規表現でマッチ
    // PatternParserはMatchオブジェクトを返すため、group(0)で文字列を取得
    return PatternParser(_emojiRegex, 'unicode emoji').map<MfmNode>(
      (dynamic v) => UnicodeEmojiNode((v as Match).group(0)!),
    );
  }
}
