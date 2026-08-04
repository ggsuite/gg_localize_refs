// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/pnpm_workspace_io.dart';
import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
import 'package:gg_localize_refs/src/backend/typescript_npm_spec.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:path/path.dart' as p;

/// Shared helpers for manifest based ref-changing commands.
class ManifestCommandSupport {
  /// Creates support helpers for manifest commands.
  const ManifestCommandSupport();

  /// Ensures the Dart backup directory exists.
  Directory ensureDartBackupDir(Directory projectDir) {
    final backupDir = Utils.dartBackupDir(projectDir);
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }
    return backupDir;
  }

  /// Ensures `.gitignore` contains the required `.gg` entries.
  ///
  /// The contents are ignored via `.gg/*` and not via the bare directory
  /// pattern `.gg`: git never descends into an excluded directory, so a
  /// `!.gg/gg.json` re-include below `.gg` has no effect and the check state
  /// would never reach CI. A bare `.gg` left over from earlier runs is
  /// therefore rewritten instead of kept — and so is the `!.gg/.gg.json` of
  /// the days when the files inside `.gg` were still hidden.
  void ensureGitignoreHasDartBackupEntries(Directory projectDir) {
    const ignoreDir = '.gg/*';
    const staleIgnoreDir = '.gg';
    const keepConfig = '!.gg/gg.json';
    const staleKeepConfig = '!.gg/.gg.json';

    _editGitignore(projectDir, (List<String> lines) {
      // Replace the stale entries written by earlier versions where they
      // stand: appending the replacement at the end would put it after
      // existing `!` re-includes and silence them again.
      _replaceStaleEntry(lines, staleIgnoreDir, ignoreDir);
      _replaceStaleEntry(lines, staleKeepConfig, keepConfig);

      final hasIgnoreDir = lines.any((line) => line.trim() == ignoreDir);
      final hasKeepConfig = lines.any((line) => line.trim() == keepConfig);

      if (!hasIgnoreDir) {
        lines.add(ignoreDir);
      }
      if (!hasKeepConfig) {
        lines.add(keepConfig);
      }
    });
  }

  /// Rewrites the first [stale] entry of [lines] into [replacement] and drops
  /// the remaining ones. Nothing is rewritten when [replacement] is already
  /// present — the stale entries are then only removed.
  void _replaceStaleEntry(
    List<String> lines,
    String stale,
    String replacement,
  ) {
    final staleIndex = lines.indexWhere((l) => l.trim() == stale);
    if (staleIndex >= 0 && !lines.any((l) => l.trim() == replacement)) {
      lines[staleIndex] = replacement;
    }
    lines.removeWhere((line) => line.trim() == stale);
  }

  /// Ensures `.gitignore` does **not** exclude `pubspec_overrides.yaml`.
  ///
  /// The overrides file holds relative paths only, so it travels with a shared
  /// ticket workspace exactly like the localized `pubspec.yaml` used to. It has
  /// to be committable for that, and an earlier version of this package - plus
  /// several repositories of the suite by hand - added the opposite entry.
  ///
  /// Leaving a stale entry in place would be worse than having none: a file
  /// that is gitignored *and* checked in makes `dart pub publish` fail with a
  /// "checked-in files are ignored by a .gitignore" warning.
  void ensureGitignoreAllowsPubspecOverrides(Directory projectDir) {
    const entry = PubspecOverridesIo.fileName;
    const anchoredEntry = '/$entry';

    _editGitignore(projectDir, (List<String> lines) {
      lines.removeWhere(
        (line) => line.trim() == entry || line.trim() == anchoredEntry,
      );
    });
  }

  /// Reads `.gitignore` of [projectDir] as lines, hands them to [edit] and
  /// writes the result back. A missing file is treated as empty.
  ///
  /// Nothing is written when [edit] leaves the entries as they are, so a
  /// command that changes nothing does not touch the file either. A file that
  /// does not exist is not created for nothing either.
  void _editGitignore(Directory projectDir, void Function(List<String>) edit) {
    final gitignore = File(p.join(projectDir.path, '.gitignore'));
    final existed = gitignore.existsSync();
    final raw = existed ? gitignore.readAsStringSync() : '';
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final content = normalized.endsWith('\n')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final lines = content.isEmpty ? <String>[] : content.split('\n');

    edit(lines);

    final updated = lines.isEmpty ? '' : '${lines.join('\n')}\n';
    if (updated == raw || (!existed && updated.isEmpty)) {
      return;
    }

    gitignore.writeAsStringSync(updated);
  }

  /// Queues [edit] for the `pubspec_overrides.yaml` of [projectDir].
  void bufferPubspecOverridesEdit({
    required Directory projectDir,
    required PubspecOverridesEdit edit,
    required FileChangesBuffer fileChangesBuffer,
  }) {
    if (edit.isUnchanged) {
      return;
    }

    final overridesFile = const PubspecOverridesIo().file(projectDir);
    if (edit.deleteFile) {
      fileChangesBuffer.addDeletion(overridesFile);
      return;
    }

    fileChangesBuffer.add(overridesFile, edit.content!);
  }

  /// Queues the removal of the overrides this package wrote for [node] and
  /// returns the edit, so the caller can report it.
  ///
  /// Only the overrides of the workspace dependencies are dropped, so hand
  /// written entries survive. Used by `change-refs-to-pub-dev`: both the local
  /// paths and the git feature branch refs would otherwise keep shadowing the
  /// published constraints of `pubspec.yaml`.
  ///
  /// The *transitive* dependencies are covered, because that is the set the
  /// two localizing commands write - a git override for a project the manifest
  /// does not name would otherwise survive the way back to pub.dev.
  PubspecOverridesEdit bufferPubspecOverridesRemoval({
    required ProjectNode node,
    required FileChangesBuffer fileChangesBuffer,
  }) {
    final edit = const PubspecOverridesIo().removeOwnedOverrides(
      projectDir: node.directory,
      dependencyNames: node.transitiveDependencies.keys,
    );

    bufferPubspecOverridesEdit(
      projectDir: node.directory,
      edit: edit,
      fileChangesBuffer: fileChangesBuffer,
    );

    return edit;
  }

  /// Queues [edit] for the `pnpm-workspace.yaml` of [projectDir].
  void bufferPnpmWorkspaceEdit({
    required Directory projectDir,
    required PubspecOverridesEdit edit,
    required FileChangesBuffer fileChangesBuffer,
  }) {
    if (edit.isUnchanged) {
      return;
    }

    final overridesFile = const PnpmWorkspaceIo().file(projectDir);
    if (edit.deleteFile) {
      fileChangesBuffer.addDeletion(overridesFile);
      return;
    }

    fileChangesBuffer.add(overridesFile, edit.content!);
  }

  /// Writes the TypeScript backup file for [projectDirectory].
  ///
  /// The backup lives in `.gg`, so the directory and its `.gitignore` entries
  /// are ensured here the same way the Dart commands do it.
  Future<void> writeTypeScriptBackup(
    Directory projectDirectory,
    Map<String, dynamic> replacedDependencies,
  ) async {
    ensureDartBackupDir(projectDirectory);
    ensureGitignoreHasDartBackupEntries(projectDirectory);
    final backupFile = Utils.typeScriptBackupFile(projectDirectory);
    await backupFile.writeAsString(jsonEncode(replacedDependencies));
  }

  /// Returns the `dependency_overrides` declared in [manifestMap].
  ///
  /// Pub replaces them entirely once `pubspec_overrides.yaml` exists, so every
  /// command writing that file carries them over.
  Map<String, dynamic> dependencyOverridesOf(dynamic manifestMap) {
    if (manifestMap is! Map) {
      return const <String, dynamic>{};
    }

    final section = manifestMap['dependency_overrides'];
    if (section is! Map) {
      return const <String, dynamic>{};
    }

    return <String, dynamic>{
      for (final entry in section.entries) entry.key.toString(): entry.value,
    };
  }

  /// Returns dependency references from [manifestMap].
  Map<String, DependencyReference> referencesFor(
    ProjectNode node,
    dynamic manifestMap,
  ) {
    return node.language.listDependencyReferences(manifestMap);
  }

  /// Returns true when any workspace TS dependency is not yet localized.
  bool hasNonLocalTypeScriptDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) {
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (value == null) {
        continue;
      }
      // A `file:` or `link:` spec is already localized; anything else still
      // needs localizing.
      if (!TypeScriptNpmSpec.isLocalizedSpec(value.trim())) {
        return true;
      }
    }
    return false;
  }
}
