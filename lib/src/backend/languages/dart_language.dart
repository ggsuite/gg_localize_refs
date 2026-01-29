// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';

/// Dart implementation of [ProjectLanguage].
class DartProjectLanguage extends ProjectLanguage {
  @override
  ProjectLanguageId get id => ProjectLanguageId.dart;

  @override
  String get manifestFileName => 'pubspec.yaml';

  @override
  bool isProjectRoot(Directory directory) {
    final file = File('${directory.path}/$manifestFileName');
    return file.existsSync();
  }

  @override
  Future<ProjectNode> createNode(Directory directory) async {
    final pubspecFile = File('${directory.path}/$manifestFileName');
    final content = await pubspecFile.readAsString();

    late Pubspec pubspec;
    try {
      pubspec = Pubspec.parse(content);
    } catch (e) {
      throw Exception(red('Error parsing pubspec.yaml:') + e.toString());
    }

    return ProjectNode(
      name: pubspec.name,
      directory: directory,
      language: this,
    );
  }

  @override
  Future<Map<String, String>> readDeclaredDependencies(ProjectNode node) async {
    final pubspecFile = File('${node.directory.path}/$manifestFileName');
    final content = await pubspecFile.readAsString();

    dynamic yaml;
    try {
      yaml = loadYaml(content);
    } catch (e) {
      throw Exception(red('Error parsing pubspec.yaml:') + e.toString());
    }

    if (yaml is! Map) {
      throw Exception(
        '${red('Error parsing pubspec.yaml:')} Root node is not a map.',
      );
    }

    final result = <String, String>{};

    void addDeps(String sectionKey) {
      final section = yaml[sectionKey];
      if (section is! Map) {
        return;
      }
      section.forEach((dynamic key, dynamic value) {
        if (key == null) {
          return;
        }
        final name = key.toString();
        final spec = value?.toString() ?? 'null';
        result[name] = spec;
      });
    }

    addDeps('dependencies');
    addDeps('dev_dependencies');

    return result;
  }

  @override
  dynamic parseManifestContent(String content) {
    final yaml = loadYaml(content);
    if (yaml is Map) {
      return yaml;
    }
    return <String, dynamic>{};
  }
}
