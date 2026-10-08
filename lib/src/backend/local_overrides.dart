// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/ts_link_shims.dart';
import 'package:gg_localize_refs/src/backend/typescript_npm_spec.dart';
import 'package:path/path.dart' as p;

/// The references `change-refs-to-local` declares for a project.
///
/// Single source of truth for writing them (`change-refs-to-local`) and for
/// checking them (`unlocalized-refs`). Pure: nothing is written here.
class LocalOverrides {
  /// Constructor.
  const LocalOverrides();

  // ...........................................................................
  /// Returns name → `path` override of the `pubspec_overrides.yaml` of
  /// [node], one per *transitive* workspace dependency (pub reads overrides
  /// from the root package only).
  Map<String, String> dartPaths(ProjectNode node) => <String, String>{
    for (final dependency in node.transitiveDependencies.entries)
      dependency.key: _relativePath(
        from: node.directory,
        to: dependency.value.directory,
      ),
  };

  // ...........................................................................
  /// Returns name → `link:` path of the `pnpm-workspace.yaml` of [node], one
  /// per transitive workspace dependency: the shim (see [TsLinkShims]) for a
  /// sibling with sources, else the sibling itself. Writes no shim.
  Map<String, String> pnpmLinkPaths(ProjectNode node) => <String, String>{
    for (final dependency in node.transitiveDependencies.entries)
      dependency.key: TsLinkShims.hasSourceEntry(dependency.value.directory)
          ? TsLinkShims.linkPath(dependency.key)
          : _relativePath(from: node.directory, to: dependency.value.directory),
  };

  // ...........................................................................
  /// Returns name → `link:` spec the `package.json` of a legacy npm [node]
  /// declares, one per *direct* workspace dependency (the specs live in the
  /// real dependency map, extra entries would change it).
  Map<String, String> npmLinkSpecs(ProjectNode node) => <String, String>{
    for (final dependency in node.dependencies.entries)
      dependency.key: _linkSpec(
        from: node.directory,
        to: dependency.value.directory,
      ),
  };

  // ...........................................................................
  /// Returns the direct workspace dependencies of a legacy npm [node] whose
  /// spec in [references] is no `link:`/`file:` to their sibling checkout —
  /// a registry spec or a link pointing somewhere else.
  List<String> unlinkedNpmDependencies({
    required ProjectNode node,
    required Map<String, DependencyReference> references,
  }) => <String>[
    for (final dependency in node.dependencies.entries)
      if (references[dependency.key]?.value?.toString() case final String spec
          when !_linksTo(
            spec: spec,
            from: node.directory,
            to: dependency.value.directory,
          ))
        dependency.key,
  ];

  // ######################
  // Private
  // ######################

  /// Returns the path of [to] relative to [from] with forward slashes, which
  /// pub and pnpm accept on every platform (rebuilt from the split path: a
  /// POSIX directory name may contain a backslash).
  String _relativePath({required Directory from, required Directory to}) {
    final relative = p.relative(to.path, from: from.path);
    return p.posix.joinAll(p.split(relative));
  }

  /// Returns the `link:` spec from [from] to [to].
  String _linkSpec({required Directory from, required Directory to}) =>
      'link:${_relativePath(from: from, to: to)}';

  /// Returns whether [spec] is a `link:`/`file:` spec of the project in
  /// [from] that resolves to [to].
  bool _linksTo({
    required String spec,
    required Directory from,
    required Directory to,
  }) {
    final trimmed = spec.trim();
    if (!TypeScriptNpmSpec.isLocalizedSpec(trimmed)) {
      return false;
    }

    final path = trimmed.replaceFirst(RegExp('^(link|file):'), '');
    return p.equals(
      p.normalize(p.join(from.absolute.path, path)),
      p.normalize(to.absolute.path),
    );
  }
}
