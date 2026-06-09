// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// #############################################################################
/// Small, defensive read-only access to the fields of a `package.json` that
/// the TypeScript publish flow cares about.
///
/// All methods silently return `null` / `false` when the file is missing,
/// unparseable, or carries an unexpected type. Callers that need the
/// distinction between "no file" and "field absent" should inspect the
/// directory themselves.
///
/// Lives here (rather than as static methods on `TypeScriptNpmSpec`) so the
/// spec helper stays I/O-free and easy to unit-test in isolation.
class PackageJsonIo {
  PackageJsonIo._(); // coverage:ignore-line

  // ...........................................................................
  /// Returns the value of the `version` field of `<directory>/package.json`,
  /// or `null` when the file is missing, unparseable, has no `version`, or
  /// the field is not a non-empty string.
  static String? readVersion(Directory directory) {
    final decoded = _decode(directory);
    if (decoded is! Map) return null;
    final v = decoded['version'];
    if (v is! String || v.isEmpty) return null;
    return v;
  }

  // ...........................................................................
  /// Returns `true` when `<directory>/package.json` is flagged
  /// `"private": true`. All non-true / missing / error states return `false`
  /// — the caller can fall back to the public-registry path.
  static bool isPrivate(Directory directory) {
    final decoded = _decode(directory);
    return decoded is Map && decoded['private'] == true;
  }

  // ...........................................................................
  /// Reads and JSON-decodes `<directory>/package.json`, or returns `null`
  /// when the file is missing or fails to parse.
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
