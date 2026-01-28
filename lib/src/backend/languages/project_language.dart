// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

/// Supported project languages.
enum ProjectLanguageId {
  /// Dart projects using pubspec.yaml
  dart,

  /// TypeScript/JavaScript projects using package.json
  typescript,
}

/// Represents a generic project node independent of the concrete language.
class ProjectNode {
  /// Creates a project node.
  ProjectNode({
    required this.name,
    required this.directory,
    required this.language,
  });

  /// The package or project name.
  final String name;

  /// The directory that contains the manifest file.
  final Directory directory;

  /// The language implementation that knows how to handle this project.
  final ProjectLanguage language;

  /// Nodes this project depends on.
  final Map<String, ProjectNode> dependencies = <String, ProjectNode>{};

  /// Nodes that depend on this project.
  final Map<String, ProjectNode> dependents = <String, ProjectNode>{};

  @override
  String toString() {
    return 'ProjectNode{name: $name, directory: ${directory.path}}';
  }
}

/// Describes language specific behavior required by the multi language graph
/// and higher level commands.
abstract class ProjectLanguage {
  /// The language identifier.
  ProjectLanguageId get id;

  /// The manifest file name, e.g. pubspec.yaml or package.json.
  String get manifestFileName;

  /// Returns true if [directory] is a project root for this language.
  bool isProjectRoot(Directory directory);

  /// Creates a [ProjectNode] for the project located in [directory].
  ///
  /// Implementations should validate and parse the manifest and throw
  /// meaningful exceptions if parsing fails.
  Future<ProjectNode> createNode(Directory directory);

  /// Returns all declared dependencies for [node].
  ///
  /// The returned map contains the dependency name as key and the raw
  /// version or spec string as value. Only names are required to build
  /// the workspace graph.
  Future<Map<String, String>> readDeclaredDependencies(ProjectNode node);

  /// Parses the manifest content and returns a language specific structure.
  ///
  /// For Dart this is typically a `Map<dynamic, dynamic>` created via
  /// `loadYaml`, for TypeScript a `Map<String, dynamic>` created via
  /// `jsonDecode`.
  dynamic parseManifestContent(String content);
}
