// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/replace_dependency.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

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

    late Pubspec pubspec;
    try {
      pubspec = Pubspec.parse(content);
    } catch (e) {
      throw Exception(red('Error parsing pubspec.yaml:') + e.toString());
    }

    final result = <String, String>{};

    for (final entry in pubspec.dependencies.entries) {
      result[entry.key] = entry.value.toString();
    }

    for (final entry in pubspec.devDependencies.entries) {
      result[entry.key] = entry.value.toString();
    }

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

  @override
  bool hasAnyDependencies(dynamic manifest) {
    return manifest is Map &&
        (manifest.containsKey('dependencies') ||
            manifest.containsKey('dev_dependencies'));
  }

  @override
  bool hasAnyDependencyEntries(dynamic manifest) {
    if (manifest is! Map) {
      return false;
    }

    final dependencies = manifest['dependencies'];
    final devDependencies = manifest['dev_dependencies'];

    return (dependencies is Map && dependencies.isNotEmpty) ||
        (devDependencies is Map && devDependencies.isNotEmpty);
  }

  @override
  DependencyReference? findDependency(dynamic manifest, String dependencyName) {
    if (manifest is! Map) {
      return null;
    }

    final dependencies = manifest['dependencies'];
    if (dependencies is Map && dependencies.containsKey(dependencyName)) {
      return DependencyReference(
        sectionName: 'dependencies',
        name: dependencyName,
        value: dependencies[dependencyName],
      );
    }

    final devDependencies = manifest['dev_dependencies'];
    if (devDependencies is Map && devDependencies.containsKey(dependencyName)) {
      return DependencyReference(
        sectionName: 'dev_dependencies',
        name: dependencyName,
        value: devDependencies[dependencyName],
      );
    }

    return null;
  }

  @override
  Map<String, DependencyReference> listDependencyReferences(dynamic manifest) {
    final result = <String, DependencyReference>{};
    if (manifest is! Map) {
      return result;
    }

    void addSection(String sectionName) {
      final section = manifest[sectionName];
      if (section is! Map) {
        return;
      }

      for (final entry in section.entries) {
        final name = entry.key.toString();
        result.putIfAbsent(
          name,
          () => DependencyReference(
            sectionName: sectionName,
            name: name,
            value: entry.value,
          ),
        );
      }
    }

    addSection('dependencies');
    addSection('dev_dependencies');
    return result;
  }

  @override
  String? readPackageVersion(dynamic manifest) {
    if (manifest is! Map) {
      return null;
    }

    final version = manifest['version'];
    return version?.toString();
  }

  @override
  String stringifyDependencyForReading(dynamic dependencyValue) {
    if (dependencyValue is Map) {
      final git = dependencyValue['git'];
      if (git is Map && git.containsKey('tag_pattern')) {
        return dependencyValue['version'].toString();
      }
    }

    return yamlToString(dependencyValue).trimRight();
  }

  @override
  String replaceDependencyInContent({
    required String manifestContent,
    required DependencyReference reference,
    required String newValue,
  }) {
    final oldValue = yamlToString(reference.value).trimRight();
    return replaceDependency(
      manifestContent,
      reference.name,
      oldValue,
      newValue,
      sectionName: reference.sectionName,
    );
  }

  @override
  String stringifyManifest(dynamic manifest) {
    return yamlToString(manifest).trimRight();
  }
}
