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
import 'package:gg_localize_refs/src/backend/package_json_io.dart';
import 'package:gg_localize_refs/src/backend/pnpm_workspace_io.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
import 'package:gg_localize_refs/src/backend/typescript_npm_spec.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:path/path.dart' as p;

// #############################################################################
/// The outcome of restoring the localized Dart refs of one project.
///
/// Restoring is separated from logging and from writing so that
/// `change-refs-to-local` can reuse it to migrate a project that was localized
/// by an earlier version of this package - back then the local paths were
/// written into `pubspec.yaml` itself.
class DartRefsRestore {
  /// Creates a restore result.
  const DartRefsRestore({
    required this.hadLocalizedRefs,
    required this.backupMissing,
    required this.content,
  });

  /// Nothing was localized, so there was nothing to restore.
  const DartRefsRestore.nothingLocalized()
    : hadLocalizedRefs = false,
      backupMissing = false,
      content = null;

  /// Whether `pubspec.yaml` still contained localized refs.
  final bool hadLocalizedRefs;

  /// Whether the dependency backup needed for restoring is missing.
  final bool backupMissing;

  /// The restored `pubspec.yaml` content, or null when nothing was restored.
  final String? content;
}

// #############################################################################
/// The outcome of restoring the localized TypeScript refs of one project.
///
/// Restoring is separated from logging and from writing so that
/// `change-refs-to-local` and `change-refs-to-git-feature-branch` can reuse
/// it to migrate a project that was localized by an earlier version of this
/// package — back then the `link:`/git specs were written into
/// `package.json` itself instead of the overrides of `pnpm-workspace.yaml`.
class TypeScriptRefsRestore {
  /// Creates a restore result.
  const TypeScriptRefsRestore({
    required this.hadLocalizedRefs,
    required this.backupMissing,
    required this.content,
  });

  /// Nothing was localized, so there was nothing to restore.
  const TypeScriptRefsRestore.nothingLocalized()
    : hadLocalizedRefs = false,
      backupMissing = false,
      content = null;

  /// Whether `package.json` still contained localized refs.
  final bool hadLocalizedRefs;

  /// Whether the dependency backup needed for restoring is missing.
  final bool backupMissing;

  /// The restored `package.json` content, or null when nothing was restored.
  final String? content;
}

// #############################################################################
/// Command that reverts localized references back to remote dependencies.
class ChangeRefsToPubDev extends DirCommand<dynamic> {
  /// Creates the command.
  ChangeRefsToPubDev({required super.ggLog})
    : isOnPubDev = IsOnPubDev(ggLog: ggLog),
      super(
        name: 'change-refs-to-pub-dev',
        description: 'Changes dependencies to remote dependencies.',
      );

  /// Service used to check whether a dependency was published before.
  final IsOnPubDev isOnPubDev;

  final ManifestCommandSupport _support = const ManifestCommandSupport();

  final PnpmWorkspaceIo _pnpmWorkspace = const PnpmWorkspaceIo();

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    ggLog('Running change-refs-to-pub-dev in ${directory.path}');

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

