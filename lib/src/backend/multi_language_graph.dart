// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';

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
  /// Returns a record containing the root node and all nodes in the workspace.
  Future<({ProjectNode rootNode, Map<String, ProjectNode> allNodes})> buildGraph({
    required Directory directory,
    GgLog? ggLog,
  }) async {
    final startDir = _correctDir(directory);

    final rootInfo = await _findProjectRootAndLanguage(startDir);
    if (rootInfo == null) {
      throw Exception(red('No project root found'));
    }

    final rootDir = rootInfo.$1;
    final language = rootInfo.$2;

    final workspaceRoot = rootDir.parent;

    final allDirs = workspaceRoot
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

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
    }

    // Detect circular dependencies.
    final coveredNodes = <ProjectNode>[];
    for (final node in nodes.values) {
      _detectCircularDependencies(node, coveredNodes);
    }

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
        'The node for the package ${rootDir.path.split(Platform.pathSeparator).last} was not found.',
      );
    }

    return (rootNode: rootNode, allNodes: nodes);
  }

  Future<(Directory, ProjectLanguage)?> _findProjectRootAndLanguage(
    Directory directory,
  ) async {
    var dir = _correctDir(directory);

    while (true) {
      for (final language in languages) {
        if (language.isProjectRoot(dir)) {
          return (dir, language);
        }
      }

      final parent = dir.parent;
      if (parent.path == dir.path) {
        return null;
      }
      dir = parent;
    }
  }

  void _detectCircularDependencies(
    ProjectNode node,
    List<ProjectNode> coveredNodes,
  ) {
    if (coveredNodes.contains(node)) {
      final indexOfCoveredNode = coveredNodes.indexOf(node);
      final circularNodes = <ProjectNode>[
        ...coveredNodes.sublist(indexOfCoveredNode),
        node,
      ];
      final circularNames = circularNodes.map((n) => n.name).join(' -> ');

      final part0 = red('Please remove circular dependency:\n');
      final part1 = yellow(circularNames);

      throw Exception('$part0$part1');
    }

    for (final dependency in node.dependencies.values) {
      _detectCircularDependencies(dependency, <ProjectNode>[...coveredNodes, node]);
    }
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
