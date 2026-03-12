// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights
// Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/multi_language_graph.dart';
import 'package:gg_localize_refs/src/backend/replace_dependency.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_publish/gg_publish.dart';
import 'package:gg_log/gg_log.dart';
import 'package:yaml/yaml.dart';

// #############################################################################
/// Command that sets the version/spec of a dependency in pubspec.yaml
/// or package.json.
///
/// This command operates directly on the manifest in the provided
/// input directory. It does not traverse a workspace or use project graphs.
class SetRefVersion extends DirCommand<dynamic> {
  /// Constructor.
  SetRefVersion({required super.ggLog})
    : isOnPubDev = IsOnPubDev(ggLog: ggLog),
      super(
        name: 'set-ref-version',
        description: 'Sets the version/spec of a dependency in pubspec.yaml.',
      ) {
    argParser
      ..addOption('ref', help: 'The dependency name to change.')
      ..addOption(
        'version',
        help:
            'The new version/spec. Can be a scalar (e.g., ^1.2.3) '
            'or a YAML/JSON block.',
      );
  }

  /// Service used to check whether a dependency was published before.
  final IsOnPubDev isOnPubDev;

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    GgLog? ggLog,
    String? ref,
    String? version,
  }) async {
    ggLog?.call('Running set-ref-version in ${directory.path}');

    final String? dependencyName = ref ?? (argResults?['ref'] as String?);
    final String? newVersion = version ?? (argResults?['version'] as String?);

    if (dependencyName == null || dependencyName.isEmpty) {
      throw Exception(red('Please provide a dependency name via --ref.'));
    }
    if (newVersion == null) {
      throw Exception(red('Please provide the new version via --version.'));
    }

    try {
      final pubspec = File('${directory.path}/pubspec.yaml');
      final packageJson = File('${directory.path}/package.json');

      if (!pubspec.existsSync() && !packageJson.existsSync()) {
        throw Exception('pubspec.yaml not found at ${pubspec.path}');
      }

      if (pubspec.existsSync()) {
        await _updateDartDependency(
          directory: directory,
          pubspecFile: pubspec,
          dependencyName: dependencyName,
          newVersion: newVersion,
          ggLog: ggLog,
        );
        return;
      }

      _updateTypeScriptDependency(
        packageJsonFile: packageJson,
        dependencyName: dependencyName,
        newVersion: newVersion,
        ggLog: ggLog,
      );
    } catch (e) {
      throw Exception(red('An error occurred: $e. No files were changed.'));
    }
  }

  /// Updates a dependency in pubspec.yaml.
  Future<void> _updateDartDependency({
    required Directory directory,
    required File pubspecFile,
    required String dependencyName,
    required String newVersion,
    required GgLog? ggLog,
  }) async {
    final content = pubspecFile.readAsStringSync();
    final yamlMap = loadYaml(content) as Map<dynamic, dynamic>;

    final dynamic oldDep = _getDependency(dependencyName, yamlMap);
    if (oldDep == null) {
      throw Exception('Dependency $dependencyName not found.');
    }

    final sectionName = yamlMap['dependencies']?[dependencyName] != null
        ? 'dependencies'
        : 'dev_dependencies';

    final oldYaml = yamlToString(oldDep).trimRight();
    final replacement = await _buildDartReplacement(
      workspaceDirectory: directory,
      dependencyName: dependencyName,
      oldDep: oldDep,
      newVersion: newVersion,
    );

    final updated = replaceDependency(
      content,
      dependencyName,
      oldYaml,
      replacement,
      sectionName: sectionName,
    );

    if (updated == content) {
      ggLog?.call(yellow('No files were changed.'));
      return;
    }

    pubspecFile.writeAsStringSync(updated);
  }

  /// Updates a dependency in package.json.
  void _updateTypeScriptDependency({
    required File packageJsonFile,
    required String dependencyName,
    required String newVersion,
    required GgLog? ggLog,
  }) {
    final content = packageJsonFile.readAsStringSync();
    final json = jsonDecode(content) as Map<String, dynamic>;

    Map<String, dynamic>? deps;
    if (json['dependencies'] is Map) {
      deps = (json['dependencies'] as Map).cast<String, dynamic>();
    }
    Map<String, dynamic>? devDeps;
    if (json['devDependencies'] is Map) {
      devDeps = (json['devDependencies'] as Map).cast<String, dynamic>();
    }

    dynamic oldValue;
    String? section;
    if (deps != null && deps.containsKey(dependencyName)) {
      oldValue = deps[dependencyName];
      section = 'dependencies';
    } else if (devDeps != null && devDeps.containsKey(dependencyName)) {
      oldValue = devDeps[dependencyName];
      section = 'devDependencies';
    }

    if (section == null) {
      throw Exception('Dependency $dependencyName not found.');
    }

    final oldString = oldValue.toString();
    if (oldString == newVersion) {
      ggLog?.call(yellow('No files were changed.'));
      return;
    }

    if (section == 'dependencies') {
      deps![dependencyName] = newVersion;
      json['dependencies'] = deps;
    } else {
      devDeps![dependencyName] = newVersion;
      json['devDependencies'] = devDeps;
    }

    final updated = jsonEncode(json);
    packageJsonFile.writeAsStringSync('$updated\n');
  }

  /// Builds the replacement YAML for a Dart dependency.
  Future<String> _buildDartReplacement({
    required Directory workspaceDirectory,
    required String dependencyName,
    required dynamic oldDep,
    required String newVersion,
  }) async {
    final dependencyDirectory = await _findDependencyDirectory(
      workspaceDirectory: workspaceDirectory,
      dependencyName: dependencyName,
    );

    if (dependencyDirectory == null) {
      return _updateExistingTagPatternVersion(oldDep, newVersion);
    }

    final wasPublished = await _wasPublished(dependencyDirectory);
    if (wasPublished) {
      return newVersion;
    }

    final gitUrl = await _getGitRemoteUrl(dependencyDirectory, dependencyName);
    return yamlToString(<String, dynamic>{
      'git': <String, dynamic>{'url': gitUrl, 'tag_pattern': '{{version}}'},
      'version': newVersion,
    }).trimRight();
  }

  /// Preserves a tag_pattern git dependency and only updates its version.
  String _updateExistingTagPatternVersion(dynamic oldDep, String newVersion) {
    if (oldDep is Map) {
      final git = oldDep['git'];
      if (git is Map && git.containsKey('tag_pattern')) {
        final updatedGit = <String, dynamic>{
          ...git.cast<String, dynamic>(),
          'version': newVersion,
        };
        return yamlToString(<String, dynamic>{'git': updatedGit}).trimRight();
      }
    }

    return newVersion;
  }

  /// Finds the local dependency directory for [dependencyName] if available.
  Future<Directory?> _findDependencyDirectory({
    required Directory workspaceDirectory,
    required String dependencyName,
  }) async {
    try {
      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[
          DartProjectLanguage(),
          TypeScriptProjectLanguage(),
        ],
      );
      final result = await graph.buildGraph(directory: workspaceDirectory);
      final node = result.allNodes[dependencyName];
      return node?.directory;
    } catch (_) {
      return null;
    }
  }

  /// Returns true when the project in [directory] was published before.
  Future<bool> _wasPublished(Directory directory) async {
    try {
      return await isOnPubDev.get(directory: directory, ggLog: (_) {});
    } catch (_) {
      return false;
    }
  }

  /// Reads the origin URL from git for [dependencyName].
  Future<String> _getGitRemoteUrl(
    Directory directory,
    String dependencyName,
  ) async {
    final result = await Process.run('git', <String>[
      'remote',
      'get-url',
      'origin',
    ], workingDirectory: directory.path);

    if (result.exitCode != 0) {
      throw Exception(
        'Cannot get git remote url for dependency '
        '$dependencyName in ${directory.path}',
      );
    }

    return result.stdout.toString().trim();
  }
}

// ............................................................................
/// Get a dependency from the YAML map (local helper).
dynamic _getDependency(String dependencyName, Map<dynamic, dynamic> yamlMap) {
  return yamlMap['dependencies']?[dependencyName] ??
      yamlMap['dev_dependencies']?[dependencyName];
}
