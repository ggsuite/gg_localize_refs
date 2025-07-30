// ...........................................................................
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/src/file_changes_buffer.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_project_root/gg_project_root.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

/// Process the project
Future<void> processProject(
  Directory directory,
  Future<void> Function(
    String packageName,
    File pubspec,
    String pubspecContent,
    Map<dynamic, dynamic> yamlMap,
    Node node,
    Directory projectDir,
    FileChangesBuffer fileChangesBuffer,
  ) modifyFunction,
  FileChangesBuffer fileChangesBuffer,
  GgLog ggLog,
) async {
  String? root = await GgProjectRoot.get(directory.absolute.path);

  if (root == null) {
    throw Exception(red('No project root found'));
  }

  Directory projectDir = correctDir(Directory(root));

  Graph graph = Graph(ggLog: ggLog);
  Map<String, Node> nodes = await graph.get(
    directory: projectDir.parent,
    ggLog: ggLog,
  );

  await processNode(projectDir, nodes, {}, modifyFunction, fileChangesBuffer);
}

// ...........................................................................
/// Process the node
Future<void> processNode(
  Directory projectDir,
  Map<String, Node> nodes,
  Set<String> processedNodes,
  Future<void> Function(
    String packageName,
    File pubspec,
    String pubspecContent,
    Map<dynamic, dynamic> yamlMap,
    Node node,
    Directory projectDir,
    FileChangesBuffer fileChangesBuffer,
  ) modifyFunction,
  FileChangesBuffer fileChangesBuffer,
) async {
  projectDir = correctDir(projectDir);
  final pubspec = File('${projectDir.path}/pubspec.yaml');

  final pubspecContent = await pubspec.readAsString();

  String packageName = getPackageName(pubspecContent);

  // Load the YAML content as a Map
  final yamlMap = loadYaml(pubspecContent) as Map;

  // Check if the 'dependencies' section exists
  if (!yamlMap.containsKey('dependencies') &&
      !yamlMap.containsKey('dev_dependencies')) {
    return;
  }

  // Collect all unique nodes
  final allNodesMap = <String, Node>{};
  void collect(Node node) {
    if (allNodesMap.containsKey(node.name)) return;
    allNodesMap[node.name] = node;
    for (final dep in node.dependencies.values) {
      collect(dep);
    }
  }

  for (final root in nodes.values) {
    collect(root);
  }

  Node? node = allNodesMap[packageName];

  if (node == null) {
    throw Exception('The node for the package $packageName was not found.');
  }

  await modifyFunction(
    packageName,
    pubspec,
    pubspecContent,
    yamlMap,
    node,
    projectDir,
    fileChangesBuffer,
  );

  for (MapEntry<String, Node> dependency in node.dependencies.entries) {
    if (processedNodes.contains(dependency.key)) {
      continue;
    }
    processedNodes.add(dependency.key);
    await processNode(
      dependency.value.directory,
      node.dependencies,
      processedNodes,
      modifyFunction,
      fileChangesBuffer,
    );
  }
}

// ...........................................................................
/// Helper method to correct a directory
Directory correctDir(Directory directory) {
  if (directory.path.endsWith('\\.') || directory.path.endsWith('/.')) {
    directory =
        Directory(directory.path.substring(0, directory.path.length - 2));
  } else if (directory.path.endsWith('\\') || directory.path.endsWith('/')) {
    directory =
        Directory(directory.path.substring(0, directory.path.length - 1));
  }
  return directory;
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
