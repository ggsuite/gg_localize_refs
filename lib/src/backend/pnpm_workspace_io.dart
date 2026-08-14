// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
import 'package:gg_localize_refs/src/backend/typescript_npm_spec.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Reads and edits the `overrides` section of a `pnpm-workspace.yaml`.
///
/// `pnpm-workspace.yaml` is pnpm's per-repository settings file. Redirecting
/// a reference through its `overrides` section instead of rewriting
/// `package.json` keeps the published dependency constraints intact — the
/// same architecture `pubspec_overrides.yaml` gives Dart. pnpm applies the
/// overrides to the whole resolution, direct dependencies included, and the
/// file never ships with a published tarball.
///
/// The section is the only place that can express this redirection:
///
/// - npm's own top-level `overrides` field of `package.json` refuses an
///   override that conflicts with a direct dependency (`EOVERRIDE`) — and
///   redirecting direct dependencies is exactly what localizing does. pnpm
///   ignores the field entirely.
/// - The `pnpm.overrides` field of `package.json` is dead since pnpm 11,
///   which reads settings exclusively from `pnpm-workspace.yaml`.
///
/// Repositories not managed by pnpm therefore keep the legacy in-manifest
/// `link:` rewrite — npm has no working overrides sibling for direct
/// dependencies.
///
/// Two kinds of overrides are written: a `link:` pointing at the sibling
/// checkout (local mode) and a `git+…#ref` spec pinning the ticket's feature
/// branch (git feature branch mode). They are mutually exclusive — writing
/// one replaces the other.
///
/// All edits merge into an existing file: settings and entries this package
/// does not own are preserved, and the file is only deleted when this
/// package created it (recognized by [headerComment]) and nothing but an
/// empty `overrides` section is left in it.
class PnpmWorkspaceIo {
  /// Creates the io helper.
  const PnpmWorkspaceIo();

  /// The name of pnpm's per-repository settings file.
  static const String fileName = 'pnpm-workspace.yaml';

  /// The header written above a file this package creates from scratch.
  ///
  /// Doubles as the ownership marker: only a file starting with it may be
  /// deleted again once the last override is removed — an existing
  /// `pnpm-workspace.yaml` carries the user's pnpm settings and stays.
  static const String headerComment =
      '# Created by gg_localize_refs. The overrides section redirects\n'
      '# the dependencies of package.json to the sibling checkouts of\n'
      '# this workspace without touching their published constraints.\n'
      '# change-refs-to-pub-dev removes the section again.\n';

  /// Returns the `pnpm-workspace.yaml` of the project in [projectDir].
  File file(Directory projectDir) => File(p.join(projectDir.path, fileName));

  // ...........................................................................
  /// Returns whether the project in [projectDir] is managed by pnpm.
  ///
  /// Recognized by the `packageManager` field of `package.json` (the
  /// corepack pin every pnpm ≥ 9 project carries), a `pnpm-lock.yaml` or an
  /// existing `pnpm-workspace.yaml`. Only pnpm projects get their refs
  /// redirected through the overrides of `pnpm-workspace.yaml`; everything
  /// else keeps the legacy in-manifest rewrite.
  static bool isPnpmManaged(Directory projectDir) {
    if (File(p.join(projectDir.path, 'pnpm-lock.yaml')).existsSync() ||
        File(p.join(projectDir.path, fileName)).existsSync()) {
      return true;
    }

    final packageJson = File(p.join(projectDir.path, 'package.json'));
    if (!packageJson.existsSync()) {
      return false;
    }

    try {
      final parsed = jsonDecode(packageJson.readAsStringSync());
      if (parsed is! Map) {
        return false;
      }
      final packageManager = parsed['packageManager'];
      return packageManager is String && packageManager.startsWith('pnpm@');
    } catch (_) {
      return false;
    }
  }

