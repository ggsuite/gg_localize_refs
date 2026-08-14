// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart' as p;

/// Resolves the project language and common manifest related file paths.
class Utils {
  /// Returns the language implementation for the manifest in [directory].
  static ProjectLanguage findLanguage(Directory directory) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    final packageJson = File(p.join(directory.path, 'package.json'));

    if (pubspec.existsSync()) {
      return DartProjectLanguage();
    }
    if (packageJson.existsSync()) {
      return TypeScriptProjectLanguage();
    }

    throw Exception('pubspec.yaml not found at ${pubspec.path}');
  }

  /// Returns the TypeScript backup file used by this package.
  ///
  /// It lives beside the Dart backup in `.gg`, under its own `_ts` name so
  /// the two never collide in a cross-language bridge. Older checkouts wrote
  /// it hidden into the project root; that file is moved on first access.
  static File typeScriptBackupFile(Directory directory) => _inBackupDir(
    directory,
    'gg_localize_refs_backup_ts.json',
    legacyPaths: const <String>['.gg_localize_refs_backup.json'],
  );

  /// Returns the backup directory used by this package.
  static Directory dartBackupDir(Directory directory) {
    return Directory(p.join(directory.path, '.gg'));
  }

  /// Returns the Dart backup file used by this package.
  static File dartBackupFile(Directory directory) => _inBackupDir(
    directory,
    'gg_localize_refs_backup_dart.json',
    legacyPaths: const <String>[
      '.gg/gg_localize_refs_backup.json',
      '.gg/.gg_localize_refs_backup.json',
    ],
  );

  /// Returns the backup file that stores the original `publish_to` value.
  static File dartPublishToBackupFile(Directory directory) {
    return _inBackupDir(directory, 'gg_localize_refs_publish_to_backup.json');
  }

  /// Returns `<directory>/.gg/<name>`, migrating a file an earlier version
  /// wrote under one of [legacyPaths] (repo-relative) to that location.
  ///
  /// Two renames happened over time: the files inside `.gg` are no longer
  /// hidden, and the dependency backups carry a `_dart`/`_ts` suffix so the
  /// two languages cannot overwrite each other. Migrating on first access
  /// keeps an older checkout's backups readable instead of silently falling
  /// back to "no backup found". [legacyPaths] defaults to the dot-prefixed
  /// name inside `.gg`.
  static File _inBackupDir(
    Directory directory,
    String name, {
    List<String>? legacyPaths,
  }) {
    final backupDir = dartBackupDir(directory);
    final file = File(p.join(backupDir.path, name));
    if (file.existsSync()) {
      return file;
    }

    final candidates = legacyPaths ?? <String>['.gg/.$name'];
    for (final candidate in candidates) {
      final legacy = File(
        p.join(directory.path, p.joinAll(candidate.split('/'))),
      );
      if (legacy.existsSync()) {
        backupDir.createSync(recursive: true);
        legacy.renameSync(file.path);
        break;
      }
    }

    return file;
  }

  /// Reads the origin URL from git for [dependencyName].
  static Future<String> getGitRemoteUrl(
    Directory directory,
    String dependencyName,
  ) async {
    final result = await ggRunProcess('git', <String>[
      'remote',
      'get-url',
      'origin',
    ], workingDirectory: directory.path);

    if (result.exitCode != 0) {
      throw Exception(
        'Cannot get git remote url for dependency '
        '$dependencyName in ${directory.path}',
      );
    }

    return result.stdout.toString().trim();
  }

  /// Reads a dependency backup JSON from [filePath].
  static Map<String, dynamic> readDependenciesFromJson(String filePath) {
    final file = File(filePath);

    if (!file.existsSync()) {
      throw Exception(
        'The json file $filePath with old dependencies does not exist.',
      );
    }

    final jsonString = file.readAsStringSync();
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }
}