  // ...........................................................................
  /// Logs the removal of the overrides of [node].
  void _logOverridesRemoval({
    required ProjectNode node,
    required PubspecOverridesEdit edit,
    required GgLog ggLog,
  }) {
    if (edit.isUnchanged) {
      return;
    }

    ggLog(
      'Remove the dependency overrides of ${node.name} from '
      '${PubspecOverridesIo.fileName}',
    );
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
        node: node,
        pubspec: manifestFile,
        pubspecContent: manifestContent,
        yamlMap: manifestMap,
        fileChangesBuffer: fileChangesBuffer,
        ggLog: ggLog,
      );
      return;
    }

    await _unlocalizeTypeScript(
      node: node,
      manifestFile: manifestFile,
      manifestContent: manifestContent,
      manifestMap: manifestMap,
      fileChangesBuffer: fileChangesBuffer,
      ggLog: ggLog,
    );
  }

  Future<void> _unlocalizeDart({
    required ProjectNode node,
    required File pubspec,
    required String pubspecContent,
    required dynamic yamlMap,
    required FileChangesBuffer fileChangesBuffer,
    required GgLog ggLog,
  }) async {
    // Going remote means leaving local and git feature branch mode: the
    // overrides of pubspec_overrides.yaml would keep shadowing the published
    // constraints of pubspec.yaml.
    _logOverridesRemoval(
      node: node,
      edit: _support.bufferPubspecOverridesRemoval(
        node: node,
        fileChangesBuffer: fileChangesBuffer,
      ),
      ggLog: ggLog,
    );

    final references = _support.referencesFor(node, yamlMap);

    final restore = await restoreDartRefs(
      node: node,
      pubspecContent: pubspecContent,
      references: references,
    );

    if (!restore.hadLocalizedRefs) {
      return;
    }

    ggLog('Unlocalize refs of ${node.name}');

    if (restore.backupMissing) {
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

    fileChangesBuffer.add(pubspec, restore.content!);
  }

  // ...........................................................................
  /// Restores every localized workspace dependency of [node] in
  /// [pubspecContent] back to the remote ref it was declared with.
  ///
  /// Pure with respect to the file system: it reads the dependency backup but
  /// writes nothing, so the caller decides how to log and when to apply the
  /// result. [references] are the dependency references of the manifest that
  /// [pubspecContent] was read from.
  ///
  /// With [reconstructGitRefs] a dependency that does not publish to pub.dev is
  /// turned into a git ref built from its origin - the shape a published
  /// closed-source dependency needs. Pass false to restore the backed up spec
  /// verbatim: the backup only remembers a version constraint, so rebuilding a
  /// git ref would invent a url and a tag pattern, and it would fail outright
  /// for a checkout without an origin remote.
  Future<DartRefsRestore> restoreDartRefs({
    required ProjectNode node,
    required String pubspecContent,
    required Map<String, DependencyReference> references,
    bool reconstructGitRefs = true,
  }) async {
    if (!_hasLocalizedDependencies(node: node, references: references)) {
      return const DartRefsRestore.nothingLocalized();
    }

    final backupFile = Utils.dartBackupFile(node.directory);
    if (!backupFile.existsSync()) {
      return const DartRefsRestore(
        hadLocalizedRefs: true,
        backupMissing: true,
        content: null,
      );
    }

    final savedDependencies = Utils.readDependenciesFromJson(backupFile.path);
    var newPubspecContent = pubspecContent;

    for (final dependency in node.dependencies.entries) {
      final dependencyName = dependency.key;
      final reference = references[dependencyName];
      if (reference == null || !savedDependencies.containsKey(dependencyName)) {
        continue;
      }

      final oldDependencyYaml = yamlToString(reference.value);
      if (!_isLocalizedDartDependency(oldDependencyYaml)) {
        continue;
      }

      final newDependencyYaml = reconstructGitRefs
          ? await _buildDartRemoteDependencyYaml(
              dependencyNode: dependency.value,
              savedDependencies: savedDependencies,
            )
          : yamlToString(savedDependencies[dependencyName]).trimRight();

      newPubspecContent = node.language.replaceDependencyInContent(
        manifestContent: newPubspecContent,
        reference: reference,
        newValue: newDependencyYaml,
      );
    }

    return DartRefsRestore(
      hadLocalizedRefs: true,
      backupMissing: false,
      content: newPubspecContent,
    );
  }

  Future<void> _unlocalizeTypeScript({
    required ProjectNode node,
    required File manifestFile,
    required String manifestContent,
    required dynamic manifestMap,
    required FileChangesBuffer fileChangesBuffer,
    required GgLog ggLog,
  }) async {
    final references = _support.referencesFor(node, manifestMap);

    // Going remote means leaving local and git feature branch mode: the
    // overrides of pnpm-workspace.yaml would keep shadowing the published
    // constraints of package.json. Removed before the early-out below,
    // because a repo in the new model has a pristine manifest — a check on
    // it alone would leave the overrides in place.
    final overridesEdit = _pnpmWorkspace.removeOwnedOverrides(
      projectDir: node.directory,
      dependencyNames: node.transitiveDependencies.keys,
    );
    _support.bufferPnpmWorkspaceEdit(
      projectDir: node.directory,
      edit: overridesEdit,
      fileChangesBuffer: fileChangesBuffer,
    );
    if (!overridesEdit.isUnchanged) {
      ggLog(
        'Remove the dependency overrides of ${node.name} from '
        '${PnpmWorkspaceIo.fileName}',
      );
    }

    final restore = await restoreTypeScriptRefs(
      node: node,
      manifestContent: manifestContent,
      references: references,
    );

    if (!restore.hadLocalizedRefs) {
      return;
    }

    ggLog('Unlocalize refs of ${node.name}');

    if (restore.backupMissing) {
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

    fileChangesBuffer.add(manifestFile, restore.content!);
  }

  // ...........................................................................
  /// Restores every localized workspace dependency of [node] in
  /// [manifestContent] back to the remote ref it was declared with.
  ///
  /// Pure with respect to the file system: it reads the dependency backup
  /// but writes nothing, so the caller decides how to log and when to apply
  /// the result. [references] are the dependency references of the manifest
  /// that [manifestContent] was read from. Only the manifest is covered —
  /// the overrides of `pnpm-workspace.yaml` are removed separately.
  ///
  /// With [rebuildRemoteSpecs] a dependency is rebuilt into the spec its
  /// published form needs (git specs normalized, private packages turned
  /// into `git+…#semver:` refs). Pass false to restore the backed up spec
  /// verbatim: the migration path uses this, because rebuilding reads the
  /// dependency's git remote and would abort in a checkout without an
  /// `origin`.
  Future<TypeScriptRefsRestore> restoreTypeScriptRefs({
    required ProjectNode node,
    required String manifestContent,
    required Map<String, DependencyReference> references,
    bool rebuildRemoteSpecs = true,
  }) async {
    if (!_hasLocalizedDependencies(node: node, references: references)) {
      return const TypeScriptRefsRestore.nothingLocalized();
    }

    final backupFile = Utils.typeScriptBackupFile(node.directory);
    if (!backupFile.existsSync()) {
      return const TypeScriptRefsRestore(
        hadLocalizedRefs: true,
        backupMissing: true,
        content: null,
      );
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
          newValue: rebuildRemoteSpecs
              ? await _buildTypeScriptRemoteDependency(
                  dependencyNode: dependency.value,
                  savedDependency: saved,
                )
              : saved.toString(),
        );
      }
    }

    return TypeScriptRefsRestore(
      hadLocalizedRefs: true,
      backupMissing: false,
      content: newContent,
    );
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
  /// `file:`/`link:` are current markers; `git+` is the historical heuristic.
  bool _isLocalizedTypeScriptDependency(String dependencyValue) {
    final trimmed = dependencyValue.trim();
    if (TypeScriptNpmSpec.isLocalizedSpec(trimmed)) return true;
    return trimmed.startsWith('git+');
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
      'git': <String, dynamic>{'url': gitUrl, 'tag_pattern': '"{{version}}"'},
      'version': version,
    }).trimRight();
  }

  /// Builds the remote TS dep. Rule 1: saved git URL → preserve fragment,
  /// normalize base. Rule 2: private + range → `git+<remote>#semver:`.
  /// Rule 3: public + range → keep range so `pnpm update` still sees it.
  Future<String> _buildTypeScriptRemoteDependency({
    required ProjectNode dependencyNode,
    required dynamic savedDependency,
  }) async {
    final savedSpec = savedDependency?.toString().trim() ?? '';

    if (TypeScriptNpmSpec.isGitSpec(savedSpec)) {
      final base = TypeScriptNpmSpec.toNpmGitBase(
        TypeScriptNpmSpec.stripFragment(savedSpec),
      );
      if (TypeScriptNpmSpec.hasUrlFragment(savedSpec)) {
        final fragment = savedSpec.substring(savedSpec.indexOf('#'));
        return '$base$fragment';
      }
      final range = _localSemverRange(dependencyNode);
      if (range == null) return base;
      return TypeScriptNpmSpec.withSemverFragment(base, range);
    }

    if (PackageJsonIo.isPrivate(dependencyNode.directory)) {
      final gitUrl = await Utils.getGitRemoteUrl(
        dependencyNode.directory,
        dependencyNode.name,
      );
      final base = TypeScriptNpmSpec.toNpmGitBase(gitUrl);
      final range =
          TypeScriptNpmSpec.toSemverRange(savedSpec) ??
          _localSemverRange(dependencyNode);
      if (range == null) return base;
      return TypeScriptNpmSpec.withSemverFragment(base, range);
    }

    return savedSpec;
  }

  /// Caret-range derived from the local `package.json` version, or `null`.
  String? _localSemverRange(ProjectNode dependencyNode) {
    final version = PackageJsonIo.readVersion(dependencyNode.directory);
    return version == null ? null : TypeScriptNpmSpec.toSemverRange(version);
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

    if (dependencyYaml.contains('version:')) {
      return false;
    }

    return true;
  }
}
