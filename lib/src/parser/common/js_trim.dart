/// JavaScriptのString.prototype.trimと同じ空白集合で前後を除去する。
///
/// ECMAScriptのWhiteSpaceとLineTerminatorのみが対象。
/// DartのString.trimと異なりU+0085を保持する。
String jsTrim(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && _isJsTrimSpace(value.codeUnitAt(start))) {
    start++;
  }
  while (start < end && _isJsTrimSpace(value.codeUnitAt(end - 1))) {
    end--;
  }
  return value.substring(start, end);
}

bool _isJsTrimSpace(int unit) => switch (unit) {
  >= 0x0009 && <= 0x000d ||
  0x0020 ||
  0x00a0 ||
  0x1680 ||
  >= 0x2000 && <= 0x200a ||
  0x2028 ||
  0x2029 ||
  0x202f ||
  0x205f ||
  0x3000 ||
  0xfeff => true,
  _ => false,
};
