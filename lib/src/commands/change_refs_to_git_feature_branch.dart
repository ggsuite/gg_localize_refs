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

/// Command that changes workspace dependencies to git references.
class ChangeRefsToGitFeatureBranch extends DirCommand<dynamic> {
  /// Creates the command.
  ChangeRefsToGitFeatureBranch({required super.ggLog})
    : super(
        name: 'change-refs-to-git-feature-branch',
        description: 'Changes dependencies to git dependencies.',
      ) {
    argParser.addOption(
      'git-ref',
      help: 'Git ref (branch, tag, or commit) to use for git dependencies.',
    );
    // coverage:ignore-start
    runProcess =
        (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
        }) {
          return Process.run(
            executable,
            arguments,
            workingDirectory: workingDirectory,
          );
        };
    // coverage:ignore-end
  }

  final ManifestCommandSupport _support = const ManifestCommandSupport();

  /// The function used to run processes.
  late Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  runProcess;

  /// The git ref to use for all converted dependencies.
  String? gitRefOverride;

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    String? gitRef,
  }) async {
    ggLog('Running change-refs-to-git-feature-branch in ${directory.path}');
    gitRefOverride = gitRef ?? (argResults?['git-ref'] as String?);

    if (gitRefOverride == null || gitRefOverride!.trim().isEmpty) {
      throw Exception(
        red(
          'Please provide the git ref via --git-ref for '
          'change-refs-to-git-feature-branch.',
        ),
      );
    }

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
    final references = _support.referencesFor(node, yamlMap);

    if (!_hasNonGitDartDependencies(node: node, references: references)) {
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
      shouldRefreshBackup: _shouldBackupOriginalGitDependency,
    );
    if (_support.shouldBackupPublishTo(node: node, references: references)) {
      replacedDependencies.addAll(
        backupPublishTo(yamlMap as Map<dynamic, dynamic>),
      );
    }

    await _support.saveDependenciesAsJson(
      replacedDependencies,
      Utils.dartBackupFile(projectDir).path,
    );

    var newPubspecContent = pubspecContent;
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }

      final oldDependencyYaml = yamlToString(reference.value);
      if (_shouldConvertToGit(oldDependencyYaml)) {
        final newDependencyYaml = await getGitDependencyYaml(
          dependency.value.directory,
          dependency.key,
        );
        newPubspecContent = node.language.replaceDependencyInContent(
          manifestContent: newPubspecContent,
          reference: reference,
          newValue: newDependencyYaml,
        );
      }
    }

    newPubspecContent = addPublishToNone(newPubspecContent);
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

    if (!_hasNonGitTypeScriptDependencies(node: node, references: references)) {
      return;
    }

    ggLog('Localize refs of ${node.name}');

    final replacedDependencies = <String, dynamic>{};
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (value == null) {
        continue;
      }
      if (!value.trim().startsWith('git+')) {
        replacedDependencies[dependency.key] = value;
      }
    }

    await _support.writeTypeScriptBackup(node.directory, replacedDependencies);

    var updatedContent = manifestContent;
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (reference == null || value == null) {
        continue;
      }
      if (value.trim().startsWith('git+')) {
        continue;
      }

      final gitSpec = await getGitDependencySpecForTs(
        dependency.value.directory,
        dependency.key,
      );
      updatedContent = node.language.replaceDependencyInContent(
        manifestContent: updatedContent,
        reference: reference,
        newValue: gitSpec,
      );
    }

    fileChangesBuffer.add(manifestFile, updatedContent);
  }

  /// Returns true when any Dart workspace dependency is not yet a plain git ref
  bool _hasNonGitDartDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) {
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }
      if (_shouldConvertToGit(yamlToString(reference.value))) {
        return true;
      }
    }
    return false;
  }

  /// Returns true when any TS workspace dependency is not yet a git spec.
  bool _hasNonGitTypeScriptDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) {
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (value == null) {
        continue;
      }
      if (!value.trim().startsWith('git+')) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether [dependencyYaml] should be converted to a plain git ref.
  bool _shouldConvertToGit(String dependencyYaml) {
    final trimmed = dependencyYaml.trimLeft();
    if (!trimmed.startsWith('git:')) {
      return true;
    }

    return trimmed.contains('version:');
  }

  /// Returns whether the original dependency should be backed up.
  bool _shouldBackupOriginalGitDependency(String dependencyYaml) {
    final trimmed = dependencyYaml.trimLeft();
    if (!trimmed.startsWith('git:')) {
      return true;
    }

    return trimmed.contains('version:');
  }

  /// Get a dependency Yaml for a git repo.
  Future<String> getGitDependencyYaml(Directory depDir, String depName) async {
    final gitInfo = await _resolveGitUrlAndRef(depDir, depName);
    final url = gitInfo.$1;
    final ref = gitInfo.$2;

    final gitMap = <String, dynamic>{
      'git': <String, dynamic>{'url': url, 'ref': ref},
    };

    return yamlToString(gitMap);
  }

  /// Returns a git spec string usable in package.json for TypeScript.
  Future<String> getGitDependencySpecForTs(
    Directory depDir,
    String depName,
  ) async {
    final gitInfo = await _resolveGitUrlAndRef(depDir, depName);
    final url = gitInfo.$1;
    final ref = gitInfo.$2;

    return 'git+$url#$ref';
  }

  Future<(String, String)> _resolveGitUrlAndRef(
    Directory depDir,
    String depName,
  ) async {
    final url = await Utils.getGitRemoteUrl(depDir, depName);
    final ref = gitRefOverride!.trim();
    return (url, ref);
  }
}
