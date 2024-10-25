// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_project_root/gg_project_root.dart';
import 'package:gg_to_local/src/yaml_to_string.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

// #############################################################################
/// An example command
class LocalizeRefs extends DirCommand<dynamic> {
  /// Constructor
  LocalizeRefs({
    required super.ggLog,
  }) : super(
          name: 'localize-refs',
          description: 'Changes dependencies to local dependencies.',
        );

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    ggLog('Running localize-refs in ${directory.path}');

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

    await processNode(projectDir, nodes, {}, modifyYaml);
  }

  // ...........................................................................
  /// Process the node
  Future<void> processNode(
    Directory projectDir,
    Map<String, Node> nodes,
    Set<String> processedNodes,
    // Modify function
    Future<void> Function(
      String packageName,
      File pubspec,
      String pubspecContent,
      Map<dynamic, dynamic> yamlMap,
      Node node,
      Directory projectDir,
    ) modifyFunction,
  ) async {
    projectDir = correctDir(projectDir);
    final pubspec = File('${projectDir.path}/pubspec.yaml');

    final pubspecContent = await pubspec.readAsString();

    String packageName = getPackageName(pubspecContent);

    // Load the YAML content as a Map
    final yamlMap = loadYaml(pubspecContent) as Map;

    // Check if the 'dependencies' section exists
    if (!yamlMap.containsKey('dependencies')) {
      return;
    }

    Node? node = nodes[packageName];

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
      );
    }
  }

  // ...........................................................................
  /// Modify the pubspec.yaml file
  Future<void> modifyYaml(
    String packageName,
    File pubspec,
    String pubspecContent,
    Map<dynamic, dynamic> yamlMap,
    Node node,
    Directory projectDir,
  ) async {
    ggLog('Processing dependencies of package $packageName:');

    // copy pubspec.yaml to pubspec.yaml.original
    File originalPubspec = File('${projectDir.path}/.gg_to_local_backup.yaml');
    await _writeFileCopy(
      source: pubspec,
      destination: originalPubspec,
    );

    // Return the updated YAML content
    String newPubspecContent = pubspecContent;

    Map<String, dynamic> replacedDependencies = {};

    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      String dependencyName = dependency.key;
      String dependencyPath = dependency.value.directory.path;
      dynamic oldDependency = yamlMap['dependencies'][dependencyName];
      String oldDependencyYaml = yamlToString(oldDependency);
      String oldDependencyYamlCompressed =
          '# ${oldDependencyYaml.replaceAll(RegExp(r'[\n\r\t{}]'), '')}';

      ggLog('\t$dependencyName');

      // Update or add the dependency
      print(oldDependency);

      if (!oldDependencyYamlCompressed.startsWith('path:')) {
        replacedDependencies[dependencyName] =
            yamlMap['dependencies'][dependencyName];
      }

      String oldDependencyPattern =
          RegExp.escape(oldDependencyYaml).replaceAll(RegExp(r'\s+'), r'\s*');
      RegExp oldDependencyRegex = RegExp(oldDependencyPattern);

      newPubspecContent = newPubspecContent.replaceAll(
        oldDependencyRegex,
        '\n    path: $dependencyPath # $oldDependencyYamlCompressed\n  ',
      );
    }

    // Save the replaced dependencies to a JSON file
    saveDependenciesAsJson(
      replacedDependencies,
      '${projectDir.path}/.gg_to_local_backup.json',
    );

    // write new pubspec.yaml.modified
    File modifiedPubspec = File('${projectDir.path}/pubspec.yaml.modified');
    await _writeToFile(
      content: newPubspecContent,
      file: modifiedPubspec,
    );
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
  /// Helper method to write content to a file
  Future<void> _writeToFile({
    required String content,
    required File file,
  }) async {
    if (await file.exists()) {
      await file.delete();
    }
    await file.writeAsString(content);
  }

  // ...........................................................................
  /// Helper method to copy a file
  Future<void> _writeFileCopy({
    required File source,
    required File destination,
  }) async {
    if (await destination.exists()) {
      await destination.delete();
    }
    await source.copy(destination.path);
  }

  // ...........................................................................
  /// Save the dependencies to a JSON file
  void saveDependenciesAsJson(
    Map<String, dynamic> replacedDependencies,
    String filePath,
  ) async {
    // Convert the Map to a JSON string
    String jsonString = jsonEncode(replacedDependencies);

    // Write the JSON data to the file
    File file = File(filePath);
    await file.writeAsString(jsonString);

    print('Dependencies successfully saved to $filePath.');
  }
}
