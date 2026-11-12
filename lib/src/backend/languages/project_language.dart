// @license
// Copyright (c) ggsuite
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

/// Describes where a dependency was found inside a manifest.
class DependencyReference {
  /// Creates a dependency reference.
  const DependencyReference({
    required this.sectionName,
    required this.name,
    required this.value,
  });

  /// The section name that contains the dependency.
  final String sectionName;

  /// The dependency name.
  final String name;

  /// The raw dependency value from the manifest.
  final dynamic value;
}

/// Holds a manifest file together with its parsed representation.
class ProjectManifest {
  /// Creates a project manifest.
  const ProjectManifest({
    required this.file,
    required this.content,
    required this.parsed,
  });

  /// The manifest file on disk.
  final File file;

  /// The raw manifest content.
  final String content;

  /// The parsed language specific manifest object.
  final dynamic parsed;
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

  /// Names of workspace projects this one needs only as a dev dependency.
  ///
  /// Such an edge may close a cycle - see the circular dependency check
  /// of `MultiLanguageGraph`.
  final Set<String> devOnlyDependencies = <String>{};

  /// Workspace projects this one reaches only through packages outside the
  /// workspace: a dependency that is no workspace project, but whose
  /// manifest - found in the ocean of the gg workspace - leads, directly or
  /// through further such packages, to a workspace project.
  ///
  /// Filled by `MultiLanguageGraph`. Unlike [dependencies], these edges are
  /// not part of the manifest of this project, so nothing rewrites a
  /// reference for them - they only widen [transitiveDependencies].
  final Map<String, ProjectNode> indirectDependencies = <String, ProjectNode>{};

  /// Names of [indirectDependencies] reached only through a dev dependency
  /// of this project.
  final Set<String> devOnlyIndirectDependencies = <String>{};

  /// Every workspace project this one needs, directly or indirectly.
  ///
  /// Pub honors `dependency_overrides` only from the **root** package of a
  /// resolution: an override that a dependency declares for its own
  /// dependency is ignored. A package therefore has to override the whole
  /// part of the workspace it reaches, not only what its own manifest names -
  /// otherwise a project two steps down is resolved from the registry while
  /// its siblings come from the ticket, and the published version has to
  /// satisfy the local sources.
  ///
  /// The walk follows [dependencies] and [indirectDependencies], so a chain
  /// passing through packages outside the workspace is covered too. It
  /// mirrors what pub and pnpm resolve: the dev dependencies of this project
  /// count, those of every other package do not - an override for a project
  /// the resolution does not need would still pull that project and its
  /// whole dependency tree into it.
  ///
  /// The walk terminates on any graph: the visited set collapses a diamond
  /// and stops a cycle - `MultiLanguageGraph` rejects only cycles of regular
  /// dependencies between workspace projects.
  Map<String, ProjectNode> get transitiveDependencies {
    final result = <String, ProjectNode>{};

    void visit(ProjectNode node, {required bool isRoot}) {
      final reached = <String, ProjectNode>{
        for (final entry in node.dependencies.entries)
          if (isRoot || !node.devOnlyDependencies.contains(entry.key))
            entry.key: entry.value,
        for (final entry in node.indirectDependencies.entries)
          if (isRoot || !node.devOnlyIndirectDependencies.contains(entry.key))
            entry.key: entry.value,
      };

      for (final entry in reached.entries) {
        if (entry.key == name || result.containsKey(entry.key)) {
          continue;
        }
        result[entry.key] = entry.value;
        visit(entry.value, isRoot: false);
      }
    }

    visit(this, isRoot: true);
    return result;
  }

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

  /// Returns the declared dependency names that appear only in the dev
  /// section of the manifest, not in the regular one.
  Future<Set<String>> readDeclaredDevOnlyDependencies(ProjectNode node);

  /// Parses the manifest content and returns a language specific structure.
  ///
  /// For Dart this is typically a `Map<dynamic, dynamic>` created via
  /// `loadYaml`, for TypeScript a `Map<String, dynamic>` created via
  /// `jsonDecode`.
  dynamic parseManifestContent(String content);

  /// Reads and parses the manifest for [directory].
  Future<ProjectManifest> readManifest(Directory directory) async {
    final file = File('${directory.path}/$manifestFileName');
    final content = await file.readAsString();
    return ProjectManifest(
      file: file,
      content: content,
      parsed: parseManifestContent(content),
    );
  }

  /// Returns true when [manifest] contains at least one dependency section.
  bool hasAnyDependencies(dynamic manifest);

  /// Returns true when [manifest] contains at least one dependency entry.
  bool hasAnyDependencyEntries(dynamic manifest);

  /// Finds [dependencyName] in the manifest and returns its reference.
  DependencyReference? findDependency(dynamic manifest, String dependencyName);

  /// Returns all known dependency references indexed by dependency name.
  Map<String, DependencyReference> listDependencyReferences(dynamic manifest);

  /// Extracts the version from the root manifest.
  String? readPackageVersion(dynamic manifest);

  /// Returns the display value for a dependency when reading it.
  String stringifyDependencyForReading(dynamic dependencyValue);

  /// Builds new manifest content after replacing one dependency.
  String replaceDependencyInContent({
    required String manifestContent,
    required DependencyReference reference,
    required String newValue,
  });

  /// Builds new manifest content after writing [manifest].
  String stringifyManifest(dynamic manifest);
}
