// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/file_changes_buffer.dart';
import 'package:path/path.dart' as p;

import 'package:gg_args/gg_args.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_localize_refs/src/process_dependencies.dart';
import 'package:gg_localize_refs/src/replace_dependency.dart';
import 'package:gg_localize_refs/src/yaml_to_string.dart';

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

    FileChangesBuffer fileChangesBuffer = FileChangesBuffer();

    try {
      await processProject(directory, modifyYaml, fileChangesBuffer, ggLog);

      await fileChangesBuffer.apply();
    } catch (e) {
      throw Exception(red('An error occurred: $e. No files were changed.'));
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
    FileChangesBuffer fileChangesBuffer,
  ) async {
    ggLog('Processing dependencies of package $packageName:');

    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      if (yamlToString(
        getDependency(dependency.key, yamlMap),
      ).startsWith('path:')) {
        ggLog('Dependencies already localized.');
        return;
      }
    }

    // copy pubspec.yaml to pubspec.yaml.original
    File originalPubspec =
        File('${projectDir.path}/.gg_localize_refs_backup.yaml');
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
      String relativeDepPath =
          p.relative(dependencyPath, from: projectDir.path);
      dynamic oldDependency = getDependency(dependencyName, yamlMap);
      String oldDependencyYaml = yamlToString(oldDependency);
      String oldDependencyYamlCompressed =
          oldDependencyYaml.replaceAll(RegExp(r'[\n\r\t{}]'), '');

      ggLog('\t$dependencyName');

      // Update or add the dependency

      if (!oldDependencyYamlCompressed.startsWith('path:')) {
        replacedDependencies[dependencyName] =
            getDependency(dependencyName, yamlMap);
      }

      newPubspecContent = replaceDependency(
        newPubspecContent,
        dependencyName,
        oldDependencyYaml,
        'path: $relativeDepPath # $oldDependencyYamlCompressed',
      );
    }

    // Save the replaced dependencies to a JSON file
    saveDependenciesAsJson(
      replacedDependencies,
      '${projectDir.path}/.gg_localize_refs_backup.json',
    );

    // write new pubspec.yaml.modified
    File modifiedPubspec = File('${projectDir.path}/pubspec.yaml');
    fileChangesBuffer.add(modifiedPubspec, newPubspecContent);
  }

  // ...........................................................................
  /// Helper method to copy a file
  Future<void> _writeFileCopy({
    required File source,
    required File destination,
  }) async {
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

// ...........................................................................
/// Get a dependency from the YAML map
dynamic getDependency(String dependencyName, Map<dynamic, dynamic> yamlMap) {
  return yamlMap['dependencies']?[dependencyName] ??
      yamlMap['dev_dependencies']?[dependencyName];
}