  // ...........................................................................
  /// Returns whether the `pnpm-workspace.yaml` of [projectDir] still
  /// redirects at least one dependency to a local working copy — an
  /// `overrides` entry with a `link:`/`file:` spec.
  ///
  /// A missing file, one without overrides and one holding only git specs or
  /// version constraints all count as »no localized refs«. An unparsable
  /// file counts as localized — it cannot prove the opposite, and the
  /// callers use this to *refuse* an operation (`gg do publish
  /// --merge-only`, which must not put local-only refs onto a main branch).
  static bool hasLocalizedRefs(Directory projectDir) {
    final overridesFile = File(p.join(projectDir.path, fileName));
    if (!overridesFile.existsSync()) {
      return false;
    }

    final content = overridesFile.readAsStringSync();
    if (content.trim().isEmpty) {
      return false;
    }

    final dynamic parsed;
    try {
      parsed = loadYaml(content);
    } catch (_) {
      return true;
    }

    if (parsed is! Map) {
      return false;
    }

    final section = parsed['overrides'];
    if (section is! Map) {
      return false;
    }

    return section.values.any(
      (dynamic value) =>
          value is String && TypeScriptNpmSpec.isLocalizedSpec(value),
    );
  }

  // ...........................................................................
  /// Computes the edit that declares a `link:` override for every entry of
  /// [pathsByDependency] (dependency name → path relative to [projectDir]).
  ///
  /// See [_addOverrides] for how the edit is merged into an existing file.
  PubspecOverridesEdit addLinkOverrides({
    required Directory projectDir,
    required Map<String, String> pathsByDependency,
  }) {
    return _addOverrides(
      projectDir: projectDir,
      specsByDependency: <String, String>{
        for (final entry in pathsByDependency.entries)
          entry.key: 'link:${entry.value}',
      },
    );
  }

  /// Computes the edit that declares [gitSpecsByDependency] (dependency name
  /// → `git+…#ref` spec) as overrides.
  ///
  /// The result is the shape [removeOwnedOverrides] recognizes again, so
  /// `change-refs-to-pub-dev` can drop exactly these entries later. See
  /// [_addOverrides] for how the edit is merged into an existing file.
  PubspecOverridesEdit addGitOverrides({
    required Directory projectDir,
    required Map<String, String> gitSpecsByDependency,
  }) {
    return _addOverrides(
      projectDir: projectDir,
      specsByDependency: gitSpecsByDependency,
    );
  }

  /// Computes the edit that declares [specsByDependency] in the `overrides`
  /// section of the `pnpm-workspace.yaml` of [projectDir].
  ///
  /// [_addOverrides] merges into an existing file: foreign settings
  /// (`allowBuilds`, `packages`, …) and hand written override entries
  /// survive, an override this package owns for a dependency that left the
  /// workspace is pruned. Returns an unchanged edit when every dependency is
  /// already overridden with exactly that spec, so running a command twice
  /// is a no-op.
  PubspecOverridesEdit _addOverrides({
    required Directory projectDir,
    required Map<String, String> specsByDependency,
  }) {
    if (specsByDependency.isEmpty) {
      return const PubspecOverridesEdit.unchanged();
    }

    final overridesFile = file(projectDir);
    final existing = overridesFile.existsSync()
        ? overridesFile.readAsStringSync()
        : null;
    final parsed = existing == null
        ? null
        : _parseOrThrow(existing, overridesFile);
    final section = parsed is Map ? parsed['overrides'] : null;

    // An override this package wrote for a dependency that is no longer part
    // of the workspace set must go — pnpm fails hard on a `link:` whose
    // target is gone, and a stale git pin would silently shadow the restored
    // constraint.
    final stale = <String>[
      if (section is Map)
        for (final entry in section.entries)
          if (!specsByDependency.containsKey(entry.key.toString()) &&
              (isOwnedLinkOverride(
                    projectDir: projectDir,
                    name: entry.key.toString(),
                    value: entry.value,
                  ) ||
                  _isDeadLinkOverride(
                    projectDir: projectDir,
                    value: entry.value,
                  )))
            entry.key.toString(),
    ];

    if (stale.isEmpty &&
        section is Map &&
        specsByDependency.entries.every(
          (entry) => section[entry.key] == entry.value,
        )) {
      return const PubspecOverridesEdit.unchanged();
    }

    // A missing, empty or comment-only file has no map to merge into. Build
    // the document from scratch and put the header on top — it is what marks
    // the file as deletable again once the last override is removed.
    if (parsed is! Map) {
      final editor = YamlEditor('');
      editor.update(<Object>[], <String, dynamic>{
        'overrides': specsByDependency,
      });
      return PubspecOverridesEdit.write(
        _withTrailingNewline('$headerComment$editor'),
      );
    }

    final editor = YamlEditor(existing!);
    if (section is! Map) {
      // The key is absent or has a null value: yaml_edit cannot address
      // children of a scalar, so the whole section is written at once.
      editor.update(<Object>['overrides'], specsByDependency);
    } else {
      for (final entry in specsByDependency.entries) {
        editor.update(<Object>['overrides', entry.key], entry.value);
      }
      for (final name in stale) {
        editor.remove(<Object>['overrides', name]);
      }
    }

    final updated = _withTrailingNewline(editor.toString());
    return updated == existing
        ? const PubspecOverridesEdit.unchanged()
        : PubspecOverridesEdit.write(updated);
  }

