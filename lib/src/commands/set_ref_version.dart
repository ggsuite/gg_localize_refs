// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/replace_dependency.dart';
import 'package:gg_localize_refs/src/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

// #############################################################################
/// Command that sets the version/spec of a dependency in pubspec.yaml
///
/// This command operates directly on the pubspec.yaml in the provided
/// input directory. It does not traverse a workspace or use project graphs.
class SetRefVersion extends DirCommand<dynamic> {
  /// Constructor
  SetRefVersion({
    required super.ggLog,
  }) : super(
          name: 'set-ref-version',
          description: 'Sets the version/spec of a dependency in pubspec.yaml.',
        ) {
    argParser
      ..addOption('ref', help: 'The dependency name to change.')
      ..addOption(
        'version',
        help:
            'The new version/spec. Can be a scalar (e.g., ^1.2.3) or a YAML block.',
      );
  }

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    String? ref,
    String? version,
  }) async {
    ggLog('Running set-ref-version in ${directory.path}');

    final String? dependencyName = ref ?? (argResults?['ref'] as String?);
    final String? newVersion = version ?? (argResults?['version'] as String?);

    if (dependencyName == null || dependencyName.isEmpty) {
      throw Exception(red('Please provide a dependency name via --ref.'));
    }
    if (newVersion == null) {
      throw Exception(red('Please provide the new version via --version.'));
    }

    try {
      // Resolve pubspec.yaml in the provided directory directly.
      final pubspec = File('${directory.path}/pubspec.yaml');
      if (!pubspec.existsSync()) {
        throw Exception('pubspec.yaml not found at ${pubspec.path}');
      }

      // Read pubspec content
      final content = pubspec.readAsStringSync();

      // Validate YAML by parsing with Pubspec.parse to keep consistent errors
      try {
        // ignore: unused_local_variable
        final _ = Pubspec.parse(content);
      } catch (e) {
        throw Exception(red('Error parsing pubspec.yaml:') + e.toString());
      }

      // Also load YAML as Map to access dependency values
      final yamlMap = loadYaml(content) as Map<dynamic, dynamic>;

      final dynamic oldDep = getDependency3(dependencyName, yamlMap);
      if (oldDep == null) {
        throw Exception('Dependency $dependencyName not found.');
      }

      final oldYaml = yamlToString(oldDep);
      final newYaml = newVersion;

      final updated = replaceDependency(
        content,
        dependencyName,
        oldYaml,
        newYaml,
      );

      if (updated == content) {
        ggLog(yellow('No files were changed.'));
        return;
      }

      pubspec.writeAsStringSync(updated);
    } catch (e) {
      throw Exception(red('An error occurred: $e. No files were changed.'));
    }
  }
}

// .............................................................................
/// Get a dependency from the YAML map (re-export helper for this file)
dynamic getDependency3(String dependencyName, Map<dynamic, dynamic> yamlMap) {
  return yamlMap['dependencies']?[dependencyName] ??
      yamlMap['dev_dependencies']?[dependencyName];
}
