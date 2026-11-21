import 'dart:convert';
import 'dart:io';

/// Regenerates the Unicode emoji regular expression used by the parser.
///
/// The expression is the one mfm.js uses (`emojiRegex` exported by
/// `@misskey-dev/emoji-data`), so that emoji are classified the same way as
/// in Misskey.
///
/// Run this command from the repository root:
///
/// ```sh
/// dart run tool/update_unicode_emoji_regex.dart
/// ```
///
/// To follow a new mfm.js release, update the version, size, and blob below to
/// match the `@misskey-dev/emoji-data` version it depends on, then review both
/// the generated diff and the Unicode emoji regression tests.
const unicodeVersion = '17.0';
const sourcePackage = '@misskey-dev/emoji-data';
const sourceVersion = '17.0.3';
const sourceBlob = '2e07057041456ca7eac351b6985dbad80d992c25';
const expectedSourceBytes = 17142;
const outputPath = 'lib/src/parser/inline/generated/unicode_emoji_regex.dart';

final Uri sourceUri = Uri.parse(
  'https://cdn.jsdelivr.net/npm/$sourcePackage@$sourceVersion/built/regex.mjs',
);

/// Verifies both the size and Git blob SHA-1 of the pinned source bytes.
Future<void> validateSourceBytes(List<int> bytes) async {
  if (bytes.length != expectedSourceBytes) {
    throw FormatException(
      'Unexpected source size: ${bytes.length} bytes '
      '(expected $expectedSourceBytes for blob $sourceBlob).',
    );
  }

  final process = await Process.start('git', ['hash-object', '--stdin']);
  final output = process.stdout.transform(utf8.decoder).join();
  final errorOutput = process.stderr.transform(utf8.decoder).join();
  process.stdin.add(bytes);
  await process.stdin.close();

  final status = await process.exitCode;
  final actualBlob = (await output).trim();
  final error = (await errorOutput).trim();
  if (status != 0) {
    throw ProcessException(
      'git',
      const ['hash-object', '--stdin'],
      error,
      status,
    );
  }
  if (actualBlob != sourceBlob) {
    throw FormatException(
      'Unexpected source Git blob SHA-1: $actualBlob '
      '(expected $sourceBlob).',
    );
  }
}

/// Extracts the regular expression body from `regex.mjs`.
///
/// The source is `const emojiRegex = /<pattern>/g;`. The pattern uses UTF-16
/// surrogate escapes, so it must be compiled without the `unicode` flag.
String extractPattern(String source) {
  const prefix = 'const emojiRegex = /';
  const suffix = '/g;';
  final start = source.indexOf(prefix);
  final end = start < 0 ? -1 : source.indexOf(suffix, start + prefix.length);
  if (start < 0 || end < 0) {
    throw const FormatException('Could not locate emojiRegex in the source.');
  }
  final pattern = source.substring(start + prefix.length, end);
  if (pattern.isEmpty || pattern.contains('\n') || pattern.contains("'")) {
    throw const FormatException(
      'Downloaded source is not the expected one-line pattern.',
    );
  }
  return pattern;
}

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this tool from the repository root.');
    exitCode = 64;
    return;
  }

  final client = HttpClient();
  try {
    final request = await client.getUrl(sourceUri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'misskey_mfm_parser emoji regex updater',
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      stderr.writeln(
        'Failed to download $sourceUri: HTTP ${response.statusCode}',
      );
      exitCode = 1;
      return;
    }

    final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
      all.addAll(chunk);
      return all;
    });
    final String pattern;
    try {
      await validateSourceBytes(bytes);
      pattern = extractPattern(utf8.decode(bytes));
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      exitCode = 1;
      return;
    }

    final output =
        '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
//
// Unicode Emoji version: $unicodeVersion
// Source: $sourcePackage@$sourceVersion (built/regex.mjs, the emojiRegex used by mfm.js)
// Source blob: $sourceBlob
// License: MIT (see third_party/misskey-emoji-data/)
// Regenerate: dart run tool/update_unicode_emoji_regex.dart

/// The emoji regular expression used by mfm.js (Unicode $unicodeVersion).
///
/// The pattern uses UTF-16 surrogate escapes, so compile it without the
/// `unicode` flag.
const unicodeEmojiRegexPattern =
    r'$pattern';
''';

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(output);
    stdout.writeln('Updated $outputPath from $sourceUri');
  } finally {
    client.close(force: true);
  }
}
