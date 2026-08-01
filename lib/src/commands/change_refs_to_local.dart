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
import 'package:gg_localize_refs/src/backend/manifest_command_support.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/backend/publish_to_utils.dart';
import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
import 'package:gg_localize_refs/src/backend/typescript_npm_spec.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_localize_refs/src/commands/change_refs_to_pub_dev.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;

/// Command for localizing references to local path dependencies.
///
/// For Dart projects the local paths are declared as `dependency_overrides` in
/// `pubspec_overrides.yaml`; `pubspec.yaml` keeps the published constraints and
/// is not rewritten. A project that an earlier version of this package
/// localized inside `pubspec.yaml` is migrated on the way.
class ChangeRefsToLocal extends DirCommand<dynamic> {
  /// Constructor.
  ///
  /// [changeRefsToPubDev] is used to restore `pubspec.yaml` when a project is
  /// still localized the old way; inject it to keep the migration offline.
  ChangeRefsToLocal({
    required super.ggLog,
    ChangeRefsToPubDev? changeRefsToPubDev,
  }) : _changeRefsToPubDev =
           changeRefsToPubDev ?? ChangeRefsToPubDev(ggLog: ggLog),
       super(
         name: 'change-refs-to-local',
         description: 'Localize references to local path dependencies',
       );

  final ManifestCommandSupport _support = const ManifestCommandSupport();

  final PubspecOverridesIo _overrides = const PubspecOverridesIo();

  final ChangeRefsToPubDev _changeRefsToPubDev;

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
    _support.ensureGitignoreHasDartBackupEntries(projectDir);
    _support.ensureGitignoreAllowsPubspecOverrides(projectDir);
    final references = _support.referencesFor(node, yamlMap);

    await _migrateManifest(
      node: node,
      pubspec: pubspec,
      pubspecContent: pubspecContent,
      references: references,
      fileChangesBuffer: fileChangesBuffer,
      ggLog: ggLog,
    );

    final edit = _overrides.addPathOverrides(
      projectDir: projectDir,
      pathsByDependency: <String, String>{
        for (final dependency in node.dependencies.entries)
          dependency.key: _relativePathTo(
            from: projectDir,
            to: dependency.value.directory,
          ),
      },
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

  /// Undoes a localization an earlier version of this package wrote into
  /// `pubspec.yaml`, so the manifest is left with its published refs only.
  ///
  /// Covers both starting points that keep local paths or a feature branch
  /// pinned inside the manifest: `path:` entries and git refs without a
  /// version. The `publish_to: none` that came with them is reverted to the
  /// backed up original.
  Future<void> _migrateManifest({
    required ProjectNode node,
    required File pubspec,
    required String pubspecContent,
    required Map<String, DependencyReference> references,
    required FileChangesBuffer fileChangesBuffer,
    required GgLog ggLog,
  }) async {
    final restore = await _changeRefsToPubDev.restoreDartRefs(
      node: node,
      pubspecContent: pubspecContent,
      references: references,
      // Restore what the backup remembers - nothing else. Rebuilding a git ref
      // would invent a url plus a tag pattern for every dependency that
      // carries the `publish_to: none` the old localization injected, and it
      // would abort the whole command in a checkout without an origin remote.
      reconstructGitRefs: false,
    );

    if (restore.backupMissing) {
      ggLog(
        yellow(
          'The refs of ${node.name} are localized inside '
          '${red(p.join(node.directory.path, 'pubspec.yaml'))} and cannot be '
          'migrated automatically, because the dependency backup is missing. '
          'Please restore the original dependencies manually.',
        ),
      );
      return;
    }

    final backupFile = Utils.dartPublishToBackupFile(node.directory);
    var newContent = restore.content ?? pubspecContent;

    if (_hasPublishToNone(newContent) && backupFile.existsSync()) {
      // The backup is not deleted here: the git feature branch mode still
      // injects `publish_to: none` and relies on it to find the original.
      final backupMap =
          jsonDecode(backupFile.readAsStringSync()) as Map<String, dynamic>;
      newContent = restorePublishTo(newContent, backupMap);
    } else if (restore.content != null && _hasPublishToNone(newContent)) {
      // A `publish_to: none` cannot be told apart from one of a package that is
      // private by intention, so it is kept - but the user has to know that
      // the package stays unpublishable.
      ggLog(
        yellow(
          'Kept publish_to: none in '
          '${p.join(node.directory.path, 'pubspec.yaml')} - without a '
          'publish_to backup it is unknown whether it was injected while '
          'localizing. Remove it manually if the package is publishable.',
        ),
      );
    }

    if (newContent == pubspecContent) {
      return;
    }

    // The line based dependency replacement drops the trailing newline. The
    // manifest is otherwise left alone, so it must not gain a
    // "no newline at end of file" diff on top of the migration.
    if (pubspecContent.endsWith('\n') && !newContent.endsWith('\n')) {
      newContent = '$newContent\n';
    }

    ggLog(
      restore.content != null
          ? 'Migrate refs of ${node.name} out of pubspec.yaml'
          : 'Revert the injected publish_to of ${node.name}',
    );
    fileChangesBuffer.add(pubspec, newContent);
  }

  /// Returns the path of [to] relative to [from], always with forward slashes.
  ///
  /// Pub accepts forward slashes on every platform, so the written override
  /// stays the same no matter where it was generated. The separators are
  /// rebuilt from the split path instead of replacing every backslash, because
  /// a POSIX directory name may legally contain one.
  String _relativePathTo({required Directory from, required Directory to}) {
    final relative = p.relative(to.path, from: from.path);
    return p.posix.joinAll(p.split(relative));
  }

  /// Returns whether [pubspecContent] declares `publish_to: none`.
  bool _hasPublishToNone(String pubspecContent) {
    return RegExp(
      r'^publish_to:\s*none\s*$',
      multiLine: true,
    ).hasMatch(pubspecContent);
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
      if (!TypeScriptNpmSpec.isLocalizedSpec(oldString.trim())) {
        replacedDependencies[dependency.key] = oldValue;
      }

      final relativePath = p
          .relative(dependency.value.directory.path, from: node.directory.path)
          .replaceAll('\\', '/');

      // Use pnpm's `link:` (a live symlink to the sibling source dir), not
      // `file:` (which pnpm snapshots into its store at install time). A
      // snapshot goes stale the moment the dependency is rebuilt — e.g. a
      // bridge whose `dist/` is generated — so a consumer would resolve an
      // out-of-date copy. `link:` mirrors Dart's `path:` live-link semantics.
      updatedContent = node.language.replaceDependencyInContent(
        manifestContent: updatedContent,
        reference: reference,
        newValue: 'link:$relativePath',
      );
    }

    if (replacedDependencies.isEmpty) {
      return;
    }

    await _support.writeTypeScriptBackup(node.directory, replacedDependencies);
    fileChangesBuffer.add(manifestFile, updatedContent);
  }
}
