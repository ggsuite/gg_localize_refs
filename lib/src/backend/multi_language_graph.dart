// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart' as p;

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';

/// Builds a dependency graph for a workspace that may contain projects in
/// different languages.
class MultiLanguageGraph {
  /// Creates a multi language graph.
  MultiLanguageGraph({required this.languages});

  /// The supported project languages.
  final List<ProjectLanguage> languages;

  /// Builds the graph starting at [directory].
  ///
  /// The workspace language is the first registered language whose project
  /// root matches, unless [forLanguage] pins it explicitly. Pass [forLanguage]
  /// to build the graph for one specific language of a multi-language (bridge)
  /// workspace; call once per language to cover both manifests.
  ///
  /// Returns a record containing the root node and all nodes in the workspace.
  Future<({ProjectNode rootNode, Map<String, ProjectNode> allNodes})>
  buildGraph({
    required Directory directory,
    GgLog? ggLog,
    ProjectLanguage? forLanguage,
  }) async {
    final startDir = _correctDir(directory.absolute);

    final rootInfo = await _findProjectRootAndLanguage(startDir, forLanguage);
    if (rootInfo == null) {
      throw Exception(red('No project root found'));
    }

    final rootDir = rootInfo.$1;
    final language = rootInfo.$2;

    final allDirs = projectCandidateDirs(workspaceRootOf(rootDir));

    final nodes = <String, ProjectNode>{};

    for (final dir in allDirs) {
      if (!language.isProjectRoot(dir)) {
        continue;
      }

      final node = await language.createNode(dir);

      if (nodes.containsKey(node.name)) {
        throw Exception('Duplicate package name: ${node.name}');
      }

      nodes[node.name] = node;
    }

    // Resolve dependencies within the workspace.
    for (final node in nodes.values) {
      final declared = await language.readDeclaredDependencies(node);
      for (final entry in declared.entries) {
        final depName = entry.key;
        final depNode = nodes[depName];
        if (depNode == null) {
          continue;
        }
        node.dependencies[depName] = depNode;
        depNode.dependents[node.name] = node;
      }

      final devOnly = await language.readDeclaredDevOnlyDependencies(node);
      node.devOnlyDependencies.addAll(devOnly.where(nodes.containsKey));
    }

    // Detect circular dependencies.
    _checkCircularDependencies(nodes, ggLog);

    ProjectNode? rootNode;
    final normalizedRoot = _correctDir(rootDir).path;
    for (final node in nodes.values) {
      if (_correctDir(node.directory).path == normalizedRoot) {
        rootNode = node;
        break;
      }
    }

    if (rootNode == null) {
      throw Exception(
        'The node for the package '
        '${rootDir.path.split(ggPlatform.pathSeparator).last} was not found.',
      );
    }

    return (rootNode: rootNode, allNodes: nodes);
  }

  /// Finds the nearest ancestor of [directory] (including itself) that is a
  /// project root for at least one registered language, and returns it
  /// together with EVERY language that recognizes it.
  ///
  /// A cross-language bridge (pubspec.yaml + package.json + tsconfig.json) is a
  /// root for more than one language, so callers can process each manifest.
  /// Returns null when no project root is found.
  Future<(Directory, List<ProjectLanguage>)?> findRootAndLanguages(
    Directory directory,
  ) async {
    var dir = _correctDir(directory.absolute);

    while (true) {
      final matched = <ProjectLanguage>[
        for (final language in languages)
          if (language.isProjectRoot(dir)) language,
      ];
      if (matched.isNotEmpty) {
        return (_correctDir(dir), matched);
      }

      final parent = dir.parent;
      if (parent.path == dir.path) {
        return null;
      }
      dir = parent;
    }
  }

  /// Returns the directory that holds the sibling checkouts of the project at
  /// [projectRoot].
  ///
  /// Usually the repositories sit directly in the workspace, so the parent of
  /// the project is the workspace root. A gg workspace may additionally group
  /// its repositories in a folder named after the organization a repository
  /// belongs to (`<workspace>/<org>/<repo>`); then the grandparent is the
  /// workspace root. Both gg workspaces are recognized by a marker they always
  /// carry — the ocean by its folder name (`.ocean`, or the legacy
  /// `.master`), a ticket workspace by its `ticket.json` file — so a plain
  /// folder of sibling checkouts outside a gg workspace keeps resolving to
  /// the parent.
  Directory workspaceRootOf(Directory projectRoot) {
    final parent = projectRoot.parent.absolute;
    if (_isWorkspaceRoot(parent)) {
      return parent;
    }
    final grandParent = parent.parent.absolute;
    if (_isWorkspaceRoot(grandParent)) {
      return grandParent;
    }
    return parent;
  }

  /// Returns every directory below [workspaceRoot] that may hold a project:
  /// its direct sub directories plus the children of each of them that is a
  /// grouping folder, i.e. a visible directory that is neither a project of
  /// any registered language nor a git repository. Sorted by path.
  ///
  /// An organization folder is such a grouping folder, a repository is not —
  /// so the repositories inside the organization folders are found while
  /// projects nested inside a repository stay invisible.
  List<Directory> projectCandidateDirs(Directory workspaceRoot) {
    final result = <Directory>[];
    for (final dir in _subDirs(workspaceRoot)) {
      result.add(dir);
      if (_isGroupingDir(dir)) {
        result.addAll(_subDirs(dir));
      }
    }
    return result..sort((a, b) => a.path.compareTo(b.path));
  }

