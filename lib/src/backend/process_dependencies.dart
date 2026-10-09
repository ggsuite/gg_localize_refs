// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/multi_language_graph.dart';
import 'package:gg_log/gg_log.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

/// Signature of a function that modifies a project manifest.
typedef ModifyManifest = Future<void> Function(
  ProjectNode node,
  File manifestFile,
  String manifestContent,
  dynamic manifestMap,
  FileChangesBuffer fileChangesBuffer,
  GgLog ggLog,
);

/// Process the project
Future<void> processProject({
  required Directory directory,
  required ModifyManifest modifyFunction,
  required FileChangesBuffer fileChangesBuffer,
  required GgLog ggLog,
}) async {
  for (final result in await buildRootGraphs(
    directory: directory,
    ggLog: ggLog,
  )) {
    // Each language pass has its own node identity space, so it tracks its
    // own processed set.
    final processedNodes = <String>{};
    await processNode(
      result.rootNode,
      result.allNodes,
      processedNodes,
      modifyFunction,
      fileChangesBuffer,
      ggLog,
    );
  }
}

// ...........................................................................
/// Builds the workspace graph of the project root in [directory] once per
/// language the root supports: a cross-language bridge gets one for its Dart
/// and one for its TypeScript manifest, a single-language repo exactly one.
Future<List<({ProjectNode rootNode, Map<String, ProjectNode> allNodes})>>
buildRootGraphs({required Directory directory, required GgLog ggLog}) async {
  final graph = MultiLanguageGraph(
    languages: <ProjectLanguage>[
      DartProjectLanguage(),
      TypeScriptProjectLanguage(),
    ],
  );

  final root = await graph.findRootAndLanguages(directory);
  if (root == null) {
    throw Exception(red('No project root found'));
  }

  final (rootDir, rootLanguages) = root;
  return <({ProjectNode rootNode, Map<String, ProjectNode> allNodes})>[
    for (final language in rootLanguages)
      await graph.buildGraph(
        directory: rootDir,
        ggLog: ggLog,
        forLanguage: language,
      ),
  ];
}

// ...........................................................................
/// Find a node by package name in the dependency graph
ProjectNode? findNode({
  required String packageName,
  required Map<String, ProjectNode> nodes,
}) {
  if (nodes.isEmpty) {
    return null;
  }
  final ProjectNode? node = nodes[packageName];
  if (node != null) {
    return node;
  }
  for (final n in nodes.values) {
    final ProjectNode? foundNode = findNode(
      packageName: packageName,
      nodes: n.dependencies,
    );
    if (foundNode != null) {
      return foundNode;
    }
  }
  return null;
}

// ...........................................................................
/// Process the node
Future<void> processNode(
  ProjectNode currentNode,
  Map<String, ProjectNode> allNodes,
  Set<String> processedNodes,
  ModifyManifest modifyFunction,
  FileChangesBuffer fileChangesBuffer,
  GgLog ggLog,
) async {
  final projectDir = correctDir(currentNode.directory);

  if (!allNodes.containsKey(currentNode.name)) {
    throw Exception(
      'The node for the package ${currentNode.name} was not found.',
    );
  }

  final manifest = await currentNode.language.readManifest(projectDir);

  if (!currentNode.language.hasAnyDependencyEntries(manifest.parsed)) {
    return;
  }

  await modifyFunction(
    currentNode,
    manifest.file,
    manifest.content,
    manifest.parsed,
    fileChangesBuffer,
    ggLog,
  );

  for (final dependency in currentNode.dependencies.entries) {
    if (processedNodes.contains(dependency.key)) {
      continue;
    }
    processedNodes.add(dependency.key);
    await processNode(
      dependency.value,
      allNodes,
      processedNodes,
      modifyFunction,
      fileChangesBuffer,
      ggLog,
    );
  }
}

// ...........................................................................
/// Helper method to correct a directory
Directory correctDir(Directory directory) {
  var dir = directory;
  if (dir.path.endsWith('\\.') || dir.path.endsWith('/.')) {
    dir = Directory(dir.path.substring(0, dir.path.length - 2));
  } else if (dir.path.endsWith('\\') || dir.path.endsWith('/')) {
    dir = Directory(dir.path.substring(0, dir.path.length - 1));
  }
  return dir;
}

// ...........................................................................
/// Get the package name from the pubspec.yaml file
String getPackageName(String pubspecContent) {
  late Pubspec pubspecYaml;
  try {
    pubspecYaml = Pubspec.parse(pubspecContent);
  } catch (e) {
    throw Exception(red('Error parsing pubspec.yaml:') + e.toString());
  }

  return pubspecYaml.name;
}
