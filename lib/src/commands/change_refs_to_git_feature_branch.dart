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
import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
import 'package:gg_localize_refs/src/backend/typescript_npm_spec.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_log/gg_log.dart';

/// Command that changes workspace dependencies to git references.
///
/// For Dart projects the git refs are declared as `dependency_overrides` in
/// `pubspec_overrides.yaml`; `pubspec.yaml` keeps its published constraints
/// and is not rewritten - so the package stays publishable and its manifest
/// never carries a feature branch pin. TypeScript keeps writing the git specs
/// into `package.json`, because npm has no overrides sibling.
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

  final PubspecOverridesIo _overrides = const PubspecOverridesIo();

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

      if (fileChangesBuffer.isEmpty) {
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
    required dynamic yamlMap,
    required FileChangesBuffer fileChangesBuffer,
    required GgLog ggLog,
  }) async {
    final projectDir = node.directory;
    _support.ensureGitignoreAllowsPubspecOverrides(projectDir);

    // The overrides are written for every *transitive* workspace dependency,
    // also for one that pubspec.yaml already declares as a git ref: pub does
    // not merge the two sections and reads them from the root package only, so
    // an entry left out here would resolve against the published constraint
    // while its siblings sit on the feature branch.
    final gitUrls = <String, String>{};
    for (final dependency in node.transitiveDependencies.entries) {
      gitUrls[dependency.key] = await Utils.getGitRemoteUrl(
        dependency.value.directory,
        dependency.key,
      );
    }

    final edit = _overrides.addGitOverrides(
      projectDir: projectDir,
      gitUrlsByDependency: gitUrls,
      ref: gitRefOverride!.trim(),
      inheritedOverrides: _support.dependencyOverridesOf(yamlMap),
    );

    if (edit.isUnchanged) {
      return;
    }

    ggLog('Localize refs of ${node.name}');

    _support.bufferPubspecOverridesEdit(
      projectDir: projectDir,
      edit: edit,
      fileChangesBuffer: fileChangesBuffer,
    );
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
    for (final dependency in node.transitiveDependencies.entries) {
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
    for (final dependency in node.transitiveDependencies.entries) {
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

  /// Returns true when any TS workspace dependency is not yet a git spec.
  bool _hasNonGitTypeScriptDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) {
    for (final dependency in node.transitiveDependencies.entries) {
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

  /// Returns a git spec string usable in package.json for TypeScript.
  Future<String> getGitDependencySpecForTs(
    Directory depDir,
    String depName,
  ) async {
    final url = await Utils.getGitRemoteUrl(depDir, depName);
    final ref = gitRefOverride!.trim();

    // SCP-shorthand `git@host:path` → `git+ssh://…` (pnpm 11 rejects SCP).
    return '${TypeScriptNpmSpec.toNpmGitBase(url)}#$ref';
  }
}
