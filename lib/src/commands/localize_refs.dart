// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:path/path.dart' as p;

import 'package:gg_args/gg_args.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/backend/replace_dependency.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_localize_refs/src/backend/publish_to_utils.dart';
import 'package:gg_log/gg_log.dart';

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
    argParser
      ..addFlag(
        'git',
        abbr: 'g',
        negatable: false,
        help: 'Use git references instead of local paths.',
      )
      ..addOption(
        'git-ref',
        help:
            'Git ref (branch, tag, or commit) '
            'to use when localizing with --git.',
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

  /// Optional override for the git ref (branch, tag, or commit).
  String? gitRefOverride;

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    GgLog? ggLog,
    bool? git,
    String? gitRef,
  }) async {
    ggLog?.call('Running localize-refs in ${directory.path}');
    useGit = git ?? ((argResults?['git'] as bool?) ?? false);
    gitRefOverride = gitRef ?? (argResults?['git-ref'] as String?);
    final fileChangesBuffer = FileChangesBuffer();

    try {
      await processProject(
        directory: directory,
        modifyFunction: modifyManifest,
        fileChangesBuffer: fileChangesBuffer,
        ggLog: ggLog,
      );

      if (fileChangesBuffer.files.isEmpty) {
        ggLog?.call(yellow('No files were changed.'));
        return;
      }

      await fileChangesBuffer.apply();
    } catch (e) {
      throw Exception(yellow('An error occurred: $e. No files were changed.'));
    }
  }

  // ...........................................................................
  /// Modify the manifest file of a project node.
  Future<void> modifyManifest(
    ProjectNode node,
    File manifestFile,
    String manifestContent,
    dynamic manifestMap,
    FileChangesBuffer fileChangesBuffer,
  ) async {
    if (node.language.id == ProjectLanguageId.dart) {
      await _modifyDart(
        node,
        manifestFile,
        manifestContent,
        manifestMap as Map<dynamic, dynamic>,
        fileChangesBuffer,
      );
      return;
    }

    if (node.language.id == ProjectLanguageId.typescript) {
      await _modifyTypeScript(
        node,
        manifestFile,
        manifestContent,
        manifestMap as Map<String, dynamic>,
        fileChangesBuffer,
      );
    }
  }

  Future<void> _modifyDart(
    ProjectNode node,
    File pubspec,
    String pubspecContent,
    Map<dynamic, dynamic> yamlMap,
    FileChangesBuffer fileChangesBuffer,
  ) async {
    if (!useGit) {
      var hasOnlineDependencies = false;

      for (final dependency in node.dependencies.entries) {
        if (!yamlToString(
          getDependency(dependency.key, yamlMap),
        ).startsWith('path:')) {
          hasOnlineDependencies = true;
        }
      }

      if (!hasOnlineDependencies) {
        return;
      }

      ggLog('Localize refs of ${node.name}');

      final originalPubspec = File(
        '${node.directory.path}/.gg_localize_refs_backup.yaml',
      );
      await _writeFileCopy(source: pubspec, destination: originalPubspec);

      var newPubspecContent = pubspecContent;

      final replacedDependencies = <String, dynamic>{};

      for (final dependency in node.dependencies.entries) {
        final dependencyName = dependency.key;
        final dependencyPath = dependency.value.directory.path;
        final relativeDepPath = p
            .relative(dependencyPath, from: node.directory.path)
            .replaceAll('\\', '/');
        final oldDependency = getDependency(dependencyName, yamlMap);
        final oldDependencyYaml = yamlToString(oldDependency);
        final oldDependencyYamlCompressed = oldDependencyYaml.replaceAll(
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

      final publishBackup = backupPublishTo(yamlMap);
      replacedDependencies.addAll(publishBackup);

      newPubspecContent = addPublishToNone(newPubspecContent);

      await saveDependenciesAsJson(
        replacedDependencies,
        '${node.directory.path}/.gg_localize_refs_backup.json',
      );

      final modifiedPubspec = File('${node.directory.path}/pubspec.yaml');
      fileChangesBuffer.add(modifiedPubspec, newPubspecContent);
      return;
    }

    var hasNonGitDependencies = false;
    for (final dependency in node.dependencies.entries) {
      final depYaml = yamlToString(getDependency(dependency.key, yamlMap));
      if (!depYaml.startsWith('git:')) {
        hasNonGitDependencies = true;
      }
    }
    if (!hasNonGitDependencies) {
      return;
    }

    ggLog('Localize refs of ${node.name}');

    final originalPubspec = File(
      '${node.directory.path}/.gg_localize_refs_backup.yaml',
    );
    await _writeFileCopy(source: pubspec, destination: originalPubspec);

    final replacedDependencies = <String, dynamic>{};
    for (final dependency in node.dependencies.entries) {
      final dependencyName = dependency.key;
      final oldDependency = getDependency(dependencyName, yamlMap);
      final oldDependencyYaml = yamlToString(oldDependency);

      if (!oldDependencyYaml.startsWith('git:')) {
        replacedDependencies[dependencyName] = getDependency(
          dependencyName,
          yamlMap,
        );
      }
    }

    final publishBackup = backupPublishTo(yamlMap);
    replacedDependencies.addAll(publishBackup);

    await saveDependenciesAsJson(
      replacedDependencies,
      '${node.directory.path}/.gg_localize_refs_backup.json',
    );

    var newPubspecContent = pubspecContent;
    for (final dependency in node.dependencies.entries) {
      final dependencyName = dependency.key;
      final oldDependency = getDependency(dependencyName, yamlMap);
      final oldDependencyYaml = yamlToString(oldDependency);

      if (!oldDependencyYaml.startsWith('git:')) {
        final newDependencyYaml = await getGitDependencyYaml(
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

    newPubspecContent = addPublishToNone(newPubspecContent);
    final modifiedPubspec = File('${node.directory.path}/pubspec.yaml');
    fileChangesBuffer.add(modifiedPubspec, newPubspecContent);
  }

  Future<void> _modifyTypeScript(
    ProjectNode node,
    File manifestFile,
    String manifestContent,
    Map<String, dynamic> manifestMap,
    FileChangesBuffer fileChangesBuffer,
  ) async {
    final dependencies = manifestMap['dependencies'] is Map
        ? (manifestMap['dependencies'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final devDependencies = manifestMap['devDependencies'] is Map
        ? (manifestMap['devDependencies'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    if (!useGit) {
      var hasOnlineDependencies = false;

      for (final dependency in node.dependencies.entries) {
        final name = dependency.key;
        final value =
            dependencies[name]?.toString() ?? devDependencies[name]?.toString();
        if (value == null) {
          continue;
        }
        if (!value.trim().startsWith('file:')) {
          hasOnlineDependencies = true;
        }
      }

      if (!hasOnlineDependencies) {
        return;
      }

      ggLog('Localize refs of ${node.name}');

      final replacedDependencies = <String, dynamic>{};

      for (final dependency in node.dependencies.entries) {
        final name = dependency.key;
        final depDir = dependency.value.directory.path;
        final relativePath = p
            .relative(depDir, from: node.directory.path)
            .replaceAll('\\', '/');

        if (dependencies.containsKey(name)) {
          final oldValue = dependencies[name];
          final oldString = oldValue.toString();
          if (!oldString.trim().startsWith('file:')) {
            replacedDependencies[name] = oldValue;
          }
          dependencies[name] = 'file:$relativePath';
        } else if (devDependencies.containsKey(name)) {
          final oldValue = devDependencies[name];
          final oldString = oldValue.toString();
          if (!oldString.trim().startsWith('file:')) {
            replacedDependencies[name] = oldValue;
          }
          devDependencies[name] = 'file:$relativePath';
        }
      }

      manifestMap['dependencies'] = dependencies;
      manifestMap['devDependencies'] = devDependencies;

      if (replacedDependencies.isEmpty) {
        return;
      }

      final backupFile = File(
        '${node.directory.path}/.gg_localize_refs_backup.json',
      );
      await backupFile.writeAsString(jsonEncode(replacedDependencies));

      final newContent = jsonEncode(manifestMap);
      fileChangesBuffer.add(manifestFile, '$newContent\n');
      return;
    }

    var hasNonGitDependencies = false;
    for (final dependency in node.dependencies.entries) {
      final name = dependency.key;
      final value =
          dependencies[name]?.toString() ?? devDependencies[name]?.toString();
      if (value == null) {
        continue;
      }
      if (!value.trim().startsWith('git+')) {
        hasNonGitDependencies = true;
      }
    }

    if (!hasNonGitDependencies) {
      return;
    }

    ggLog('Localize refs of ${node.name}');

    final replacedDependencies = <String, dynamic>{};

    for (final dependency in node.dependencies.entries) {
      final name = dependency.key;
      final value =
          dependencies[name]?.toString() ?? devDependencies[name]?.toString();
      if (value == null) {
        continue;
      }
      if (!value.trim().startsWith('git+')) {
        replacedDependencies[name] = value;
      }
    }

    final backupFile = File(
      '${node.directory.path}/.gg_localize_refs_backup.json',
    );
    await backupFile.writeAsString(jsonEncode(replacedDependencies));

    for (final dependency in node.dependencies.entries) {
      final name = dependency.key;
      final depDir = dependency.value.directory;

      final value =
          dependencies[name]?.toString() ?? devDependencies[name]?.toString();
      if (value == null) {
        continue;
      }
      if (value.trim().startsWith('git+')) {
        continue;
      }

      final gitSpec = await getGitDependencySpecForTs(depDir, name);
      if (dependencies.containsKey(name)) {
        dependencies[name] = gitSpec;
      } else if (devDependencies.containsKey(name)) {
        devDependencies[name] = gitSpec;
      }
    }

    manifestMap['dependencies'] = dependencies;
    manifestMap['devDependencies'] = devDependencies;

    final newContent = jsonEncode(manifestMap);
    fileChangesBuffer.add(manifestFile, '$newContent\n');
  }

  // ...........................................................................
  /// Get a dependency Yaml for a git repo
  ///
  /// If [gitRefOverride] is set, this value is used for the `ref` field
  /// instead of querying git for the current branch.
  Future<String> getGitDependencyYaml(Directory depDir, String depName) async {
    final gitInfo = await _resolveGitUrlAndRef(depDir, depName);
    final url = gitInfo.$1;
    final ref = gitInfo.$2;

    final gitMap = <String, dynamic>{
      'git': <String, dynamic>{'url': url, 'ref': ref},
    };

    return yamlToString(gitMap);
  }

  /// Returns a git spec string usable in package.json for TypeScript.
  Future<String> getGitDependencySpecForTs(
    Directory depDir,
    String depName,
  ) async {
    final gitInfo = await _resolveGitUrlAndRef(depDir, depName);
    final url = gitInfo.$1;
    final ref = gitInfo.$2;

    return 'git+$url#$ref';
  }

  Future<(String, String)> _resolveGitUrlAndRef(
    Directory depDir,
    String depName,
  ) async {
    final resultUrl = await runProcess('git', <String>[
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

    var ref = gitRefOverride?.trim() ?? '';

    if (ref.isEmpty) {
      final resultRef = await runProcess('git', <String>[
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ], workingDirectory: depDir.path);
      ref = 'main';
      if (resultRef.exitCode == 0) {
        ref = resultRef.stdout.toString().trim();
        if (ref.isEmpty || ref == 'HEAD') {
          ref = 'main';
        }
      }
    }

    return (url, ref);
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
    final jsonString = jsonEncode(replacedDependencies);
    final file = File(filePath);
    await file.writeAsString(jsonString);
  }
}

// ............................................................................
/// Get a dependency from the YAML map
dynamic getDependency(String dependencyName, Map<dynamic, dynamic> yamlMap) {
  return yamlMap['dependencies']?[dependencyName] ??
      yamlMap['dev_dependencies']?[dependencyName];
}
