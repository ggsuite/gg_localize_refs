// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:path/path.dart' as p;

/// Shared helpers for manifest based ref-changing commands.
class ManifestCommandSupport {
  /// Creates support helpers for manifest commands.
  const ManifestCommandSupport();

  /// Ensures the Dart backup directory exists.
  Directory ensureDartBackupDir(Directory projectDir) {
    final backupDir = Utils.dartBackupDir(projectDir);
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }
    return backupDir;
  }

  /// Ensures `.gitignore` contains the required `.gg` entries.
  void ensureGitignoreHasDartBackupEntries(Directory projectDir) {
    final gitignore = File(p.join(projectDir.path, '.gitignore'));
    const ignoreDir = '.gg';
    const keepConfig = '!.gg/.gg.json';

    if (!gitignore.existsSync()) {
      gitignore.writeAsStringSync('$ignoreDir\n$keepConfig\n');
      return;
    }

    final raw = gitignore.readAsStringSync();
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final content = normalized.endsWith('\n')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final lines = content.isEmpty ? <String>[] : content.split('\n');

    final hasIgnoreDir = lines.any((line) => line.trim() == ignoreDir);
    final hasKeepConfig = lines.any((line) => line.trim() == keepConfig);

    if (!hasIgnoreDir) {
      lines.add(ignoreDir);
    }
    if (!hasKeepConfig) {
      lines.add(keepConfig);
    }

    gitignore.writeAsStringSync('${lines.join('\n')}\n');
  }

  /// Copies [source] to [destination].
  Future<void> writeFileCopy({
    required File source,
    required File destination,
  }) async {
    await source.copy(destination.path);
  }

  /// Saves [replacedDependencies] as JSON at [filePath].
  Future<void> saveDependenciesAsJson(
    Map<String, dynamic> replacedDependencies,
    String filePath,
  ) async {
    final jsonString = jsonEncode(replacedDependencies);
    final file = File(filePath);
    await file.writeAsString(jsonString);
  }

  /// Writes the TypeScript backup file for [projectDirectory].
  Future<void> writeTypeScriptBackup(
    Directory projectDirectory,
    Map<String, dynamic> replacedDependencies,
  ) async {
    final backupFile = Utils.typeScriptBackupFile(projectDirectory);
    await backupFile.writeAsString(jsonEncode(replacedDependencies));
  }

  /// Returns dependency references from [manifestMap].
  Map<String, DependencyReference> referencesFor(
    ProjectNode node,
    dynamic manifestMap,
  ) {
    return node.language.listDependencyReferences(manifestMap);
  }

  /// Returns true when any workspace Dart dependency is not yet localized.
  bool hasNonLocalDartDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) {
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }
      if (!yamlToString(reference.value).startsWith('path:')) {
        return true;
      }
    }
    return false;
  }

  /// Returns true when any workspace TS dependency is not yet localized.
  bool hasNonLocalTypeScriptDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) {
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (value == null) {
        continue;
      }
      if (!value.trim().startsWith('file:')) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether publish_to should be backed up for this manifest.
  bool shouldBackupPublishTo({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) {
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }

      final dependencyYaml = yamlToString(reference.value).trimLeft();
      final isPubDevVersion =
          !dependencyYaml.startsWith('path:') &&
          !dependencyYaml.startsWith('git:');
      final isGitWithVersion =
          dependencyYaml.startsWith('git:') &&
          dependencyYaml.contains('version:');

      if (!isPubDevVersion && !isGitWithVersion) {
        return false;
      }
    }

    return true;
  }

  /// Returns backup entries normalized to plain version strings where possible.
  Map<String, dynamic> buildUpdatedDartBackupDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
    required bool Function(String dependencyYaml) shouldRefreshBackup,
  }) {
    final backupFile = Utils.dartBackupFile(node.directory);
    final existingBackup = backupFile.existsSync()
        ? Utils.readDependenciesFromJson(backupFile.path)
        : <String, dynamic>{};

    final updatedBackup = <String, dynamic>{};

    for (final entry in existingBackup.entries) {
      if (entry.key == 'publish_to_original') {
        continue;
      }

      final normalizedValue = normalizeBackupVersionValue(entry.value);
      if (normalizedValue != null) {
        updatedBackup[entry.key] = normalizedValue;
      }
    }

    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }

      final dependencyYaml = yamlToString(reference.value);
      if (!shouldRefreshBackup(dependencyYaml)) {
        continue;
      }

      final normalizedValue = normalizeBackupVersionValue(reference.value);
      if (normalizedValue != null) {
        updatedBackup[dependency.key] = normalizedValue;
      }
    }

    return updatedBackup;
  }

  /// Returns the normalized backup version or null when it cannot be used.
  dynamic normalizeBackupVersionValue(dynamic dependency) {
    if (dependency is String) {
      final trimmed = dependency.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      if (trimmed.startsWith('path:') || trimmed.startsWith('git:')) {
        return null;
      }
      return trimmed;
    }

    if (dependency is Map) {
      final version = dependency['version'];
      if (version != null) {
        final trimmed = version.toString().trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }

      final git = dependency['git'];
      if (git is Map) {
        final gitVersion = git['version'];
        if (gitVersion != null) {
          final trimmed = gitVersion.toString().trim();
          if (trimmed.isNotEmpty) {
            return trimmed;
          }
        }
      }
    }

    return null;
  }
}
