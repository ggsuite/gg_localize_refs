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
import 'package:gg_localize_refs/src/publish_to_utils.dart';

// #############################################################################
/// Command for localizing references
class LocalizeRefs extends DirCommand<dynamic> {
  /// The function used to run processes (injected for testability)
  /// Defaults to [Process.run]
  late Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  runProcess;

  /// Constructor
  LocalizeRefs({required super.ggLog})
    : super(
        name: 'localize-refs',
        description: 'Changes dependencies to local dependencies.',
      ) {
    argParser.addFlag(
      'git',
      abbr: 'g',
      negatable: false,
      help: 'Use git references instead of local paths.',
    );
    runProcess =
        (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
        }) {
          return Process.run(
            executable,
            arguments,
            workingDirectory: workingDirectory,
          );
        };
  }

  /// Whether to localize to git references
  late bool useGit;

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? git,
  }) async {
    ggLog('Running localize-refs in ${directory.path}');
    // Use a safe access for argResults
    useGit = git ?? ((argResults?['git'] as bool?) ?? false);
    FileChangesBuffer fileChangesBuffer = FileChangesBuffer();

    try {
      await processProject(directory, modifyYaml, fileChangesBuffer, ggLog);

      if (fileChangesBuffer.files.isEmpty) {
        ggLog(yellow('No files were changed.'));
        return;
      }

      await fileChangesBuffer.apply();
    } catch (e) {
      throw Exception(yellow('An error occurred: $e. No files were changed.'));
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
    if (!useGit) {
      // Normal path (file)
      bool hasOnlineDependencies = false;

      for (MapEntry<String, Node> dependency in node.dependencies.entries) {
        if (!yamlToString(
          getDependency(dependency.key, yamlMap),
        ).startsWith('path:')) {
          hasOnlineDependencies = true;
        }
      }

      if (!hasOnlineDependencies) {
        return;
      }

      ggLog('Localize refs of $packageName');

      // copy pubspec.yaml to pubspec.yaml.original
      File originalPubspec = File(
        '${projectDir.path}/.gg_localize_refs_backup.yaml',
      );
      await _writeFileCopy(source: pubspec, destination: originalPubspec);

      // Return the updated YAML content
      String newPubspecContent = pubspecContent;

      Map<String, dynamic> replacedDependencies = {};

      for (MapEntry<String, Node> dependency in node.dependencies.entries) {
        String dependencyName = dependency.key;
        String dependencyPath = dependency.value.directory.path;
        String relativeDepPath = p
            .relative(dependencyPath, from: projectDir.path)
            .replaceAll('\\', '/');
        dynamic oldDependency = getDependency(dependencyName, yamlMap);
        String oldDependencyYaml = yamlToString(oldDependency);
        String oldDependencyYamlCompressed = oldDependencyYaml.replaceAll(
          RegExp(r'[\n\r\t{}]'),
          '',
        );

        if (!oldDependencyYamlCompressed.startsWith('path:')) {
          replacedDependencies[dependencyName] = getDependency(
            dependencyName,
            yamlMap,
          );
        }

        newPubspecContent = replaceDependency(
          newPubspecContent,
          dependencyName,
          oldDependencyYaml,
          'path: $relativeDepPath # $oldDependencyYamlCompressed',
        );
      }

      // Backup publish_to
      final publishBackup = backupPublishTo(yamlMap);
      replacedDependencies.addAll(publishBackup);

      // Add publish_to: none
      newPubspecContent = addPublishToNone(newPubspecContent);

      // Save the replaced dependencies to a JSON file
      await saveDependenciesAsJson(
        replacedDependencies,
        '${projectDir.path}/.gg_localize_refs_backup.json',
      );

      // write new pubspec.yaml.modified
      File modifiedPubspec = File('${projectDir.path}/pubspec.yaml');
      fileChangesBuffer.add(modifiedPubspec, newPubspecContent);
      return;
    }
    // ------------ useGit = true ----------------------
    bool hasNonGitDependencies = false;
    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      String depYaml = yamlToString(getDependency(dependency.key, yamlMap));
      if (!depYaml.startsWith('git:')) {
        // not yet git
        hasNonGitDependencies = true;
      }
    }
    if (!hasNonGitDependencies) {
      return;
    }

    ggLog('Localize refs of $packageName');

    // backup YAML
    File originalPubspec = File(
      '${projectDir.path}/.gg_localize_refs_backup.yaml',
    );
    await _writeFileCopy(source: pubspec, destination: originalPubspec);
    // backup JSON of dependencies
    Map<String, dynamic> replacedDependencies = {};
    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      String dependencyName = dependency.key;
      dynamic oldDependency = getDependency(dependencyName, yamlMap);
      String oldDependencyYaml = yamlToString(oldDependency);

      if (!oldDependencyYaml.startsWith('git:')) {
        replacedDependencies[dependencyName] = getDependency(
          dependencyName,
          yamlMap,
        );
      }
    }
    // Backup publish_to
    final publishBackup = backupPublishTo(yamlMap);
    replacedDependencies.addAll(publishBackup);

    await saveDependenciesAsJson(
      replacedDependencies,
      '${projectDir.path}/.gg_localize_refs_backup.json',
    );

    // Replace each dependency in pubspecContent
    String newPubspecContent = pubspecContent;
    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      String dependencyName = dependency.key;
      dynamic oldDependency = getDependency(dependencyName, yamlMap);
      String oldDependencyYaml = yamlToString(oldDependency);
      // Only replace if not already git
      if (!oldDependencyYaml.startsWith('git:')) {
        String newDependencyYaml = await getGitDependencyYaml(
          dependency.value.directory,
          dependencyName,
        );
        newPubspecContent = replaceDependency(
          newPubspecContent,
          dependencyName,
          oldDependencyYaml,
          newDependencyYaml,
        );
      }
    }
    // Add publish_to: none
    newPubspecContent = addPublishToNone(newPubspecContent);
    // write new pubspec.yaml.modified
    File modifiedPubspec = File('${projectDir.path}/pubspec.yaml');
    fileChangesBuffer.add(modifiedPubspec, newPubspecContent);
  }

  // ...........................................................................
  /// Get a dependency Yaml for a git repo
  Future<String> getGitDependencyYaml(Directory depDir, String depName) async {
    // resolve remote url
    final resultUrl = await runProcess('git', [
      'remote',
      'get-url',
      'origin',
    ], workingDirectory: depDir.path);
    if (resultUrl.exitCode != 0) {
      throw Exception(
        'Cannot get git remote url for dependency $depName in ${depDir.path}',
      );
    }
    final url = resultUrl.stdout.toString().trim();
    // resolve branch/ref
    final resultRef = await runProcess('git', [
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ], workingDirectory: depDir.path);
    String ref = 'main';
    if (resultRef.exitCode == 0) {
      ref = resultRef.stdout.toString().trim();
      // Fallback to 'main' if ref is 'HEAD' or empty string
      if (ref.isEmpty || ref == 'HEAD') {
        ref = 'main';
      }
    }
    final gitMap = {
      'git': {'url': url, 'ref': ref},
    };
    // returns YAML string for the dependency
    // The yamlToString expects Map corresponding to a full dependency:
    //     dependencyName:
    //       git:
    //         url:
    //         ref:
    return yamlToString(gitMap);
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
  Future<void> saveDependenciesAsJson(
    Map<String, dynamic> replacedDependencies,
    String filePath,
  ) async {
    // Convert the Map to a JSON string
    String jsonString = jsonEncode(replacedDependencies);

    // Write the JSON data to the file
    File file = File(filePath);
    await file.writeAsString(jsonString);
  }
}

// .............................................................................
/// Get a dependency from the YAML map
dynamic getDependency(String dependencyName, Map<dynamic, dynamic> yamlMap) {
  return yamlMap['dependencies']?[dependencyName] ??
      yamlMap['dev_dependencies']?[dependencyName];
}
