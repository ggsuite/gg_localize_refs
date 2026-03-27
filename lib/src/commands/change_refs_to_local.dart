// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/manifest_command_support.dart';
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
        description: 'Localize references to local path dependencies',
      );

  final ManifestCommandSupport _support = const ManifestCommandSupport();

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
        node: node,
        pubspec: manifestFile,
        pubspecContent: manifestContent,
        yamlMap: manifestMap,
        fileChangesBuffer: fileChangesBuffer,
        ggLog: ggLog,
      );
      return;
    }

    await _modifyTypeScript(
      node: node,
      manifestFile: manifestFile,
      manifestContent: manifestContent,
      manifestMap: manifestMap as Map<String, dynamic>,
      fileChangesBuffer: fileChangesBuffer,
      ggLog: ggLog,
    );
  }

  Future<void> _modifyDart({
    required ProjectNode node,
    required File pubspec,
    required String pubspecContent,
    required dynamic yamlMap,
    required FileChangesBuffer fileChangesBuffer,
    required GgLog ggLog,
  }) async {
    final projectDir = node.directory;
    _support.ensureDartBackupDir(projectDir);
    _support.ensureGitignoreHasDartBackupEntries(projectDir);
    final references = _support.referencesFor(node, yamlMap);

    if (!_support.hasNonLocalDartDependencies(
      node: node,
      references: references,
    )) {
      return;
    }

    ggLog('Localize refs of ${node.name}');

    await _support.writeFileCopy(
      source: pubspec,
      destination: Utils.dartBackupYamlFile(projectDir),
    );

    final replacedDependencies = _support.buildUpdatedDartBackupDependencies(
      node: node,
      references: references,
      shouldRefreshBackup: _shouldRefreshBackupValue,
    );
    replacedDependencies.addAll(
      backupPublishTo(yamlMap as Map<dynamic, dynamic>),
    );

    var newPubspecContent = pubspecContent;
    for (final dependency in node.dependencies.entries) {
      final dependencyName = dependency.key;
      final reference = references[dependencyName];
      if (reference == null) {
        continue;
      }

      final relativeDepPath = p
          .relative(dependency.value.directory.path, from: node.directory.path)
          .replaceAll('\\', '/');
      final oldDependencyYamlCompressed = yamlToString(
        reference.value,
      ).replaceAll(RegExp(r'[\n\r\t{}]'), '');

      newPubspecContent = node.language.replaceDependencyInContent(
        manifestContent: newPubspecContent,
        reference: reference,
        newValue: 'path: $relativeDepPath # $oldDependencyYamlCompressed',
      );
    }

    newPubspecContent = addPublishToNone(newPubspecContent);

    await _support.saveDependenciesAsJson(
      replacedDependencies,
      Utils.dartBackupFile(projectDir).path,
    );

    fileChangesBuffer.add(pubspec, newPubspecContent);
  }

  Future<void> _modifyTypeScript({
    required ProjectNode node,
    required File manifestFile,
    required String manifestContent,
    required Map<String, dynamic> manifestMap,
    required FileChangesBuffer fileChangesBuffer,
    required GgLog ggLog,
  }) async {
    final references = _support.referencesFor(node, manifestMap);

    if (!_support.hasNonLocalTypeScriptDependencies(
      node: node,
      references: references,
    )) {
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

      final oldValue = reference.value;
      final oldString = oldValue.toString();
      if (!oldString.trim().startsWith('file:')) {
        replacedDependencies[dependency.key] = oldValue;
      }

      final relativePath = p
          .relative(dependency.value.directory.path, from: node.directory.path)
          .replaceAll('\\', '/');

      updatedContent = node.language.replaceDependencyInContent(
        manifestContent: updatedContent,
        reference: reference,
        newValue: 'file:$relativePath',
      );
    }

    if (replacedDependencies.isEmpty) {
      return;
    }

    await _support.writeTypeScriptBackup(node.directory, replacedDependencies);
    fileChangesBuffer.add(manifestFile, updatedContent);
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
}
