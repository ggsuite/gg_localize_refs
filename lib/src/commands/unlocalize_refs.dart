// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_to_local/src/process_dependencies.dart';
import 'package:gg_to_local/src/replace_dependency.dart';
import 'package:gg_to_local/src/yaml_to_string.dart';

// #############################################################################
/// An example command
class UnlocalizeRefs extends DirCommand<dynamic> {
  /// Constructor
  UnlocalizeRefs({
    required super.ggLog,
  }) : super(
          name: 'unlocalize-refs',
          description: 'Changes dependencies to remote dependencies.',
        );

  // ...........................................................................
  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    ggLog('Running unlocalize-refs in ${directory.path}');

    await processProject(directory, modifyYaml, ggLog);
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

    // Return the updated YAML content
    String newPubspecContent = pubspecContent;

    Map<String, dynamic> savedDependencies = readDependenciesFromJson(
      '${projectDir.path}/.gg_to_local_backup.json',
    );

    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      String dependencyName = dependency.key;
      dynamic oldDependency = yamlMap['dependencies'][dependencyName];
      String oldDependencyYaml = yamlToString(oldDependency);

      if (!savedDependencies.containsKey(dependencyName)) {
        continue;
      }

      ggLog('\t$dependencyName');

      // Update or add the dependency

      if (!oldDependencyYaml.contains('path:')) {
        ggLog('Dependencies already unlocalized.');
        return;
      }

      String newDependencyYaml =
          yamlToString(savedDependencies[dependencyName]);

      newPubspecContent = replaceDependency(
        newPubspecContent,
        dependencyName,
        oldDependencyYaml,
        newDependencyYaml,
      );
    }

    // write new pubspec.yaml.modified
    File modifiedPubspec = File('${projectDir.path}/pubspec.yaml');
    await _writeToFile(
      content: newPubspecContent,
      file: modifiedPubspec,
    );
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
  /// Read dependencies from a JSON file
  Map<String, dynamic> readDependenciesFromJson(String filePath) {
    File file = File(filePath);
    String jsonString = file.readAsStringSync();
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }
}
