// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/local_overrides.dart';
import 'package:gg_localize_refs/src/backend/manifest_command_support.dart';
import 'package:gg_localize_refs/src/backend/pnpm_workspace_io.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
import 'package:gg_localize_refs/src/backend/ts_link_shims.dart';
import 'package:gg_log/gg_log.dart';

/// Why a workspace reference of a project is out of sync.
enum UnlocalizedRefKind {
  /// A workspace dependency is resolved from the registry, not the sibling.
  missing,

  /// An override still points at a sibling the project no longer needs.
  stale,
}

/// One workspace reference that `change-refs-to-local` would rewrite.
class UnlocalizedRef {
  /// Constructor.
  const UnlocalizedRef({
    required this.project,
    required this.dependency,
    required this.kind,
  });

  /// The project whose overrides are out of sync.
  final String project;

  /// The dependency the override is missing or stale for.
  final String dependency;

  /// Whether the override is missing or stale.
  final UnlocalizedRefKind kind;

  @override
  String toString() => switch (kind) {
    UnlocalizedRefKind.missing =>
      '$project uses the published $dependency instead of its checkout',
    UnlocalizedRefKind.stale =>
      '$project still overrides $dependency, which it no longer needs',
  };
}

/// Lists the workspace references of a project that are not localized.
/// Read-only counterpart of `change-refs-to-local`: an empty result means
/// running it would change none of the project's references.
class UnlocalizedRefs extends DirCommand<List<UnlocalizedRef>> {
  /// Constructor.
  UnlocalizedRefs({required super.ggLog})
    : super(
        name: 'unlocalized-refs',
        description: 'Lists the workspace refs that are not localized',
      );

  // ...........................................................................
  /// Checks the ROOT project of [directory], every language of a bridge,
  /// against what `change-refs-to-local` writes for it (see
  /// [LocalOverrides]), the shims of `.gg/ts_links` included.
  @override
  Future<List<UnlocalizedRef>> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final result = <UnlocalizedRef>[];
    for (final graph in await buildRootGraphs(
      directory: directory,
      ggLog: ggLog,
    )) {
      result.addAll(await _check(graph.rootNode));
    }
    return result;
  }

  // ...........................................................................
  /// Logs one line per unlocalized ref and throws when there is any.
  @override
  Future<List<UnlocalizedRef>> exec({
    required Directory directory,
    required GgLog ggLog,
    Map<String, dynamic> options = const <String, dynamic>{},
  }) async {
    final refs = await get(directory: directory, ggLog: ggLog);
    if (refs.isEmpty) {
      ggLog('All workspace refs are localized.');
      return refs;
    }

    for (final ref in refs) {
      ggLog(ref.toString());
    }
    throw Exception(
      red('${refs.length} workspace ref(s) are not localized. ') +
          yellow('Run change-refs-to-local to fix it.'),
    );
  }

  // ######################
  // Private
  // ######################

  final ManifestCommandSupport _support = const ManifestCommandSupport();

  final LocalOverrides _localOverrides = const LocalOverrides();

  // ...........................................................................
  /// Returns the unlocalized refs of [node] in its own language.
  Future<List<UnlocalizedRef>> _check(ProjectNode node) async {
    final manifest = await node.language.readManifest(node.directory);

    // Like processNode: change-refs-to-local skips a project without deps.
    if (!node.language.hasAnyDependencyEntries(manifest.parsed)) {
      return const <UnlocalizedRef>[];
    }

    final ({List<String> missing, List<String> stale}) diff;
    if (node.language.id == ProjectLanguageId.dart) {
      diff = const PubspecOverridesIo().diffPathOverrides(
        projectDir: node.directory,
        pathsByDependency: _localOverrides.dartPaths(node),
        inheritedOverrides: _support.dependencyOverridesOf(manifest.parsed),
      );
    } else if (PnpmWorkspaceIo.isPnpmManaged(node.directory)) {
      final yamlDiff = const PnpmWorkspaceIo().diffLinkOverrides(
        projectDir: node.directory,
        pathsByDependency: _localOverrides.pnpmLinkPaths(node),
      );
      diff = (
        missing: <String>[
          for (final dependency in node.transitiveDependencies.entries)
            if (yamlDiff.missing.contains(dependency.key) ||
                _isShimOutdated(node, dependency.key, dependency.value))
              dependency.key,
        ],
        stale: yamlDiff.stale,
      );
    } else {
      // Legacy npm: the `link:` specs live in package.json itself.
      diff = (
        missing: _localOverrides.unlinkedNpmDependencies(
          node: node,
          references: _support.referencesFor(node, manifest.parsed),
        ),
        stale: const <String>[],
      );
    }

    return <UnlocalizedRef>[
      for (final name in diff.missing)
        UnlocalizedRef(
          project: node.name,
          dependency: name,
          kind: UnlocalizedRefKind.missing,
        ),
      for (final name in diff.stale)
        UnlocalizedRef(
          project: node.name,
          dependency: name,
          kind: UnlocalizedRefKind.stale,
        ),
    ];
  }

  // ...........................................................................
  /// Returns whether the shim of [name] that `change-refs-to-local` would
  /// write for [dependency] is missing or outdated (fresh clone, git clean).
  bool _isShimOutdated(ProjectNode node, String name, ProjectNode dependency) =>
      TsLinkShims.hasSourceEntry(dependency.directory) &&
      !const TsLinkShims().isInSync(
        projectDir: node.directory,
        name: name,
        depDir: dependency.directory,
      );
}

/// Mock for [UnlocalizedRefs].
class MockUnlocalizedRefs extends MockDirCommand<List<UnlocalizedRef>>
    implements UnlocalizedRefs {}
