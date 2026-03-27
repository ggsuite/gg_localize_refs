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
  }

  /// The function used to run processes.
  late Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  runProcess;

  /// The git ref to use for all converted dependencies.
  String? gitRefOverride;

  /// Ensures the backup directory (.gg) exists under [projectDir].
  Directory _ensureBackupDir(Directory projectDir) {
    final backupDir = Utils.dartBackupDir(projectDir);
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }
    return backupDir;
  }

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
    final references = node.language.listDependencyReferences(yamlMap);

    var hasNonGitDependencies = false;
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }
      final dependencyYaml = yamlToString(reference.value);
      if (_shouldConvertToGit(dependencyYaml)) {
        hasNonGitDependencies = true;
      }
    }

    if (!hasNonGitDependencies) {
      return;
    }

    ggLog('Localize refs of ${node.name}');

    final originalPubspec = Utils.dartBackupYamlFile(projectDir);
    await _writeFileCopy(source: pubspec, destination: originalPubspec);

    final replacedDependencies = await _buildUpdatedDartBackupDependencies(
      node: node,
      references: references,
    );

    final publishBackup = backupPublishTo(yamlMap as Map<dynamic, dynamic>);
    replacedDependencies.addAll(publishBackup);

    await saveDependenciesAsJson(
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

  Future<void> _modifyTypeScript(
    ProjectNode node,
    File manifestFile,
    String manifestContent,
    Map<String, dynamic> manifestMap,
    FileChangesBuffer fileChangesBuffer,
    GgLog ggLog,
  ) async {
    final references = node.language.listDependencyReferences(manifestMap);

    var hasNonGitDependencies = false;
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (value == null) {
        continue;
      }
      if (!value.trim().startsWith('git+')) {
        hasNonGitDependencies = true;
      }
    }

    if (!hasNonGitDependencies) {
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

    await _writeTypeScriptBackup(node.directory, replacedDependencies);

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

      final normalized = _normalizeBackupVersionValue(entry.value);
      if (normalized != null) {
        updatedBackup[entry.key] = normalized;
      }
    }

    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }

      final dependencyYaml = yamlToString(reference.value);
      final shouldRefreshBackup = _shouldBackupOriginalGitDependency(
        dependencyYaml,
      );

      if (!shouldRefreshBackup) {
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

  /// Returns the normalized backup value or null when no version exists.
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

  /// Returns whether [dependencyYaml] should be converted to a plain git ref.
  bool _shouldConvertToGit(String dependencyYaml) {
    final trimmed = dependencyYaml.trimLeft();
    if (!trimmed.startsWith('git:')) {
      return true;
    }

    return trimmed.contains('tag_pattern:');
  }

  /// Returns whether the original dependency should be backed up.
  bool _shouldBackupOriginalGitDependency(String dependencyYaml) {
    final trimmed = dependencyYaml.trimLeft();
    if (!trimmed.startsWith('git:')) {
      return true;
    }

    return trimmed.contains('tag_pattern:');
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
