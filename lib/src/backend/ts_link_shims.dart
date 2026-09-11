// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:path/path.dart' as p;

/// Writes and removes the shim packages a localized TypeScript project links
/// its workspace dependencies through.
///
/// A pnpm `link:` straight to the sibling checkout redirects the *installed*
/// dependency — but the consumer still enters it through the `main`/`types`
/// of the sibling's `package.json`, i.e. its compiled `dist/`. That output
/// is missing in a fresh checkout, goes stale with every edit of the sibling
/// and carries no source map by default: a test stepping into the dependency
/// lands in generated JavaScript, a breakpoint in the sibling's TypeScript
/// never hits.
///
/// So the `link:` points at a shim instead: `.gg/ts_links/<name>/` holds a
/// `package.json` whose `main` and `types` are `./src/index.ts`, and `src`
/// is a symlink to the sibling's `src/`. Every resolver that follows the
/// link — vitest, `tsc`, the editor — ends up in the sibling's source:
/// edits are picked up immediately, stack traces name the `.ts` file,
/// breakpoints in the sibling hit. Nothing in the consumer or the sibling
/// has to be configured for it, which is what makes it work for any repo
/// added to a ticket.
///
/// The `src` link is what keeps the two resolvers in agreement: TypeScript
/// resolves `main`/`types` relative to the path *inside* `node_modules`,
/// Vite relative to the real location of the shim. A relative path escaping
/// the shim would mean different things to them; `./src/index.ts` means the
/// same to both, and the link's absolute target is followed by the OS.
///
/// The shims are machine-local helper files: they live in `.gg/`, which is
/// gitignored, and every localizing run rewrites them. Only a sibling that
/// has a `src/index.ts` gets one — anything else keeps the plain `link:` to
/// the sibling checkout.
class TsLinkShims {
  /// Creates the shim helper.
  const TsLinkShims();

  /// The folder below `.gg` holding the shims, one subfolder per package.
  static const String dirName = 'ts_links';

  /// The entry file of a sibling the shim points at.
  static const String sourceEntry = 'src/index.ts';

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  /// Returns the folder holding all shims of the project in [projectDir].
  Directory root(Directory projectDir) =>
      Directory(p.join(Utils.dartBackupDir(projectDir).path, dirName));

  /// Returns the shim folder of the package [name] in [projectDir].
  ///
  /// A scoped name (`@scope/pkg`) becomes a nested folder, the same shape
  /// pnpm gives it below `node_modules`.
  Directory shimDir(Directory projectDir, String name) =>
      Directory(p.joinAll(<String>[root(projectDir).path, ...name.split('/')]));

  /// Returns the `link:` path of the shim of [name], relative to the project
  /// — the value that goes into the overrides of `pnpm-workspace.yaml`.
  static String linkPath(String name) => './.gg/$dirName/$name';

  /// Returns whether [depDir] carries a [sourceEntry] a shim can point at.
  static bool hasSourceEntry(Directory depDir) =>
      File(p.join(depDir.path, sourceEntry)).existsSync();

  // ...........................................................................
  /// Writes the shim of [name] in [projectDir], pointing at the `src/` of
  /// [depDir]. Returns whether anything on disk changed.
  ///
  /// An existing shim is refreshed in place: the `src` link is recreated
  /// when it points elsewhere, the `package.json` rewritten when its content
  /// differs. Running it twice is a no-op.
  bool write({
    required Directory projectDir,
    required String name,
    required Directory depDir,
  }) {
    final dir = shimDir(projectDir, name);
    var changed = false;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      changed = true;
    }

    final target = p.normalize(p.join(depDir.absolute.path, 'src'));
    final link = Link(p.join(dir.path, 'src'));
    if (link.existsSync()) {
      if (p.normalize(link.targetSync()) != target) {
        link.deleteSync();
        link.createSync(target);
        changed = true;
      }
    } else {
      // A plain folder or file in the way is not ours; it goes.
      final blocker = FileSystemEntity.typeSync(link.path, followLinks: false);
      if (blocker == FileSystemEntityType.directory) {
        Directory(link.path).deleteSync(recursive: true);
      } else if (blocker != FileSystemEntityType.notFound) {
        File(link.path).deleteSync();
      }
      link.createSync(target);
      changed = true;
    }

    final packageJson = File(p.join(dir.path, 'package.json'));
    final content = _packageJsonContent(name: name, depDir: depDir);
    if (!packageJson.existsSync() ||
        packageJson.readAsStringSync() != content) {
      packageJson.writeAsStringSync(content);
      changed = true;
    }

    return changed;
  }

  /// Removes the shim of [name] from [projectDir]. Returns whether it
  /// existed. Empty scope folders left behind are removed as well.
  bool remove({required Directory projectDir, required String name}) {
    final dir = shimDir(projectDir, name);
    if (!dir.existsSync()) {
      return false;
    }
    dir.deleteSync(recursive: true);

    final scopeDir = dir.parent;
    final rootDir = root(projectDir);
    if (!p.equals(scopeDir.path, rootDir.path) &&
        scopeDir.existsSync() &&
        scopeDir.listSync().isEmpty) {
      scopeDir.deleteSync();
    }
    return true;
  }

  /// Removes every shim of [projectDir]. Returns whether there was any.
  bool removeAll(Directory projectDir) {
    final dir = root(projectDir);
    if (!dir.existsSync()) {
      return false;
    }
    dir.deleteSync(recursive: true);
    return true;
  }

  /// Returns the package name a shim folder [target] of [projectDir] stands
  /// for, or null when [target] is no shim folder of that project.
  ///
  /// [target] is an absolute, normalized path — e.g. the resolved target of
  /// a `link:` override. The name is read from the folder structure, not
  /// from the `package.json`, so a shim whose files are gone is still
  /// recognized.
  static String? shimNameOf({
    required Directory projectDir,
    required String target,
  }) {
    final rootPath = p.normalize(
      const TsLinkShims().root(projectDir).absolute.path,
    );
    if (!p.isWithin(rootPath, target)) {
      return null;
    }
    // isWithin is false for the root itself, so relative is never '.'.
    final segments = p.split(p.relative(target, from: rootPath));
    if (segments.length > 2) {
      return null;
    }
    if (segments.length == 2 && !segments.first.startsWith('@')) {
      return null;
    }
    return segments.join('/');
  }

  /// Builds the `package.json` of the shim of [name].
  ///
  /// `type` is copied from the sibling so a `.ts` entry is parsed the way
  /// the sibling expects; ES modules are the default of the toolchain.
  String _packageJsonContent({
    required String name,
    required Directory depDir,
  }) {
    var type = 'module';
    final depManifest = File(p.join(depDir.path, 'package.json'));
    if (depManifest.existsSync()) {
      try {
        final parsed = jsonDecode(depManifest.readAsStringSync());
        if (parsed is Map && parsed['type'] is String) {
          type = parsed['type'] as String;
        }
      } catch (_) {
        // An unreadable manifest keeps the default.
      }
    }

    final content = _encoder.convert(<String, Object?>{
      'name': name,
      'type': type,
      'main': './$sourceEntry',
      'types': './$sourceEntry',
      'private': true,
      'description':
          'Generated by gg_localize_refs: resolves $name to the sources of '
          'its sibling checkout. Do not edit, do not commit.',
    });
    return '$content\n';
  }
}
