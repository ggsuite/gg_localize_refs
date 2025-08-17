// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights
// Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/replace_dependency.dart';
import 'package:gg_localize_refs/src/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:yaml/yaml.dart';

// #############################################################################
/// Command that sets the version/spec of a dependency in pubspec.yaml
///
/// This command operates directly on the pubspec.yaml in the provided
/// input directory. It does not traverse a workspace or use project graphs.
class SetRefVersion extends DirCommand<dynamic> {
  /// Constructor
  SetRefVersion({required super.ggLog})
    : super(
        name: 'set-ref-version',
        description: 'Sets the version/spec of a dependency in pubspec.yaml.',
      ) {
    argParser
      ..addOption('ref', help: 'The dependency name to change.')
      ..addOption(
        'version',
        help:
            'The new version/spec. Can be a scalar (e.g., ^1.2.3) '
            'or a YAML block.',
      );
  }

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    required GgLog? ggLog,
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
      if (!pubspec.existsSync()) {
        throw Exception('pubspec.yaml not found at ${pubspec.path}');
      }

      final content = pubspec.readAsStringSync();

      final yamlMap = loadYaml(content) as Map<dynamic, dynamic>;

      final dynamic oldDep = _getDependency(dependencyName, yamlMap);
      if (oldDep == null) {
        throw Exception('Dependency $dependencyName not found.');
      }

      final sectionName = yamlMap['dependencies']?[dependencyName] != null
          ? 'dependencies'
          : 'dev_dependencies';

      final oldYaml = yamlToString(oldDep).trimRight();

      final updated = replaceDependency(
        content,
        dependencyName,
        oldYaml,
        newVersion,
        sectionName: sectionName,
      );

      if (updated == content) {
        ggLog?.call(yellow('No files were changed.'));
        return;
      }

      pubspec.writeAsStringSync(updated);
    } catch (e) {
      throw Exception(red('An error occurred: $e. No files were changed.'));
    }
  }
}

// .............................................................................
/// Get a dependency from the YAML map (local helper)
dynamic _getDependency(String dependencyName, Map<dynamic, dynamic> yamlMap) {
  return yamlMap['dependencies']?[dependencyName] ??
      yamlMap['dev_dependencies']?[dependencyName];
}
