// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/commands/localize_refs.dart'
    as legacy
    show getDependency;
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/backend/publish_to_utils.dart';
import 'package:gg_localize_refs/src/backend/replace_dependency.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;

// #############################################################################
/// Command that reverts localized references back to remote dependencies.
class UnlocalizeRefs extends DirCommand<dynamic> {
  /// Constructor
  UnlocalizeRefs({required super.ggLog})
    : super(
        name: 'unlocalize-refs',
        description: 'Changes dependencies to remote dependencies.',
      );

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
  /// Modify the manifest file
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
        manifestMap as Map<dynamic, dynamic>,
        fileChangesBuffer,
      );
      return;
    }

    if (node.language.id == ProjectLanguageId.typescript) {
      await _unlocalizeTypeScript(
        node,
        manifestFile,
        manifestContent,
        manifestMap as Map<String, dynamic>,
        fileChangesBuffer,
      );
    }
  }

  Future<void> _unlocalizeDart(
    ProjectNode node,
    File pubspec,
    String pubspecContent,
    Map<dynamic, dynamic> yamlMap,
    FileChangesBuffer fileChangesBuffer,
  ) async {
    var hasLocalDependencies = false;

    for (final dependency in node.dependencies.entries) {
      final oldDependencyYaml = yamlToString(
        legacy.getDependency(dependency.key, yamlMap),
      );

      if (oldDependencyYaml.contains('path:') ||
          oldDependencyYaml.contains('git:')) {
        hasLocalDependencies = true;
      }
    }

    if (!hasLocalDependencies) {
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
      final oldDependency = legacy.getDependency(dependencyName, yamlMap);
      final oldDependencyYaml = yamlToString(oldDependency);

      if (!savedDependencies.containsKey(dependencyName)) {
        continue;
      }

      if (!oldDependencyYaml.contains('path:') &&
          !oldDependencyYaml.contains('git:')) {
        continue;
      }

      final newDependencyYaml = yamlToString(savedDependencies[dependencyName]);

      newPubspecContent = replaceDependency(
        newPubspecContent,
        dependencyName,
        oldDependencyYaml,
        newDependencyYaml,
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
    Map<String, dynamic> manifestMap,
    FileChangesBuffer fileChangesBuffer,
  ) async {
    final dependencies = manifestMap['dependencies'] is Map
        ? (manifestMap['dependencies'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final devDependencies = manifestMap['devDependencies'] is Map
        ? (manifestMap['devDependencies'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    var hasLocalDependencies = false;
    for (final dependency in node.dependencies.entries) {
      final name = dependency.key;
      final value =
          dependencies[name]?.toString() ?? devDependencies[name]?.toString();
      if (value == null) {
        continue;
      }
      final trimmed = value.trim();
      if (trimmed.startsWith('file:') || trimmed.startsWith('git+')) {
        hasLocalDependencies = true;
      }
    }

    if (!hasLocalDependencies) {
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

    for (final dependency in node.dependencies.entries) {
      final name = dependency.key;
      final saved = savedDependencies[name];
      if (saved == null) {
        continue;
      }

      if (dependencies.containsKey(name)) {
        final current = dependencies[name]?.toString() ?? '';
        if (current.trim().startsWith('file:') ||
            current.trim().startsWith('git+')) {
          dependencies[name] = saved;
        }
      } else if (devDependencies.containsKey(name)) {
        final current = devDependencies[name]?.toString() ?? '';
        if (current.trim().startsWith('file:') ||
            current.trim().startsWith('git+')) {
          devDependencies[name] = saved;
        }
      }
    }

    manifestMap['dependencies'] = dependencies;
    manifestMap['devDependencies'] = devDependencies;

    final newContent = jsonEncode(manifestMap);
    fileChangesBuffer.add(manifestFile, '$newContent\n');
  }
}

// ...........................................................................
/// Read dependencies from a JSON file
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