  /// The name of the ocean of a gg workspace.
  static const String _oceanFolderName = '.ocean';

  /// The former name of [_oceanFolderName]. Still recognized so a workspace
  /// the gg tool has not auto-renamed yet keeps resolving to the right root.
  static const String _legacyMasterFolderName = '.master';

  /// The marker file a gg ticket workspace carries in its root.
  static const String _ticketFileName = 'ticket.json';

  /// Returns true when [dir] is the root of a gg workspace.
  bool _isWorkspaceRoot(Directory dir) =>
      p.basename(dir.path) == _oceanFolderName ||
      p.basename(dir.path) == _legacyMasterFolderName ||
      File(p.join(dir.path, _ticketFileName)).existsSync();

  /// Returns true when [dir] groups repositories instead of being one.
  bool _isGroupingDir(Directory dir) {
    if (p.basename(dir.path).startsWith('.')) {
      return false;
    }
    if (languages.any((language) => language.isProjectRoot(dir))) {
      return false;
    }
    return !Directory(p.join(dir.path, '.git')).existsSync();
  }

  /// Returns the direct sub directories of [directory].
  List<Directory> _subDirs(Directory directory) =>
      directory.listSync().whereType<Directory>().toList();

  Future<(Directory, ProjectLanguage)?> _findProjectRootAndLanguage(
    Directory directory, [
    ProjectLanguage? forLanguage,
  ]) async {
    var dir = _correctDir(directory);
    final candidates = forLanguage != null
        ? <ProjectLanguage>[forLanguage]
        : languages;

    while (true) {
      for (final language in candidates) {
        if (language.isProjectRoot(dir)) {
          return (_correctDir(dir), language);
        }
      }

      final parent = dir.parent;
      if (parent.path == dir.path) {
        return null;
      }
      dir = parent;
    }
  }

  /// Verifies that the regular dependencies form no cycle.
  ///
  /// A cycle that only a dev dependency closes is allowed: the DNA makes
  /// helper packages dev-depend on `helix`, while `helix` builds on them.
  /// Such an edge is ignored for this check only - the graph keeps it, so
  /// localize and unlocalize still rewrite the reference. Every ignored
  /// edge is reported via [ggLog]. A cycle made of regular dependencies
  /// alone remains an error.
  void _checkCircularDependencies(
    Map<String, ProjectNode> nodes,
    GgLog? ggLog,
  ) {
    final edges = <String, Set<String>>{
      for (final node in nodes.values)
        node.name: <String>{...node.dependencies.keys},
    };

    while (true) {
      final cycle = _findCycle(edges);
      if (cycle == null) {
        return;
      }

      // The edge to cut is picked by name, so the same graph always
      // yields the same breaks no matter which sequence the packages
      // were read in.
      String? cutFrom;
      String? cutTo;
      for (var i = 0; i < cycle.length - 1; i++) {
        final from = cycle[i];
        final to = cycle[i + 1];
        if (!nodes[from]!.devOnlyDependencies.contains(to)) {
          continue;
        }
        if (cutTo == null || to.compareTo(cutTo) < 0) {
          cutFrom = from;
          cutTo = to;
        }
      }

      if (cutFrom == null || cutTo == null) {
        final part0 = red('Please remove circular dependency:\n');
        final part1 = yellow(cycle.join(' -> '));
        throw Exception('$part0$part1');
      }

      edges[cutFrom]!.remove(cutTo);
      ggLog?.call(
        yellow('Broke dev dependency $cutFrom -> $cutTo to resolve a cycle.'),
      );
    }
  }

  /// Returns the names of one cycle in [edges], first and last entry
  /// equal, or `null` when the graph is acyclic.
  List<String>? _findCycle(Map<String, Set<String>> edges) {
    final path = <String>[];
    final onPath = <String>{};
    final settled = <String>{};

    List<String>? visit(String name) {
      if (onPath.contains(name)) {
        return <String>[...path.sublist(path.indexOf(name)), name];
      }
      if (settled.contains(name)) {
        return null;
      }

      path.add(name);
      onPath.add(name);
      // Copied: the loop above removes edges between two searches.
      for (final dependency in edges[name]!.toList()) {
        final cycle = visit(dependency);
        if (cycle != null) {
          return cycle;
        }
      }
      path.removeLast();
      onPath.remove(name);
      settled.add(name);
      return null;
    }

    for (final name in edges.keys) {
      final cycle = visit(name);
      if (cycle != null) {
        return cycle;
      }
    }
    return null;
  }

  Directory _correctDir(Directory directory) {
    var dir = directory;
    if (dir.path.endsWith('\\.') || dir.path.endsWith('/.')) {
      dir = Directory(dir.path.substring(0, dir.path.length - 2));
    } else if (dir.path.endsWith('\\') || dir.path.endsWith('/')) {
      dir = Directory(dir.path.substring(0, dir.path.length - 1));
    }
    return dir;
  }
}
