// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:yaml/yaml.dart';

// #############################################################################
/// Command that reads the current version/spec of a dependency from
/// pubspec.yaml or package.json.
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
      final pubspec = File('${directory.path}/pubspec.yaml');
      final packageJson = File('${directory.path}/package.json');

      if (!pubspec.existsSync() && !packageJson.existsSync()) {
        throw Exception('pubspec.yaml not found at ${pubspec.path}');
      }

      if (pubspec.existsSync()) {
        final content = pubspec.readAsStringSync();
        final yamlMap = loadYaml(content) as Map<dynamic, dynamic>;

        final dynamic value = getDependency2(dependencyName, yamlMap);
        if (value == null) {
          ggLog?.call(yellow('Dependency $dependencyName not found.'));
          return null;
        }

        final result = yamlToString(value).trimRight();
        ggLog?.call(result);
        return result;
      }

      final content = packageJson.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;

      dynamic value;
      if (json['dependencies'] is Map) {
        value =
            (json['dependencies'] as Map)[dependencyName] ??
            (json['dependencies'] as Map<String, dynamic>)[dependencyName];
      }
      if (value == null && json['devDependencies'] is Map) {
        value =
            (json['devDependencies'] as Map)[dependencyName] ??
            (json['devDependencies'] as Map<String, dynamic>)[dependencyName];
      }

      if (value == null) {
        ggLog?.call(yellow('Dependency $dependencyName not found.'));
        return null;
      }

      final result = value is String ? value : jsonEncode(value);
      ggLog?.call(result);
      return result;
    } catch (e) {
      throw Exception(red('An error occurred: $e'));
    }
  }
}

// ............................................................................
/// Get a dependency from the YAML map
/// (helper for pubspec.yaml based projects)
dynamic getDependency2(String dependencyName, Map<dynamic, dynamic> yamlMap) {
  return yamlMap['dependencies']?[dependencyName] ??
      yamlMap['dev_dependencies']?[dependencyName];
}
