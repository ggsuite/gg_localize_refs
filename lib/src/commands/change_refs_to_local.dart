// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/backend/publish_to_utils.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;

/// Command for localizing references to local path dependencies.
class ChangeRefsToLocal extends DirCommand<dynamic> {
  /// Constructor.
  ChangeRefsToLocal({required super.ggLog})
    : super(
        name: 'change-refs-to-local',
        description: 'Changes dependencies to local dependencies.',
      );

  /// Ensures the backup directory (.gg) exists under [projectDir].
  Directory _ensureBackupDir(Directory projectDir) {
    final backupDir = Utils.dartBackupDir(projectDir);
    final didExist = backupDir.existsSync();
    if (!didExist) {
      backupDir.createSync(recursive: true);
    }
    return backupDir;
  }

  /// Ensures that `.gitignore` contains entries for `.gg` and `!.gg/.gg.json`.
  void _ensureGitignoreHasGgEntries(Directory projectDir) {
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

  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    ggLog('Running change-refs-to-local in ${directory.path}');
    final fileChangesBuffer = FileChangesBuffer();

    try {
      await processProject(
        directory: directory,
        modifyFunction: modifyManifest,
        fileChangesBuffer: fileChangesBuffer,
        ggLog: ggLog,
      );

      if (fileChangesBuffer.files.isEmpty) {
        ggLog.call(yellow('No files were changed.'));
        return;
      }

      await fileChangesBuffer.apply();
    } catch (e) {
      throw Exception(yellow('An error occurred: $e. No files were changed.'));
    }
  }

  /// Modify the manifest file of a project node.
  Future<void> modifyManifest(
    ProjectNode node,
    File manifestFile,
    String manifestContent,
    dynamic manifestMap,
    FileChangesBuffer fileChangesBuffer,
    GgLog ggLog,
  ) async {
    if (node.language.id == ProjectLanguageId.dart) {
      await _modifyDart(
        node,
        manifestFile,
        manifestContent,
        manifestMap,
        fileChangesBuffer,
        ggLog,
      );
      return;
    }

    await _modifyTypeScript(
      node,
      manifestFile,
      manifestContent,
      manifestMap as Map<String, dynamic>,
      fileChangesBuffer,
      ggLog,
    );
  }

