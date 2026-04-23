// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';

/// TypeScript/JavaScript implementation of [ProjectLanguage].
///
/// Projects are detected via a package.json manifest file.
class TypeScriptProjectLanguage extends ProjectLanguage {
  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  @override
  ProjectLanguageId get id => ProjectLanguageId.typescript;

  @override
  String get manifestFileName => 'package.json';

  @override
  bool isProjectRoot(Directory directory) {
    final file = File('${directory.path}/$manifestFileName');
    return file.existsSync();
  }

  @override
  Future<ProjectNode> createNode(Directory directory) async {
    final manifestFile = File('${directory.path}/$manifestFileName');
    final content = await manifestFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    final name = json['name']?.toString();
    if (name == null || name.isEmpty) {
      throw FormatException(
        'package.json in ${directory.path} has no "name" field',
      );
    }

    return ProjectNode(name: name, directory: directory, language: this);
  }

  @override
  Future<Map<String, String>> readDeclaredDependencies(ProjectNode node) async {
    final manifestFile = File('${node.directory.path}/$manifestFileName');
    final content = await manifestFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    final result = <String, String>{};

    Map<String, dynamic>? deps;
    if (json['dependencies'] is Map) {
      deps = (json['dependencies'] as Map).cast<String, dynamic>();
    }
    if (deps != null) {
      for (final entry in deps.entries) {
        result[entry.key] = entry.value.toString();
      }
    }

    Map<String, dynamic>? devDeps;
    if (json['devDependencies'] is Map) {
      devDeps = (json['devDependencies'] as Map).cast<String, dynamic>();
    }
    if (devDeps != null) {
      for (final entry in devDeps.entries) {
        result[entry.key] = entry.value.toString();
      }
    }

    return result;
  }

  @override
  dynamic parseManifestContent(String content) {
    final json = jsonDecode(content);
    if (json is Map<String, dynamic>) {
      return json;
    }
    return <String, dynamic>{};
  }

  @override
  bool hasAnyDependencies(dynamic manifest) {
    return manifest is Map &&
        (manifest.containsKey('dependencies') ||
            manifest.containsKey('devDependencies'));
  }

  @override
  bool hasAnyDependencyEntries(dynamic manifest) {
    if (manifest is! Map) {
      return false;
    }

    final dependencies = manifest['dependencies'];
    final devDependencies = manifest['devDependencies'];

    return (dependencies is Map && dependencies.isNotEmpty) ||
        (devDependencies is Map && devDependencies.isNotEmpty);
  }

  @override
  DependencyReference? findDependency(dynamic manifest, String dependencyName) {
    if (manifest is! Map<String, dynamic>) {
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

    final devDependencies = manifest['devDependencies'];
    if (devDependencies is Map && devDependencies.containsKey(dependencyName)) {
      return DependencyReference(
        sectionName: 'devDependencies',
        name: dependencyName,
        value: devDependencies[dependencyName],
      );
    }

    return null;
  }

  @override
  Map<String, DependencyReference> listDependencyReferences(dynamic manifest) {
    final result = <String, DependencyReference>{};
    if (manifest is! Map<String, dynamic>) {
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
    addSection('devDependencies');
    return result;
  }

  @override
  String? readPackageVersion(dynamic manifest) {
    if (manifest is! Map<String, dynamic>) {
      return null;
    }

    return manifest['version']?.toString();
  }

  @override
  String stringifyDependencyForReading(dynamic dependencyValue) {
    return dependencyValue is String
        ? dependencyValue
        : jsonEncode(dependencyValue);
  }

  @override
  String replaceDependencyInContent({
    required String manifestContent,
    required DependencyReference reference,
    required String newValue,
  }) {
    final manifest =
        parseManifestContent(manifestContent) as Map<String, dynamic>;
    final section = manifest[reference.sectionName];
    if (section is! Map) {
      return '$manifestContent\n';
    }

    final typedSection = section.cast<String, dynamic>();
    typedSection[reference.name] = newValue;
    manifest[reference.sectionName] = typedSection;
    return '${_encoder.convert(manifest)}\n';
  }

  @override
  String stringifyManifest(dynamic manifest) {
    return '${_encoder.convert(manifest)}\n';
  }
}
