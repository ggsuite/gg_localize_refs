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
  Future<void> get({required Directory directory, GgLog? ggLog}) async {
    ggLog?.call('Running unlocalize-refs in ${directory.path}');

    final fileChangesBuffer = FileChangesBuffer();

    try {
      await processProject(
        directory: directory,
        modifyFunction: modifyManifest,
        fileChangesBuffer: fileChangesBuffer,
        ggLog: ggLog,
      );

      if (fileChangesBuffer.files.isEmpty) {
        ggLog?.call(yellow('No files were changed.'));
        return;
      }

      await fileChangesBuffer.apply();
    } catch (e) {
      throw Exception(red('An error occurred: $e. No files were changed.'));
    }
  }

  // ...........................................................................
  /// Modify the manifest file.
  Future<void> modifyManifest(
    ProjectNode node,
    File manifestFile,
    String manifestContent,
    dynamic manifestMap,
    FileChangesBuffer fileChangesBuffer,
  ) async {
    if (node.language.id == ProjectLanguageId.dart) {
      await _unlocalizeDart(
        node,
        manifestFile,
        manifestContent,
        manifestMap,
        fileChangesBuffer,
      );
      return;
    }

    await _unlocalizeTypeScript(
      node,
      manifestFile,
      manifestContent,
      manifestMap,
      fileChangesBuffer,
    );
  }

  Future<void> _unlocalizeDart(
    ProjectNode node,
    File pubspec,
    String pubspecContent,
    dynamic yamlMap,
    FileChangesBuffer fileChangesBuffer,
  ) async {
    var hasLocalizedDependencies = false;
    final references = node.language.listDependencyReferences(yamlMap);

    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }

      final oldDependencyYaml = yamlToString(reference.value);
      if (_isLocalizedDartDependency(oldDependencyYaml)) {
        hasLocalizedDependencies = true;
      }
    }

    if (!hasLocalizedDependencies) {
      return;
    }

    ggLog('Unlocalize refs of ${node.name}');

    final backupDir = Directory(p.join(node.directory.path, '.gg'));
    final backupFile = File(
      p.join(backupDir.path, '.gg_localize_refs_backup.json'),
    );

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

    final savedDependencies = readDependenciesFromJson(backupFile.path);

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

    final modifiedPubspec = File('${node.directory.path}/pubspec.yaml');
    fileChangesBuffer.add(modifiedPubspec, newPubspecContent);
  }

  Future<void> _unlocalizeTypeScript(
    ProjectNode node,
    File manifestFile,
    String manifestContent,
    dynamic manifestMap,
    FileChangesBuffer fileChangesBuffer,
  ) async {
    final references = node.language.listDependencyReferences(manifestMap);

    var hasLocalizedDependencies = false;
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (value == null) {
        continue;
      }
      if (_isLocalizedTypeScriptDependency(value)) {
        hasLocalizedDependencies = true;
      }
    }

    if (!hasLocalizedDependencies) {
      return;
    }

    ggLog('Unlocalize refs of ${node.name}');

    final backupFile = File(
      '${node.directory.path}/.gg_localize_refs_backup.json',
    );

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

    final savedDependencies = readDependenciesFromJson(backupFile.path);
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

    final wasPublished = await _wasPublished(dependencyNode.directory);
    if (wasPublished) {
      return savedDependencyYaml;
    }

    final version = _extractVersionSpec(savedDependency);
    if (version == null) {
      return savedDependencyYaml;
    }

    final gitUrl = await _getGitRemoteUrl(
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
    final savedValue = savedDependency.toString();
    final wasPublished = await _wasPublished(dependencyNode.directory);
    if (wasPublished) {
      return savedValue;
    }

    final gitUrl = await _getGitRemoteUrl(
      dependencyNode.directory,
      dependencyNode.name,
    );
    return 'git+$gitUrl';
  }

  /// Returns true when the project in [directory] was published before.
  Future<bool> _wasPublished(Directory directory) async {
    try {
      return await isOnPubDev.get(directory: directory, ggLog: (_) {});
    } catch (_) {
      return false;
    }
  }

  /// Reads the origin URL from git for [dependencyName].
  Future<String> _getGitRemoteUrl(
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

// ...........................................................................
/// Read dependencies from a JSON file.
Map<String, dynamic> readDependenciesFromJson(String filePath) {
  final file = File(filePath);

  if (!file.existsSync()) {
    throw Exception(
      'The json file $filePath with old dependencies does not exist.',
    );
  }

  final jsonString = file.readAsStringSync();
  return jsonDecode(jsonString) as Map<String, dynamic>;
}
