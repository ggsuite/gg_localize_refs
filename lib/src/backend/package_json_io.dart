// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// #############################################################################
/// Defensive read-only access to the `package.json` fields the TS publish
/// flow cares about. All accessors silently return `null`/`false` on missing
/// or unparseable input — caller decides the fallback.
class PackageJsonIo {
  PackageJsonIo._(); // coverage:ignore-line

  // ...........................................................................
  /// Returns the `version` field, or `null` when missing/unparseable/empty.
  static String? readVersion(Directory directory) {
    final decoded = _decode(directory);
    if (decoded is! Map) return null;
    final v = decoded['version'];
    if (v is! String || v.isEmpty) return null;
    return v;
  }

  // ...........................................................................
  /// Whether `package.json` is flagged `"private": true`.
  /// Anything else (missing, parse error, non-bool truthy) → `false`.
  static bool isPrivate(Directory directory) {
    final decoded = _decode(directory);
    return decoded is Map && decoded['private'] == true;
  }

  /// Reads and JSON-decodes `<directory>/package.json`, or `null` on failure.
  static dynamic _decode(Directory directory) {
    final pkg = File(p.join(directory.path, 'package.json'));
    if (!pkg.existsSync()) return null;
    try {
      return jsonDecode(pkg.readAsStringSync());
    } catch (_) {
      return null;
    }
  }
}
