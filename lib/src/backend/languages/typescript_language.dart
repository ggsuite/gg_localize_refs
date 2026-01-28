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

    return ProjectNode(
      name: name,
      directory: directory,
      language: this,
    );
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
}
