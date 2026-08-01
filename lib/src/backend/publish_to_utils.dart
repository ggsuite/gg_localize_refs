// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Returns the newline style used by [yamlString] (CRLF on Windows
/// checkouts with `core.autocrlf`, LF otherwise).
String _newlineOf(String yamlString) =>
    yamlString.contains('\r\n') ? '\r\n' : '\n';

/// Matches a whole `publish_to:` line without its line ending. `[^\r\n]*`
/// instead of `.*` + `\n`, because in Dart regexes `.` matches neither `\n`
/// nor `\r` — a `.*\n` pattern silently fails on CRLF files.
final _publishToLineRegex = RegExp(r'^publish_to:[^\r\n]*', multiLine: true);

/// Removes 'publish_to: none' from the YAML string if present.
String removePublishToNone(String yamlString) {
  return yamlString.replaceAll(
    RegExp(r'^publish_to:\s*none[ \t]*(\r?\n|$)', multiLine: true),
    '',
  );
}

/// Backs up the original 'publish_to' value from the YAML map.
/// Returns a map with the key 'publish_to_original'.
Map<String, dynamic> backupPublishTo(Map<dynamic, dynamic> yamlMap) {
  final original = yamlMap['publish_to']?.toString();
  return {'publish_to_original': original};
}

/// Restores the original 'publish_to' value or removes it if it was 'none'.
/// If backup has 'publish_to_original', replaces the current 'publish_to' value
String restorePublishTo(String yamlString, Map<String, dynamic> backupMap) {
  final original = backupMap['publish_to_original'];
  if (original == null) {
    return removePublishToNone(yamlString);
  }

  if (_publishToLineRegex.hasMatch(yamlString)) {
    return yamlString.replaceFirst(
      _publishToLineRegex,
      'publish_to: $original',
    );
  }

  // If no publish_to found, add it at the end
  final nl = _newlineOf(yamlString);
  return '$yamlString${nl}publish_to: $original$nl';
}