  Future<void> _modifyDart(
    ProjectNode node,
    File pubspec,
    String pubspecContent,
    dynamic yamlMap,
    FileChangesBuffer fileChangesBuffer,
    GgLog ggLog,
  ) async {
    final projectDir = node.directory;
    _ensureBackupDir(projectDir);
    _ensureGitignoreHasGgEntries(projectDir);
    final references = node.language.listDependencyReferences(yamlMap);

    var hasOnlineDependencies = false;

    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }
      if (!yamlToString(reference.value).startsWith('path:')) {
        hasOnlineDependencies = true;
      }
    }

    if (!hasOnlineDependencies) {
      return;
    }

    ggLog('Localize refs of ${node.name}');

    final originalPubspec = Utils.dartBackupYamlFile(projectDir);
    await _writeFileCopy(source: pubspec, destination: originalPubspec);

    var newPubspecContent = pubspecContent;

    final replacedDependencies = await _buildUpdatedDartBackupDependencies(
      node: node,
      references: references,
    );

    for (final dependency in node.dependencies.entries) {
      final dependencyName = dependency.key;
      final dependencyPath = dependency.value.directory.path;
      final relativeDepPath = p
          .relative(dependencyPath, from: node.directory.path)
          .replaceAll('\\', '/');
      final reference = references[dependencyName];
      if (reference == null) {
        continue;
      }

      final oldDependencyYaml = yamlToString(reference.value);
      final oldDependencyYamlCompressed = oldDependencyYaml.replaceAll(
        RegExp(r'[\n\r\t{}]'),
        '',
      );

      newPubspecContent = node.language.replaceDependencyInContent(
        manifestContent: newPubspecContent,
        reference: reference,
        newValue: 'path: $relativeDepPath # $oldDependencyYamlCompressed',
      );
    }

    final publishBackup = backupPublishTo(yamlMap as Map<dynamic, dynamic>);
    replacedDependencies.addAll(publishBackup);

    newPubspecContent = addPublishToNone(newPubspecContent);

    await saveDependenciesAsJson(
      replacedDependencies,
      Utils.dartBackupFile(projectDir).path,
    );

    fileChangesBuffer.add(pubspec, newPubspecContent);
  }

  Future<void> _modifyTypeScript(
    ProjectNode node,
    File manifestFile,
    String manifestContent,
    Map<String, dynamic> manifestMap,
    FileChangesBuffer fileChangesBuffer,
    GgLog ggLog,
  ) async {
    final references = node.language.listDependencyReferences(manifestMap);

    var hasOnlineDependencies = false;

    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (value == null) {
        continue;
      }
      if (!value.trim().startsWith('file:')) {
        hasOnlineDependencies = true;
      }
    }

    if (!hasOnlineDependencies) {
      return;
    }

    ggLog('Localize refs of ${node.name}');

    final replacedDependencies = <String, dynamic>{};
    var updatedContent = manifestContent;

    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }

      final depDir = dependency.value.directory.path;
      final relativePath = p
          .relative(depDir, from: node.directory.path)
          .replaceAll('\\', '/');

      final oldValue = reference.value;
      final oldString = oldValue.toString();
      if (!oldString.trim().startsWith('file:')) {
        replacedDependencies[dependency.key] = oldValue;
      }

      updatedContent = node.language.replaceDependencyInContent(
        manifestContent: updatedContent,
        reference: reference,
        newValue: 'file:$relativePath',
      );
    }

    if (replacedDependencies.isEmpty) {
      return;
    }

    await _writeTypeScriptBackup(node.directory, replacedDependencies);

    fileChangesBuffer.add(manifestFile, updatedContent);
  }

  /// Builds the Dart backup map while preserving existing version entries.
  Future<Map<String, dynamic>> _buildUpdatedDartBackupDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) async {
    final backupFile = Utils.dartBackupFile(node.directory);
    final existingBackup = backupFile.existsSync()
        ? Utils.readDependenciesFromJson(backupFile.path)
        : <String, dynamic>{};

    final updatedBackup = <String, dynamic>{};

    for (final entry in existingBackup.entries) {
      if (entry.key == 'publish_to_original') {
        continue;
      }

      final normalizedValue = _normalizeBackupVersionValue(entry.value);
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
      if (!_shouldRefreshBackupValue(dependencyYaml)) {
        continue;
      }

      final normalizedValue = _normalizeBackupVersionValue(reference.value);
      if (normalizedValue != null) {
        updatedBackup[dependency.key] = normalizedValue;
      }
    }

    return updatedBackup;
  }

  Future<void> _writeTypeScriptBackup(
    Directory projectDirectory,
    Map<String, dynamic> replacedDependencies,
  ) async {
    final backupFile = Utils.typeScriptBackupFile(projectDirectory);
    await backupFile.writeAsString(jsonEncode(replacedDependencies));
  }

  /// Returns the normalized backup version or null when it cannot be used.
  dynamic _normalizeBackupVersionValue(dynamic dependency) {
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

  /// Returns true when a dependency should refresh its backup version.
  bool _shouldRefreshBackupValue(String dependencyYaml) {
    final trimmed = dependencyYaml.trimLeft();
    if (trimmed.startsWith('path:')) {
      return false;
    }

    if (!trimmed.startsWith('git:')) {
      return true;
    }

    return trimmed.contains('tag_pattern:');
  }

  /// Helper method to copy a file.
  Future<void> _writeFileCopy({
    required File source,
    required File destination,
  }) async {
    await source.copy(destination.path);
  }

  /// Save the dependencies to a JSON file.
  Future<void> saveDependenciesAsJson(
    Map<String, dynamic> replacedDependencies,
    String filePath,
  ) async {
    final jsonString = jsonEncode(replacedDependencies);
    final file = File(filePath);
    await file.writeAsString(jsonString);
  }
}
