// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
import 'package:gg_localize_refs/src/backend/typescript_npm_spec.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
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
  /// `!.gg/.gg.json` re-include below `.gg` has no effect and the check state
  /// would never reach CI. A bare `.gg` left over from earlier runs is
  /// therefore rewritten instead of kept.
  void ensureGitignoreHasDartBackupEntries(Directory projectDir) {
    const ignoreDir = '.gg/*';
    const staleIgnoreDir = '.gg';
    const keepConfig = '!.gg/.gg.json';

    _editGitignore(projectDir, (List<String> lines) {
      // Replace the bare `.gg` written by earlier versions where it stands:
      // appending the replacement at the end would put it after existing `!`
      // re-includes and silence them again.
      final staleIndex = lines.indexWhere((l) => l.trim() == staleIgnoreDir);
      if (staleIndex >= 0 && !lines.any((l) => l.trim() == ignoreDir)) {
        lines[staleIndex] = ignoreDir;
      }
      lines.removeWhere((line) => line.trim() == staleIgnoreDir);

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

  /// Ensures `.gitignore` excludes `pubspec_overrides.yaml`.
  ///
  /// The overrides file wires a package to the checkouts of one developer
  /// machine, so it must never be committed. The entry is anchored to the
  /// package root: an unanchored pattern matches at every depth and would also
  /// hide the overrides files of test fixtures and example projects.
  void ensureGitignoreHasPubspecOverrides(Directory projectDir) {
    const entry = '/${PubspecOverridesIo.fileName}';

    _editGitignore(projectDir, (List<String> lines) {
      if (!lines.any((line) => line.trim() == entry)) {
        lines.add(entry);
      }
    });
  }

  /// Reads `.gitignore` of [projectDir] as lines, hands them to [edit] and
  /// writes the result back. A missing file is treated as empty.
  ///
  /// Nothing is written when [edit] leaves the entries as they are, so a
  /// command that changes nothing does not touch the file either.
  void _editGitignore(Directory projectDir, void Function(List<String>) edit) {
    final gitignore = File(p.join(projectDir.path, '.gitignore'));
    final raw = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final content = normalized.endsWith('\n')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final lines = content.isEmpty ? <String>[] : content.split('\n');

    edit(lines);

    final updated = '${lines.join('\n')}\n';
    if (gitignore.existsSync() && updated == raw) {
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

  /// Queues the removal of the local path overrides of [node] and returns the
  /// edit, so the caller can report it.
  ///
  /// Only the overrides of the workspace dependencies are dropped, so hand
  /// written entries survive. Used by the commands that leave local mode:
  /// their remote refs would otherwise stay shadowed by the local paths.
  PubspecOverridesEdit bufferPubspecOverridesRemoval({
    required ProjectNode node,
    required FileChangesBuffer fileChangesBuffer,
  }) {
    final edit = const PubspecOverridesIo().removePathOverrides(
      projectDir: node.directory,
      dependencyNames: node.dependencies.keys,
    );

    bufferPubspecOverridesEdit(
      projectDir: node.directory,
      edit: edit,
      fileChangesBuffer: fileChangesBuffer,
    );

    return edit;
  }

  /// Copies [source] to [destination].
  Future<void> writeFileCopy({
    required File source,
    required File destination,
  }) async {
    await source.copy(destination.path);
  }

  /// Saves [replacedDependencies] as JSON at [filePath].
  Future<void> saveDependenciesAsJson(
    Map<String, dynamic> replacedDependencies,
    String filePath,
  ) async {
    final jsonString = jsonEncode(replacedDependencies);
    final file = File(filePath);
    await file.writeAsString(jsonString);
  }

  /// Writes the TypeScript backup file for [projectDirectory].
  Future<void> writeTypeScriptBackup(
    Directory projectDirectory,
    Map<String, dynamic> replacedDependencies,
  ) async {
    final backupFile = Utils.typeScriptBackupFile(projectDirectory);
    await backupFile.writeAsString(jsonEncode(replacedDependencies));
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

  /// Returns backup entries normalized to plain version strings where possible.
  Map<String, dynamic> buildUpdatedDartBackupDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
    required bool Function(String dependencyYaml) shouldRefreshBackup,
  }) {
    final backupFile = Utils.dartBackupFile(node.directory);
    final existingBackup = backupFile.existsSync()
        ? Utils.readDependenciesFromJson(backupFile.path)
        : <String, dynamic>{};

    final updatedBackup = <String, dynamic>{};

    for (final entry in existingBackup.entries) {
      final normalizedValue = normalizeBackupVersionValue(entry.value);
      if (normalizedValue != null) {
        updatedBackup[entry.key] = normalizedValue;
      }
    }

    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }

      final dependencyYaml = yamlToString(reference.value);
      if (!shouldRefreshBackup(dependencyYaml)) {
        continue;
      }

      final normalizedValue = normalizeBackupVersionValue(reference.value);
      if (normalizedValue != null) {
        updatedBackup[dependency.key] = normalizedValue;
      }
    }

    return updatedBackup;
  }

  /// Returns the normalized backup version or null when it cannot be used.
  dynamic normalizeBackupVersionValue(dynamic dependency) {
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
}
