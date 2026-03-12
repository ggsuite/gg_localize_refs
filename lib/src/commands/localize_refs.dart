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
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/backend/publish_to_utils.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;

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
  bool useGit = false;

  /// Optional override for the git ref (branch, tag, or commit).
  String? gitRefOverride;

  /// Ensures the backup directory (.gg) exists under [projectDir].
  Directory _ensureBackupDir(Directory projectDir) {
    final backupDir = Directory(p.join(projectDir.path, '.gg'));
    final didExist = backupDir.existsSync();
    if (!didExist) {
      backupDir.createSync(recursive: true);
    }
    return backupDir;
  }

  /// Ensures that `.gitignore` contains entries for `.gg` and `!.gg/.gg.json`
  void _ensureGitignoreHasGgEntries(Directory projectDir) {
    final gitignore = File(p.join(projectDir.path, '.gitignore'));
    const ignoreDir = '.gg';
    const keepConfig = '!.gg/.gg.json';

    if (!gitignore.existsSync()) {
      gitignore.writeAsStringSync('$ignoreDir\n$keepConfig\n');
      return;
    }

    final raw = gitignore.readAsStringSync();
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final content = normalized.endsWith('\n')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final lines = content.isEmpty ? <String>[] : content.split('\n');

    final hasIgnoreDir = lines.any((line) => line.trim() == ignoreDir);
    final hasKeepConfig = lines.any((line) => line.trim() == keepConfig);

    if (!hasIgnoreDir) {
      lines.add(ignoreDir);
    }
    if (!hasKeepConfig) {
      lines.add(keepConfig);
    }

    gitignore.writeAsStringSync('${lines.join('\n')}\n');
  }

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
        manifestMap,
        fileChangesBuffer,
      );
      return;
    }

    await _modifyTypeScript(
      node,
      manifestFile,
      manifestContent,
      manifestMap as Map<String, dynamic>,
      fileChangesBuffer,
    );
  }

  Future<void> _modifyDart(
    ProjectNode node,
    File pubspec,
    String pubspecContent,
    dynamic yamlMap,
    FileChangesBuffer fileChangesBuffer,
  ) async {
    final projectDir = node.directory;
    final backupDir = _ensureBackupDir(projectDir);
    _ensureGitignoreHasGgEntries(projectDir);
    final references = node.language.listDependencyReferences(yamlMap);

    if (!useGit) {
      var hasOnlineDependencies = false;

      for (final dependency in node.dependencies.entries) {
        final reference = references[dependency.key];
        if (reference == null) {
          continue;
        }
        if (!yamlToString(reference.value).startsWith('path:')) {
          hasOnlineDependencies = true;
        }
      }

      if (!hasOnlineDependencies) {
        return;
      }

      ggLog('Localize refs of ${node.name}');

      final originalPubspec = File(
        p.join(backupDir.path, '.gg_localize_refs_backup.yaml'),
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
        final reference = references[dependencyName];
        if (reference == null) {
          continue;
        }

        final oldDependencyYaml = yamlToString(reference.value);
        final oldDependencyYamlCompressed = oldDependencyYaml.replaceAll(
          RegExp(r'[\n\r\t{}]'),
          '',
        );

        if (!oldDependencyYamlCompressed.startsWith('path:')) {
          replacedDependencies[dependencyName] = _backupDependencyValue(
            reference.value,
          );
        }

        newPubspecContent = node.language.replaceDependencyInContent(
          manifestContent: newPubspecContent,
          reference: reference,
          newValue: 'path: $relativeDepPath # $oldDependencyYamlCompressed',
        );
      }

      final publishBackup = backupPublishTo(yamlMap as Map<dynamic, dynamic>);
      replacedDependencies.addAll(publishBackup);

      newPubspecContent = addPublishToNone(newPubspecContent);

      await saveDependenciesAsJson(
        replacedDependencies,
        p.join(backupDir.path, '.gg_localize_refs_backup.json'),
      );

      final modifiedPubspec = File('${node.directory.path}/pubspec.yaml');
      fileChangesBuffer.add(modifiedPubspec, newPubspecContent);
      return;
    }

    var hasNonGitDependencies = false;
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }
      final depYaml = yamlToString(reference.value);
      if (_shouldConvertToGit(depYaml)) {
        hasNonGitDependencies = true;
      }
    }
    if (!hasNonGitDependencies) {
      return;
    }

    ggLog('Localize refs of ${node.name}');

    final originalPubspec = File(
      p.join(backupDir.path, '.gg_localize_refs_backup.yaml'),
    );
    await _writeFileCopy(source: pubspec, destination: originalPubspec);

    final replacedDependencies = <String, dynamic>{};
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }
      final oldDependencyYaml = yamlToString(reference.value);

      if (_shouldBackupOriginalGitDependency(oldDependencyYaml)) {
        replacedDependencies[dependency.key] = _backupDependencyValue(
          reference.value,
        );
      }
    }

    final publishBackup = backupPublishTo(yamlMap as Map<dynamic, dynamic>);
    replacedDependencies.addAll(publishBackup);

    await saveDependenciesAsJson(
      replacedDependencies,
      p.join(backupDir.path, '.gg_localize_refs_backup.json'),
    );

    var newPubspecContent = pubspecContent;
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      if (reference == null) {
        continue;
      }
      final oldDependencyYaml = yamlToString(reference.value);

      if (_shouldConvertToGit(oldDependencyYaml)) {
        final newDependencyYaml = await getGitDependencyYaml(
          dependency.value.directory,
          dependency.key,
        );
        newPubspecContent = node.language.replaceDependencyInContent(
          manifestContent: newPubspecContent,
          reference: reference,
          newValue: newDependencyYaml,
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
    final references = node.language.listDependencyReferences(manifestMap);

    if (!useGit) {
      var hasOnlineDependencies = false;

      for (final dependency in node.dependencies.entries) {
        final reference = references[dependency.key];
        final value = reference?.value?.toString();
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
      var updatedContent = manifestContent;

      for (final dependency in node.dependencies.entries) {
        final reference = references[dependency.key];
        if (reference == null) {
          continue;
        }

        final depDir = dependency.value.directory.path;
        final relativePath = p
            .relative(depDir, from: node.directory.path)
            .replaceAll('\\', '/');

        final oldValue = reference.value;
        final oldString = oldValue.toString();
        if (!oldString.trim().startsWith('file:')) {
          replacedDependencies[dependency.key] = oldValue;
        }

        updatedContent = node.language.replaceDependencyInContent(
          manifestContent: updatedContent,
          reference: reference,
          newValue: 'file:$relativePath',
        );
      }

      if (replacedDependencies.isEmpty) {
        return;
      }

      final backupFile = File(
        '${node.directory.path}/.gg_localize_refs_backup.json',
      );
      await backupFile.writeAsString(jsonEncode(replacedDependencies));

      fileChangesBuffer.add(manifestFile, updatedContent);
      return;
    }

    var hasNonGitDependencies = false;
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
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
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (value == null) {
        continue;
      }
      if (!value.trim().startsWith('git+')) {
        replacedDependencies[dependency.key] = value;
      }
    }

    final backupFile = File(
      '${node.directory.path}/.gg_localize_refs_backup.json',
    );
    await backupFile.writeAsString(jsonEncode(replacedDependencies));

    var updatedContent = manifestContent;
    for (final dependency in node.dependencies.entries) {
      final reference = references[dependency.key];
      final value = reference?.value?.toString();
      if (reference == null || value == null) {
        continue;
      }
      if (value.trim().startsWith('git+')) {
        continue;
      }

      final gitSpec = await getGitDependencySpecForTs(
        dependency.value.directory,
        dependency.key,
      );
      updatedContent = node.language.replaceDependencyInContent(
        manifestContent: updatedContent,
        reference: reference,
        newValue: gitSpec,
      );
    }

    fileChangesBuffer.add(manifestFile, updatedContent);
  }

  /// Returns the compact backup value for a dependency.
  dynamic _backupDependencyValue(dynamic dependency) {
    if (dependency is String) {
      return dependency;
    }

    if (dependency is Map) {
      final version = dependency['version'];
      if (version != null) {
        return version.toString();
      }

      final git = dependency['git'];
      if (git is Map) {
        final gitVersion = git['version'];
        if (gitVersion != null) {
          return gitVersion.toString();
        }
      }
    }

    return dependency;
  }

  /// Returns whether [dependencyYaml] should be converted to a plain git ref.
  bool _shouldConvertToGit(String dependencyYaml) {
    final trimmed = dependencyYaml.trimLeft();
    if (!trimmed.startsWith('git:')) {
      return true;
    }

    return trimmed.contains('tag_pattern:');
  }

  /// Returns whether the original dependency should be backed up.
  bool _shouldBackupOriginalGitDependency(String dependencyYaml) {
    final trimmed = dependencyYaml.trimLeft();
    if (!trimmed.startsWith('git:')) {
      return true;
    }

    return trimmed.contains('tag_pattern:');
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
