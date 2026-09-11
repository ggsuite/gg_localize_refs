// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
import 'package:path/path.dart' as p;

/// Reads and edits the `paths` of a `tsconfig.workspace.json`.
///
/// A pnpm `link:` override (see `PnpmWorkspaceIo`) makes the *installed*
/// dependency point at the sibling checkout — but the consumer still enters
/// it through the `main`/`types` fields of the sibling's `package.json`,
/// i.e. through its compiled `dist/`. That output does not exist in a fresh
/// checkout, goes stale with every edit of the sibling, and carries no
/// source map by default: a test that steps into the dependency lands in
/// generated JavaScript, and a breakpoint set in the sibling's TypeScript
/// source is never hit.
///
/// The `paths` of the TypeScript compiler options fix that at the source
/// level: `"<name>": ["../<repo>/src/index.ts"]` makes `tsc`, the editor and
/// — via Vite's `resolve.tsconfigPaths` — vitest resolve the dependency to
/// the sibling's source. Edits are picked up immediately, stack traces name
/// the `.ts` file, breakpoints in the sibling hit.
///
/// The entries live in `tsconfig.workspace.json`, a file this package owns,
/// which the project's `tsconfig.json` has to pull in via `"extends":
/// "./tsconfig.workspace.json"`. `tsconfig.json` itself is left alone: it is
/// JSON with comments, and rewriting it would cost every comment the author
/// put there. A project whose `tsconfig.json` does not extend the file is
/// skipped — writing `paths` nobody reads would only mislead.
///
/// Like the overrides of `pnpm-workspace.yaml` the file carries relative
/// paths only, so it travels with a shared ticket and is committed there.
/// `change-refs-to-pub-dev` empties the `paths` again; the file itself stays,
/// because `tsconfig.json` keeps extending it.
class TsconfigWorkspaceIo {
  /// Creates the io helper.
  const TsconfigWorkspaceIo();

  /// The name of the file holding the workspace `paths`.
  static const String fileName = 'tsconfig.workspace.json';

  /// The TypeScript config that has to extend [fileName].
  static const String tsconfigFileName = 'tsconfig.json';

  /// The entry file of a sibling checkout the `paths` point at.
  static const String sourceEntry = 'src/index.ts';

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  /// Returns the `tsconfig.workspace.json` of the project in [projectDir].
  File file(Directory projectDir) => File(p.join(projectDir.path, fileName));

  // ...........................................................................
  /// Returns whether the `tsconfig.json` of [projectDir] extends
  /// [fileName].
  ///
  /// Both the single `"extends": "./tsconfig.workspace.json"` and the array
  /// form TypeScript ≥ 5 accepts are recognized. A missing or unparsable
  /// `tsconfig.json` counts as »not extended«.
  static bool isExtended(Directory projectDir) {
    final tsconfig = File(p.join(projectDir.path, tsconfigFileName));
    if (!tsconfig.existsSync()) {
      return false;
    }

    final dynamic parsed;
    try {
      parsed = parseJsonc(tsconfig.readAsStringSync());
    } catch (_) {
      return false;
    }
    if (parsed is! Map) {
      return false;
    }

    final extendsValue = parsed['extends'];
    final targets = extendsValue is List
        ? extendsValue
        : <dynamic>[extendsValue];
    return targets.any(
      (dynamic target) =>
          target is String && p.posix.normalize(target.trim()) == fileName,
    );
  }

  // ...........................................................................
  /// Returns whether the `tsconfig.workspace.json` of [projectDir] still
  /// maps at least one dependency to a sibling source tree.
  ///
  /// A missing file, one without `paths` and one holding only hand written
  /// mappings all count as »no localized refs«. An unparsable file counts as
  /// localized — it cannot prove the opposite.
  static bool hasLocalizedRefs(Directory projectDir) {
    final workspaceFile = File(p.join(projectDir.path, fileName));
    if (!workspaceFile.existsSync()) {
      return false;
    }

    final dynamic parsed;
    try {
      parsed = parseJsonc(workspaceFile.readAsStringSync());
    } catch (_) {
      return true;
    }

    final paths = _pathsOf(parsed);
    if (paths == null) {
      return false;
    }

    const io = TsconfigWorkspaceIo();
    return paths.entries.any(
      (entry) =>
          io.isOwnedPath(
            projectDir: projectDir,
            name: entry.key.toString(),
            value: entry.value,
          ) ||
          io._isDeadPath(projectDir: projectDir, value: entry.value),
    );
  }

