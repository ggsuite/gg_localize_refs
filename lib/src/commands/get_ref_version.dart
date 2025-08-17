// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:yaml/yaml.dart';

// #############################################################################
/// Command that reads the current version/spec of a dependency from pubspec.yaml
class GetRefVersion extends DirCommand<dynamic> {
  /// Constructor
  GetRefVersion({required super.ggLog})
    : super(
        name: 'get-ref-version',
        description:
            'Reads the current version/spec of a dependency from pubspec.yaml.',
      ) {
    argParser.addOption('ref', help: 'The dependency name to read.');
  }

  // ...........................................................................
  @override
  Future<String?> get({
    required Directory directory,
    GgLog? ggLog,
    String? ref,
  }) async {
    ggLog?.call('Running get-ref-version in ${directory.path}');

    final String? dependencyName = ref ?? (argResults?['ref'] as String?);
    if (dependencyName == null || dependencyName.isEmpty) {
      throw Exception(red('Please provide a dependency name via --ref.'));
    }

    try {
      // Resolve pubspec.yaml in the provided directory directly.
      final pubspec = File('${directory.path}/pubspec.yaml');
      if (!pubspec.existsSync()) {
        throw Exception('pubspec.yaml not found at ${pubspec.path}');
      }

      // Read pubspec content
      final content = pubspec.readAsStringSync();

      // Also load YAML as Map to access dependency values
      final yamlMap = loadYaml(content) as Map<dynamic, dynamic>;

      final dynamic value = getDependency2(dependencyName, yamlMap);
      if (value == null) {
        ggLog?.call(yellow('Dependency $dependencyName not found.'));
        return null;
      }

      ggLog?.call(yamlToString(value).trimRight());
      return yamlToString(value).trimRight();
    } catch (e) {
      throw Exception(red('An error occurred: $e'));
    }
  }
}

// ............................................................................
/// Get a dependency from the YAML map (re-export helper for this file)
dynamic getDependency2(String dependencyName, Map<dynamic, dynamic> yamlMap) {
  return yamlMap['dependencies']?[dependencyName] ??
      yamlMap['dev_dependencies']?[dependencyName];
}
