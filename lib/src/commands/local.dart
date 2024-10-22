// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_project_root/gg_project_root.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

// #############################################################################
/// An example command
class Local extends DirCommand<dynamic> {
  /// Constructor
  Local({
    required super.ggLog,
  }) : super(
          name: 'local',
          description: 'Changes dependencies to local dependencies.',
        );

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    ggLog('Running local in ${directory.path}');

    String? root = await GgProjectRoot.get(directory.absolute.path);

    if (root == null) {
      throw Exception(red('No project root found'));
    }

    Directory projectDir = _correctDir(Directory(root));

    Graph graph = Graph(ggLog: ggLog);
    Map<String, Node> nodes = await graph.get(
      directory: projectDir.parent,
      ggLog: ggLog,
    );

    await modifyYaml(projectDir, nodes, {});
  }

  // ...........................................................................
  /// Modify the pubspec.yaml file
  Future<void> modifyYaml(
    Directory projectDir,
    Map<String, Node> nodes,
    Set<String> processedNodes,
  ) async {
    projectDir = _correctDir(projectDir);
    final pubspec = File('${projectDir.path}/pubspec.yaml');

    final pubspecContent = await pubspec.readAsString();
    late Pubspec pubspecYaml;
    try {
      pubspecYaml = Pubspec.parse(pubspecContent);
    } catch (e) {
      throw Exception(red('Error parsing pubspec.yaml:') + e.toString());
    }

    String packageName = pubspecYaml.name;

    // copy pubspec.yaml to pubspec.yaml.original
    File originalPubspec = File('${projectDir.path}/.gg_to_local_backup.yaml');
    await _writeFileCopy(
      source: pubspec,
      destination: originalPubspec,
    );

    // Create a YamlEditor with the current content
    final editor = YamlEditor(pubspecContent);

    // Load the YAML content as a Map
    final yamlMap = loadYaml(pubspecContent) as Map;

    // Check if the 'dependencies' section exists
    if (!yamlMap.containsKey('dependencies')) {
      throw Exception("The 'dependencies' section was not found.");
    }

    Node? node = nodes[packageName];

    if (node == null) {
      throw Exception('The node for the package $packageName was not found.');
    }

    ggLog('Processing dependencies of package $packageName:');

    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      String dependencyName = dependency.key;
      String dependencyPath = dependency.value.directory.path;
      /*String oldDependency = yamlMap['dependencies'][dependencyName]
          .toString()
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .replaceAll('\t', '')
          .replaceAll('{', '')
          .replaceAll('}', '');*/

      dynamic newDependency = {
        'path': dependencyPath,
      };

      ggLog('\t$dependencyName');

      // Update or add the dependency
      editor.update(['dependencies', dependencyName], newDependency);
    }

    // Return the updated YAML content
    String newPubspecContent = editor.toString();

    // write new pubspec.yaml.modified
    File modifiedPubspec = File('${projectDir.path}/pubspec.yaml.modified');
    await _writeToFile(
      content: newPubspecContent,
      file: modifiedPubspec,
    );

    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      if (processedNodes.contains(dependency.key)) {
        continue;
      }
      processedNodes.add(dependency.key);
      await modifyYaml(
        dependency.value.directory,
        node.dependencies,
        processedNodes,
      );
    }
  }

  Directory _correctDir(Directory directory) {
    if (directory.path.endsWith('\\.')) {
      directory =
          Directory(directory.path.substring(0, directory.path.length - 2));
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
}
