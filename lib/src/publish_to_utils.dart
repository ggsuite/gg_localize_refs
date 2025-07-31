// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Adds 'publish_to: none' to the YAML string if not present.
/// Inserts it after the 'version:' line to maintain a logical order.
String addPublishToNone(String yamlString) {
  if (yamlString
      .contains(RegExp(r'^publish_to:\s*none\s*$', multiLine: true))) {
    return yamlString;
  }

  final versionRegex = RegExp(r'^(version:.*)$', multiLine: true);
  final match = versionRegex.firstMatch(yamlString);
  if (match != null) {
    return yamlString.replaceFirst(
      versionRegex,
      '${match.group(0)}\npublish_to: none',
    );
  }

  // If no version found, add at the end
  return '$yamlString\npublish_to: none\n';
}

/// Removes 'publish_to: none' from the YAML string if present.
String removePublishToNone(String yamlString) {
  return yamlString.replaceAll(
    RegExp(r'^publish_to:\s*none\s*(\n|$)', multiLine: true),
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
  if (original == null || original == 'none') {
    return removePublishToNone(yamlString);
  }

  final versionRegex = RegExp(r'^(publish_to:\s*.*)\n', multiLine: true);
  final match = versionRegex.firstMatch(yamlString);
  if (match != null) {
    return yamlString.replaceFirst(
      '${match.group(1)}',
      'publish_to: $original',
    );
  }

  // If no publish_to found, add it at the end
  return '$yamlString\npublish_to: $original\n';
}