  // ...........................................................................
  /// Computes the edit that maps every entry of [pathsByDependency]
  /// (dependency name → directory of the sibling checkout, relative to
  /// [projectDir]) to the sibling's [sourceEntry].
  ///
  /// Only siblings that actually carry a `src/index.ts` are mapped: a
  /// dependency without one keeps resolving through its `package.json`.
  ///
  /// The edit merges into an existing file: foreign compiler options and
  /// hand written `paths` survive, a mapping this package owns for a
  /// dependency that left the workspace is pruned. Returns an unchanged edit
  /// when every dependency is already mapped exactly like that, so running
  /// a command twice is a no-op. Returns an unchanged edit as well when the
  /// project's `tsconfig.json` does not extend the file (see [isExtended]).
  PubspecOverridesEdit addSourcePaths({
    required Directory projectDir,
    required Map<String, String> pathsByDependency,
  }) {
    if (!isExtended(projectDir)) {
      return const PubspecOverridesEdit.unchanged();
    }

    final mappings = <String, List<String>>{
      for (final entry in pathsByDependency.entries)
        if (File(p.join(projectDir.path, entry.value, sourceEntry))
            .existsSync())
          entry.key: <String>[p.posix.join(entry.value, sourceEntry)],
    };

    final workspaceFile = file(projectDir);
    final existing = workspaceFile.existsSync()
        ? workspaceFile.readAsStringSync()
        : null;
    final root = existing == null
        ? <String, dynamic>{}
        : _parseOrThrow(existing, workspaceFile);
    final compilerOptions = _compilerOptionsOf(root);
    final paths = _mutablePathsOf(compilerOptions);

    // A mapping this package wrote for a dependency that is no longer part
    // of the workspace set must go: TypeScript falls back to the regular
    // resolution for a missing target, but the editor keeps showing the
    // stale path and every `tsc` run reports it.
    final stale = <String>[
      for (final entry in paths.entries)
        if (!mappings.containsKey(entry.key) &&
            (isOwnedPath(
                  projectDir: projectDir,
                  name: entry.key,
                  value: entry.value,
                ) ||
                _isDeadPath(projectDir: projectDir, value: entry.value)))
          entry.key,
    ];

    if (stale.isEmpty &&
        mappings.entries.every(
          (entry) => _sameMapping(paths[entry.key], entry.value),
        )) {
      return const PubspecOverridesEdit.unchanged();
    }

    for (final name in stale) {
      paths.remove(name);
    }
    paths.addAll(mappings);
    compilerOptions['paths'] = paths;
    root['compilerOptions'] = compilerOptions;

    final updated = _encode(root);
    return updated == existing
        ? const PubspecOverridesEdit.unchanged()
        : PubspecOverridesEdit.write(updated);
  }

  // ...........................................................................
  /// Computes the edit that removes the mappings this package owns from the
  /// `tsconfig.workspace.json` of [projectDir].
  ///
  /// Removed are the mappings of [dependencyNames] plus every other entry
  /// pointing at the source of a sibling checkout of the same name (see
  /// [isOwnedPath]) or at a sibling that is gone. A hand written mapping is
  /// left alone.
  ///
  /// With [restrictToNames] the sweep of the other owned entries is skipped:
  /// only the mappings of [dependencyNames] are removed. A caller that
  /// retires a single dependency — `gg do rm repo` — must not take the
  /// still-linked siblings of the remaining repos with it.
  ///
  /// The `paths` are emptied, never dropped: `tsconfig.json` keeps extending
  /// the file, and an `extends` target without `paths` reads odd where the
  /// template ships `"paths": {}`. The file is deleted only when nothing but
  /// empty `paths` is left in it and no `tsconfig.json` extends it anymore.
  PubspecOverridesEdit removeOwnedPaths({
    required Directory projectDir,
    required Iterable<String> dependencyNames,
    bool restrictToNames = false,
  }) {
    final workspaceFile = file(projectDir);
    if (!workspaceFile.existsSync()) {
      return const PubspecOverridesEdit.unchanged();
    }

    final existing = workspaceFile.readAsStringSync();
    final root = _parseOrThrow(existing, workspaceFile);
    final compilerOptions = _compilerOptionsOf(root);
    final paths = _mutablePathsOf(compilerOptions);

    final names = dependencyNames.toSet();
    final toRemove = <String>[
      for (final entry in paths.entries)
        if (names.contains(entry.key) &&
                (isOwnedPath(
                      projectDir: projectDir,
                      name: entry.key,
                      value: entry.value,
                    ) ||
                    _isDeadPath(projectDir: projectDir, value: entry.value)) ||
            (!restrictToNames &&
                (isOwnedPath(
                      projectDir: projectDir,
                      name: entry.key,
                      value: entry.value,
                    ) ||
                    _isDeadPath(projectDir: projectDir, value: entry.value))))
          entry.key,
    ];

    if (toRemove.isEmpty) {
      return _deleteWhenUnreferencedAndEmpty(projectDir, root);
    }

    for (final name in toRemove) {
      paths.remove(name);
    }
    compilerOptions['paths'] = paths;
    root['compilerOptions'] = compilerOptions;

    final edit = _deleteWhenUnreferencedAndEmpty(projectDir, root);
    if (edit.deleteFile) {
      return edit;
    }

    return PubspecOverridesEdit.write(_encode(root));
  }