  // ...........................................................................
  /// Computes the edit that removes the overrides this package owns from the
  /// `pnpm-workspace.yaml` of [projectDir].
  ///
  /// Removed are the `link:` overrides of [dependencyNames] plus every other
  /// entry that links a sibling checkout of the same name (see
  /// [isOwnedLinkOverride]) — a dependency that was dropped from the
  /// manifest must not stay overridden — and the git overrides of
  /// [dependencyNames] (see [TypeScriptNpmSpec.isGitSpec]; requiring the
  /// name keeps a hand written git pin for a foreign package alive). A hand
  /// written override such as a version constraint is left alone.
  ///
  /// With [restrictToNames] the sweep of the other owned entries is skipped:
  /// only the overrides of [dependencyNames] are removed. A caller that
  /// retires a single dependency — `gg do rm repo`, which drops the repo
  /// that just left the ticket — must not take the still-linked siblings of
  /// the remaining repos with it, and those are owned link overrides too.
  ///
  /// An empty `overrides` section is dropped entirely. The file is deleted
  /// only when this package created it — recognized by [headerComment] —
  /// and nothing else is left in it; an existing settings file keeps its
  /// `allowBuilds` & co. untouched.
  PubspecOverridesEdit removeOwnedOverrides({
    required Directory projectDir,
    required Iterable<String> dependencyNames,
    bool restrictToNames = false,
  }) {
    final overridesFile = file(projectDir);
    if (!overridesFile.existsSync()) {
      return const PubspecOverridesEdit.unchanged();
    }

    final existing = overridesFile.readAsStringSync();
    final parsed = _parseOrThrow(existing, overridesFile);
    final section = parsed is Map ? parsed['overrides'] : null;

    if (section is! Map) {
      return _deleteWhenOwnAndEmpty(existing, parsed);
    }

    final names = dependencyNames.toSet();
    final toRemove = <String>[
      for (final entry in section.entries)
        if (_isLinkOverride(entry.value) &&
                (names.contains(entry.key.toString()) ||
                    (!restrictToNames &&
                        (isOwnedLinkOverride(
                              projectDir: projectDir,
                              name: entry.key.toString(),
                              value: entry.value,
                            ) ||
                            _isDeadLinkOverride(
                              projectDir: projectDir,
                              value: entry.value,
                            )))) ||
            (names.contains(entry.key.toString()) &&
                entry.value is String &&
                TypeScriptNpmSpec.isGitSpec(entry.value as String)))
          entry.key.toString(),
    ];

    if (toRemove.isEmpty) {
      return _deleteWhenOwnAndEmpty(existing, parsed);
    }

    final editor = YamlEditor(existing);
    if (toRemove.length == section.length) {
      // Nothing would be left to override — an empty `overrides` mapping is
      // noise, so the whole section goes.
      editor.remove(<Object>['overrides']);
    } else {
      for (final name in toRemove) {
        editor.remove(<Object>['overrides', name]);
      }
    }

    final updated = editor.toString();
    final edit = _deleteWhenOwnAndEmpty(
      existing,
      _parseOrThrow(updated, overridesFile),
    );
    if (edit.deleteFile) {
      return edit;
    }

    return PubspecOverridesEdit.write(_withTrailingNewline(updated));
  }

