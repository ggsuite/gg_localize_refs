// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// ...........................................................................
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/multi_language_graph.dart';
import 'package:gg_log/gg_log.dart';
import 'package:yaml/yaml.dart';

/// Signature of a function that modifies a project manifest.
typedef ModifyManifest =
    Future<void> Function(
      ProjectNode node,
      File manifestFile,
      String manifestContent,
      dynamic manifestMap,
      FileChangesBuffer fileChangesBuffer,
    );

/// Process the project
Future<void> processProject({
  required Directory directory,
  required ModifyManifest modifyFunction,
  required FileChangesBuffer fileChangesBuffer,
  GgLog? ggLog,
}) async {
  final graph = MultiLanguageGraph(
    languages: <ProjectLanguage>[
      DartProjectLanguage(),
      TypeScriptProjectLanguage(),
    ],
  );

  final result = await graph.buildGraph(directory: directory, ggLog: ggLog);

  final rootNode = result.rootNode;
  final allNodes = result.allNodes;

  final processedNodes = <String>{};

  await processNode(
    rootNode,
    allNodes,
    processedNodes,
    modifyFunction,
    fileChangesBuffer,
  );
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
) async {
  final projectDir = correctDir(currentNode.directory);

  if (!allNodes.containsKey(currentNode.name)) {
    throw Exception(
      'The node for the package ${currentNode.name} was not found.',
    );
  }

  final manifestFile = File(
    '${projectDir.path}/${currentNode.language.manifestFileName}',
  );

  final manifestContent = await manifestFile.readAsString();

  final manifestMap = currentNode.language.parseManifestContent(
    manifestContent,
  );

  if (!_hasDependencies(manifestMap)) {
    return;
  }

  await modifyFunction(
    currentNode,
    manifestFile,
    manifestContent,
    manifestMap,
    fileChangesBuffer,
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
    );
  }
}

bool _hasDependencies(dynamic manifestMap) {
  if (manifestMap is! Map) {
    return false;
  }

  final hasDartDependencies =
      manifestMap.containsKey('dependencies') &&
      manifestMap['dependencies'] is Map &&
      (manifestMap['dependencies'] as Map).isNotEmpty;

  final hasDartDevDependencies =
      manifestMap.containsKey('dev_dependencies') &&
      manifestMap['dev_dependencies'] is Map &&
      (manifestMap['dev_dependencies'] as Map).isNotEmpty;

  final hasTsDependencies =
      manifestMap.containsKey('dependencies') &&
      manifestMap['dependencies'] is Map &&
      (manifestMap['dependencies'] as Map).isNotEmpty;

  final hasTsDevDependencies =
      manifestMap.containsKey('devDependencies') &&
      manifestMap['devDependencies'] is Map &&
      (manifestMap['devDependencies'] as Map).isNotEmpty;

  return hasDartDependencies ||
      hasDartDevDependencies ||
      hasTsDependencies ||
      hasTsDevDependencies;
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
  dynamic yaml;
  try {
    yaml = loadYaml(pubspecContent);
  } catch (e) {
    throw Exception(red('Error parsing pubspec.yaml:') + e.toString());
  }

  if (yaml is! Map) {
    throw Exception(
      '${red('Error parsing pubspec.yaml:')} Root node is not a map.',
    );
  }

  final name = yaml['name']?.toString();
  if (name == null || name.isEmpty) {
    throw Exception(
      '${red('Error parsing pubspec.yaml:')} "name" field is missing.',
    );
  }

  return name;
}
