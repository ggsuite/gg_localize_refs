// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
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
  static File typeScriptBackupFile(Directory directory) {
    return File(p.join(directory.path, '.gg_localize_refs_backup.json'));
  }

  /// Returns the Dart backup directory used by this package.
  static Directory dartBackupDir(Directory directory) {
    return Directory(p.join(directory.path, '.gg'));
  }

  /// Returns the Dart backup file used by this package.
  static File dartBackupFile(Directory directory) {
    return File(
      p.join(dartBackupDir(directory).path, '.gg_localize_refs_backup.json'),
    );
  }

  /// Returns the Dart backup copy of pubspec.yaml.
  static File dartBackupYamlFile(Directory directory) {
    return File(
      p.join(dartBackupDir(directory).path, '.gg_localize_refs_backup.yaml'),
    );
  }

  /// Returns the backup file that stores the original `publish_to` value.
  static File dartPublishToBackupFile(Directory directory) {
    return File(
      p.join(
        dartBackupDir(directory).path,
        '.gg_localize_refs_publish_to_backup.json',
      ),
    );
  }

  /// Reads the origin URL from git for [dependencyName].
  static Future<String> getGitRemoteUrl(
    Directory directory,
    String dependencyName,
  ) async {
    final result = await Process.run('git', <String>[
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