  /// Returns a delete edit when [parsed] carries nothing worth keeping and
  /// [existing] starts with [headerComment] — the file was created by this
  /// package. Everything else stays unchanged.
  PubspecOverridesEdit _deleteWhenOwnAndEmpty(String existing, dynamic parsed) {
    if (!existing.startsWith(headerComment)) {
      return const PubspecOverridesEdit.unchanged();
    }

    if (parsed == null) {
      return const PubspecOverridesEdit.delete();
    }
    if (parsed is! Map) {
      return const PubspecOverridesEdit.unchanged();
    }
    if (parsed.isEmpty) {
      return const PubspecOverridesEdit.delete();
    }
    if (parsed.length > 1 || !parsed.containsKey('overrides')) {
      return const PubspecOverridesEdit.unchanged();
    }

    final section = parsed['overrides'];
    return section == null || (section is Map && section.isEmpty)
        ? const PubspecOverridesEdit.delete()
        : const PubspecOverridesEdit.unchanged();
  }

  // ...........................................................................
  /// Returns whether the override [name] → [value] looks like one this
  /// package writes: a `link:` pointing at a sibling checkout of
  /// [projectDir] whose package name is [name].
  ///
  /// pnpm accepts no marker key inside `overrides`, so ownership is derived
  /// from the shape of the entry — the same way the Dart side recognizes its
  /// `path:` overrides.
  bool isOwnedLinkOverride({
    required Directory projectDir,
    required String name,
    required dynamic value,
  }) {
    final target = _siblingLinkTarget(projectDir: projectDir, value: value);
    if (target == null) {
      return false;
    }

    final packageJson = File(p.join(target, 'package.json'));
    if (!packageJson.existsSync()) {
      return false;
    }

    try {
      final parsed = jsonDecode(packageJson.readAsStringSync());
      return parsed is Map && parsed['name'] == name;
    } catch (_) {
      return false;
    }
  }

  /// Returns whether [value] is a `link:` override pointing at a **missing
  /// sibling** of [projectDir].
  ///
  /// That is the exact shape this package writes, so the entry is ours even
  /// though ownership cannot be proven anymore — the package name it would
  /// have to match is unreadable once the checkout is gone. Keeping it is
  /// not an option: pnpm fails hard on the dangling symlink target, and as
  /// long as the entry stays the workspace can never leave local mode. A
  /// link reaching further out (a vendored `../../vendor/x`) is left alone.
  bool _isDeadLinkOverride({
    required Directory projectDir,
    required dynamic value,
  }) {
    final target = _siblingLinkTarget(projectDir: projectDir, value: value);
    return target != null && !Directory(target).existsSync();
  }

  /// Returns the normalized target path of a `link:`/`file:` override
  /// [value] when it points at a **sibling** of [projectDir], else null.
  String? _siblingLinkTarget({
    required Directory projectDir,
    required dynamic value,
  }) {
    if (!_isLinkOverride(value)) {
      return null;
    }

    final linkPath = (value as String).trim().replaceFirst(
      RegExp('^(link|file):'),
      '',
    );
    final projectPath = p.normalize(projectDir.absolute.path);
    final targetPath = p.normalize(p.join(projectPath, linkPath));
    if (p.dirname(targetPath) != p.dirname(projectPath)) {
      return null;
    }

    return targetPath;
  }

  /// Returns whether [value] is an override declaring a local
  /// `link:`/`file:` spec.
  bool _isLinkOverride(dynamic value) {
    return value is String && TypeScriptNpmSpec.isLocalizedSpec(value);
  }

  /// Parses [content] and throws a readable exception when it is not a YAML
  /// map. An empty or comment-only file parses to null and is accepted.
  ///
  /// A file whose root is a list or a scalar is rejected instead of being
  /// overwritten: pnpm would not accept it either, and silently dropping
  /// whatever the author put there is worse than saying so.
  dynamic _parseOrThrow(String content, File overridesFile) {
    final dynamic parsed;
    try {
      parsed = loadYaml(content);
    } catch (e) {
      throw Exception('Cannot parse ${overridesFile.path}: $e');
    }

    if (parsed != null && parsed is! Map) {
      throw Exception(
        'Cannot parse ${overridesFile.path}: expected a YAML map, '
        'got ${parsed.runtimeType}.',
      );
    }

    return parsed;
  }

  /// Returns [content] with exactly one trailing newline.
  String _withTrailingNewline(String content) {
    return content.endsWith('\n') ? content : '$content\n';
  }
}