  // ...........................................................................
  /// Returns whether the mapping [name] → [value] looks like one this
  /// package writes: a single path ending in [sourceEntry] whose package
  /// directory is a sibling of [projectDir] with a `package.json` named
  /// [name].
  ///
  /// `paths` has no room for a marker, so ownership is derived from the
  /// shape of the entry — the same way the pnpm side recognizes its `link:`
  /// overrides.
  bool isOwnedPath({
    required Directory projectDir,
    required String name,
    required dynamic value,
  }) {
    final target = _siblingSourceTarget(projectDir: projectDir, value: value);
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

  /// Returns whether [value] maps to the [sourceEntry] of a **missing
  /// sibling** of [projectDir] — the shape this package writes, whose
  /// ownership cannot be proven anymore once the checkout is gone.
  bool _isDeadPath({required Directory projectDir, required dynamic value}) {
    final target = _siblingSourceTarget(projectDir: projectDir, value: value);
    return target != null && !Directory(target).existsSync();
  }

  /// Returns the normalized directory of the sibling checkout a mapping
  /// [value] points at — when it is a single path ending in [sourceEntry]
  /// whose package directory is a **sibling** of [projectDir] — else null.
  String? _siblingSourceTarget({
    required Directory projectDir,
    required dynamic value,
  }) {
    if (value is! List || value.length != 1 || value.single is! String) {
      return null;
    }

    final mapped = p.posix.normalize((value.single as String).trim());
    if (mapped != sourceEntry && !mapped.endsWith('/$sourceEntry')) {
      return null;
    }

    final relativeDir = mapped == sourceEntry
        ? '.'
        : mapped.substring(0, mapped.length - sourceEntry.length - 1);
    final projectPath = p.normalize(projectDir.absolute.path);
    final targetPath = p.normalize(p.join(projectPath, relativeDir));
    if (p.dirname(targetPath) != p.dirname(projectPath)) {
      return null;
    }

    return targetPath;
  }

  /// Returns a delete edit when [root] carries nothing but empty `paths`
  /// and no `tsconfig.json` of [projectDir] extends the file anymore.
  PubspecOverridesEdit _deleteWhenUnreferencedAndEmpty(
    Directory projectDir,
    Map<String, dynamic> root,
  ) {
    if (isExtended(projectDir)) {
      return const PubspecOverridesEdit.unchanged();
    }

    if (root.isEmpty) {
      return const PubspecOverridesEdit.delete();
    }
    if (root.length > 1 || !root.containsKey('compilerOptions')) {
      return const PubspecOverridesEdit.unchanged();
    }

    final compilerOptions = root['compilerOptions'];
    if (compilerOptions is! Map) {
      return const PubspecOverridesEdit.unchanged();
    }
    if (compilerOptions.isEmpty) {
      return const PubspecOverridesEdit.delete();
    }
    if (compilerOptions.length > 1 || !compilerOptions.containsKey('paths')) {
      return const PubspecOverridesEdit.unchanged();
    }

    final paths = compilerOptions['paths'];
    return paths == null || (paths is Map && paths.isEmpty)
        ? const PubspecOverridesEdit.delete()
        : const PubspecOverridesEdit.unchanged();
  }

  /// Returns whether [existing] already is the mapping [wanted].
  bool _sameMapping(dynamic existing, List<String> wanted) {
    if (existing is! List || existing.length != wanted.length) {
      return false;
    }
    for (var i = 0; i < wanted.length; i++) {
      if (existing[i] != wanted[i]) {
        return false;
      }
    }
    return true;
  }

  /// Returns the `paths` map of a parsed config, or null when absent.
  static Map<dynamic, dynamic>? _pathsOf(dynamic root) {
    if (root is! Map) {
      return null;
    }
    final compilerOptions = root['compilerOptions'];
    if (compilerOptions is! Map) {
      return null;
    }
    final paths = compilerOptions['paths'];
    return paths is Map ? paths : null;
  }

  /// Returns the `compilerOptions` of [root] as a mutable map — a fresh one
  /// when absent. A non-map value is replaced: TypeScript would reject it
  /// anyway.
  Map<String, dynamic> _compilerOptionsOf(Map<String, dynamic> root) {
    final section = root['compilerOptions'];
    return section is Map
        ? Map<String, dynamic>.from(section)
        : <String, dynamic>{};
  }

  /// Returns the `paths` of [compilerOptions] as a mutable map — a fresh
  /// one when absent or not a map.
  Map<String, dynamic> _mutablePathsOf(Map<String, dynamic> compilerOptions) {
    final section = compilerOptions['paths'];
    return section is Map
        ? Map<String, dynamic>.from(section)
        : <String, dynamic>{};
  }

  /// Parses [content] and throws a readable exception when it is not a JSON
  /// object. An empty file is accepted and treated as an empty object.
  Map<String, dynamic> _parseOrThrow(String content, File workspaceFile) {
    if (content.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final dynamic parsed;
    try {
      parsed = parseJsonc(content);
    } catch (e) {
      throw Exception('Cannot parse ${workspaceFile.path}: $e');
    }

    if (parsed is! Map) {
      throw Exception(
        'Cannot parse ${workspaceFile.path}: expected a JSON object, '
        'got ${parsed.runtimeType}.',
      );
    }

    return Map<String, dynamic>.from(parsed);
  }

  /// Serializes [root] with two-space indentation and a trailing newline.
  String _encode(Map<String, dynamic> root) => '${_encoder.convert(root)}\n';
}

// #############################################################################
/// Parses [content] as JSON with comments — the dialect `tsconfig.json`
/// is written in.
///
/// Line comments (`// …`), block comments (`/* … */`) and trailing commas
/// before a closing bracket are dropped; everything inside a string literal
/// is kept verbatim. The remainder is handed to [jsonDecode], so a file
/// that is not JSON underneath throws a [FormatException] like any other
/// broken JSON.
dynamic parseJsonc(String content) {
  final out = <String>[];
  var i = 0;

  while (i < content.length) {
    final char = content[i];

    // A string literal is copied as it is, escapes included.
    if (char == '"') {
      final start = i;
      i++;
      while (i < content.length) {
        if (content[i] == r'\') {
          i += 2;
          continue;
        }
        if (content[i] == '"') {
          i++;
          break;
        }
        i++;
      }
      out.add(content.substring(start, i));
      continue;
    }

    if (char == '/' && i + 1 < content.length) {
      final next = content[i + 1];
      if (next == '/') {
        i += 2;
        while (i < content.length && content[i] != '\n') {
          i++;
        }
        continue;
      }
      if (next == '*') {
        final end = content.indexOf('*/', i + 2);
        i = end == -1 ? content.length : end + 2;
        continue;
      }
    }

    // A trailing comma — one followed by nothing but whitespace and
    // comments up to the closing bracket — is not JSON, but every
    // tsconfig.json reader accepts it. Drop it once the bracket shows up.
    if (char == '}' || char == ']') {
      var last = out.length - 1;
      while (last >= 0 && out[last].trim().isEmpty) {
        last--;
      }
      if (last >= 0 && out[last] == ',') {
        out.removeAt(last);
      }
    }

    out.add(char);
    i++;
  }

  return jsonDecode(out.join());
}
