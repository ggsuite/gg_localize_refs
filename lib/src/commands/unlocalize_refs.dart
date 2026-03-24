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
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/backend/publish_to_utils.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:path/path.dart' as p;

// #############################################################################
/// Command that reverts localized references back to remote dependencies.
class UnlocalizeRefs extends DirCommand<dynamic> {
  /// Creates the command.
  UnlocalizeRefs({required super.ggLog})
    : isOnPubDev = IsOnPubDev(ggLog: ggLog),
      super(
        name: 'unlocalize-refs',
        description: 'Changes dependencies to remote dependencies.',
      );

  /// Service used to check whether a dependency was published before.
  final IsOnPubDev isOnPubDev;

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    ggLog('Running unlocalize-refs in ${directory.path}');

    final fileChangesBuffer = FileChangesBuffer();

    //try {
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
    //} catch (e) {
    //  throw Exception(red('An error occurred: $e. No files were changed.'));
    //}
  }

  // ...........................................................................
  /// Modify the manifest file.
  Future<void> modifyManifest(
    ProjectNode node,
    File manifestFile,
    String manifestContent,
    dynamic manifestMap,
    FileChangesBuffer fileChangesBuffer,
    GgLog ggLog,
  ) async {
    if (node.language.id == ProjectLanguageId.dart) {
      await _unlocalizeDart(
        node,
        manifestFile,
        manifestContent,
        manifestMap,
        fileChangesBuffer,
        ggLog,
      );
      return;
    }

    await _unlocalizeTypeScript(
      node,
      manifestFile,
      manifestContent,
      manifestMap,
      fileChangesBuffer,
      ggLog,
    );
  }

  Future<void> _unlocalizeDart(
    ProjectNode node,
    File pubspec,
    String pubspecContent,
    dynamic yamlMap,
    FileChangesBuffer fileChangesBuffer,
    GgLog ggLog,
  ) async {
    final references = node.language.listDependencyReferences(yamlMap);

    if (!_hasLocalizedDependencies(node: node, references: references)) {
      return;
    }

    ggLog('Unlocalize refs of ${node.name}');

    final backupFile = Utils.dartBackupFile(node.directory);

    if (!backupFile.existsSync()) {
      ggLog(
        yellow(
          'The automatic change of dependencies could not be performed. '
          'Please change the '
          '${red(p.join(node.directory.path, 'pubspec.yaml'))} '
          'file manually.',
        ),
      );
      return;
    }

    final savedDependencies = Utils.readDependenciesFromJson(backupFile.path);

    var newPubspecContent = pubspecContent;

    for (final dependency in node.dependencies.entries) {
      final dependencyName = dependency.key;
      final reference = references[dependencyName];
      if (reference == null) {
        continue;
      }

      final oldDependencyYaml = yamlToString(reference.value);

      if (!savedDependencies.containsKey(dependencyName)) {
        continue;
      }

      if (!_isLocalizedDartDependency(oldDependencyYaml)) {
        continue;
      }

      final newDependencyYaml = await _buildDartRemoteDependencyYaml(
        dependencyNode: dependency.value,
        savedDependencies: savedDependencies,
      );

      newPubspecContent = node.language.replaceDependencyInContent(
        manifestContent: newPubspecContent,
        reference: reference,
        newValue: newDependencyYaml,
      );
    }

    newPubspecContent = restorePublishTo(newPubspecContent, savedDependencies);

    fileChangesBuffer.add(pubspec, newPubspecContent);
  }

  Future<void> _unlocalizeTypeScript(
    ProjectNode node,
    File manifestFile,
    String manifestContent,
    dynamic manifestMap,
    FileChangesBuffer fileChangesBuffer,
    GgLog ggLog,
  ) async {
    final references = node.language.listDependencyReferences(manifestMap);

    if (!_hasLocalizedDependencies(node: node, references: references)) {
      return;
    }

    ggLog('Unlocalize refs of ${node.name}');

    final backupFile = Utils.typeScriptBackupFile(node.directory);

    if (!backupFile.existsSync()) {
      ggLog(
        yellow(
          'The automatic change of dependencies could not be performed. '
          'Please change the '
          '${red(p.join(node.directory.path, 'package.json'))} '
          'file manually.',
        ),
      );
      return;
    }

    final savedDependencies = Utils.readDependenciesFromJson(backupFile.path);
    var newContent = manifestContent;

    for (final dependency in node.dependencies.entries) {
      final name = dependency.key;
      final saved = savedDependencies[name];
      final reference = references[name];
      if (saved == null || reference == null) {
        continue;
      }

      final current = reference.value?.toString() ?? '';
      if (_isLocalizedTypeScriptDependency(current)) {
        newContent = node.language.replaceDependencyInContent(
          manifestContent: newContent,
          reference: reference,
          newValue: await _buildTypeScriptRemoteDependency(
            dependencyNode: dependency.value,
            savedDependency: saved,
          ),
        );
      }
    }

    fileChangesBuffer.add(manifestFile, newContent);
  }

  /// Returns true when any workspace dependency is still localized.
  bool _hasLocalizedDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) {
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }

      if (node.language.id == ProjectLanguageId.dart) {
        final value = yamlToString(reference.value);
        if (_isLocalizedDartDependency(value)) {
          return true;
        }
        continue;
      }

      final value = reference.value?.toString();
      if (value != null && _isLocalizedTypeScriptDependency(value)) {
        return true;
      }
    }

    return false;
  }

  /// Returns whether [dependencyYaml] still points to a localized Dart source.
  bool _isLocalizedDartDependency(String dependencyYaml) {
    return dependencyYaml.contains('path:') ||
        _containsLocalizedGitWithoutVersion(dependencyYaml);
  }

  /// Returns whether [dependencyValue] still points to a localized TS source.
  bool _isLocalizedTypeScriptDependency(String dependencyValue) {
    final trimmed = dependencyValue.trim();
    return trimmed.startsWith('file:') || trimmed.startsWith('git+');
  }

  /// Builds the final remote Dart dependency YAML for [dependencyNode].
  Future<String> _buildDartRemoteDependencyYaml({
    required ProjectNode dependencyNode,
    required Map<String, dynamic> savedDependencies,
  }) async {
    final savedDependency = savedDependencies[dependencyNode.name];
    final savedDependencyYaml = yamlToString(savedDependency).trimRight();

    final published = await isOnPubDev.get(
      directory: dependencyNode.directory,
      ggLog: ggLog,
    );
    if (published) {
      return savedDependencyYaml;
    }

    final version = _extractVersionSpec(savedDependency);
    if (version == null) {
      return savedDependencyYaml;
    }

    final gitUrl = await Utils.getGitRemoteUrl(
      dependencyNode.directory,
      dependencyNode.name,
    );

    return yamlToString(<String, dynamic>{
      'git': <String, dynamic>{'url': gitUrl, 'tag_pattern': '{{version}}'},
      'version': version,
    }).trimRight();
  }

  /// Builds the final remote TypeScript dependency spec for [dependencyNode].
  Future<String> _buildTypeScriptRemoteDependency({
    required ProjectNode dependencyNode,
    required dynamic savedDependency,
  }) async {
    final gitUrl = await Utils.getGitRemoteUrl(
      dependencyNode.directory,
      dependencyNode.name,
    );
    return 'git+$gitUrl';
  }

  /// Extracts a version constraint from [savedDependency] if available.
  String? _extractVersionSpec(dynamic savedDependency) {
    if (savedDependency is String) {
      return savedDependency;
    }

    if (savedDependency is Map) {
      final version = savedDependency['version'];
      if (version != null) {
        return version.toString();
      }
    }

    return null;
  }

  /// Returns true for old localized git blocks without a version field.
  bool _containsLocalizedGitWithoutVersion(String dependencyYaml) {
    if (!dependencyYaml.contains('git:')) {
      return false;
    }

    if (dependencyYaml.contains('tag_pattern:')) {
      return false;
    }

    return true;
  }
}
