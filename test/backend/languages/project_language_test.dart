// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../test_helpers.dart';

void main() {
  group('ProjectLanguage and ProjectNode', () {
    test('ProjectLanguageId contains dart and typescript', () {
      expect(
        ProjectLanguageId.values,
        containsAll(<ProjectLanguageId>[
          ProjectLanguageId.dart,
          ProjectLanguageId.typescript,
        ]),
      );
    });

    test('ProjectManifest initializes fields correctly', () {
      final file = File('/tmp/pubspec.yaml');
      const content = 'name: pkg\nversion: 1.0.0\n';
      final parsed = <String, dynamic>{'name': 'pkg'};

      const matcherContent = 'name: pkg\nversion: 1.0.0\n';
      final manifest = ProjectManifest(
        file: file,
        content: matcherContent,
        parsed: parsed,
      );

      expect(manifest.file.path, file.path);
      expect(manifest.content, content);
      expect(manifest.parsed, same(parsed));
    });

    test('ProjectNode initializes fields and relations correctly', () {
      final language = _FakeLanguage();
      final dir = Directory('/tmp/project');

      final node = ProjectNode(
        name: 'my_pkg',
        directory: dir,
        language: language,
      );

      expect(node.name, 'my_pkg');
      expect(node.directory, dir);
      expect(node.language, same(language));
      expect(node.dependencies, isEmpty);
      expect(node.dependents, isEmpty);
    });

    test('ProjectNode.toString contains name and directory path', () {
      final language = _FakeLanguage();
      final dir = Directory('/tmp/project');

      final node = ProjectNode(
        name: 'my_pkg',
        directory: dir,
        language: language,
      );

      final description = node.toString();

      expect(description, contains('my_pkg'));
      expect(description, contains(dir.path));
    });

    test('DependencyReference stores section, name and value', () {
      const reference = DependencyReference(
        sectionName: 'dependencies',
        name: 'dep',
        value: '^1.0.0',
      );

      expect(reference.sectionName, 'dependencies');
      expect(reference.name, 'dep');
      expect(reference.value, '^1.0.0');
    });

    test('readManifest reads file content and parsed manifest', () async {
      final workspace = createTempDir('project_language_read_manifest');
      final project = Directory(p.join(workspace.path, 'project'));
      project.createSync(recursive: true);
      final file = File(p.join(project.path, 'fake.yaml'));
      file.writeAsStringSync('name: pkg\nversion: 1.0.0\n');

      final language = _FakeLanguage();
      final manifest = await language.readManifest(project);

      expect(
        manifest.file.absolute.path.replaceAll('\\', '/'),
        file.absolute.path.replaceAll('\\', '/'),
      );
      expect(manifest.content, 'name: pkg\nversion: 1.0.0\n');
      expect(manifest.parsed, <String, dynamic>{
        'content': 'name: pkg\nversion: 1.0.0\n',
      });

      deleteDirs(<Directory>[workspace]);
    });
  });
}

/// Simple fake language implementation for testing [ProjectNode].
class _FakeLanguage extends ProjectLanguage {
  @override
  ProjectLanguageId get id => ProjectLanguageId.dart;

  @override
  String get manifestFileName => 'fake.yaml';

  @override
  bool isProjectRoot(Directory directory) => true;

  @override
  Future<ProjectNode> createNode(Directory directory) async {
    return ProjectNode(name: 'fake', directory: directory, language: this);
  }

  @override
  Future<Map<String, String>> readDeclaredDependencies(ProjectNode node) async {
    return <String, String>{};
  }

  @override
  dynamic parseManifestContent(String content) {
    return <String, dynamic>{'content': content};
  }

  @override
  bool hasAnyDependencies(dynamic manifest) {
    return false;
  }

  @override
  bool hasAnyDependencyEntries(dynamic manifest) {
    return false;
  }

  @override
  DependencyReference? findDependency(dynamic manifest, String dependencyName) {
    return null;
  }

  @override
  Map<String, DependencyReference> listDependencyReferences(dynamic manifest) {
    return <String, DependencyReference>{};
  }

  @override
  String? readPackageVersion(dynamic manifest) {
    return null;
  }

  @override
  String stringifyDependencyForReading(dynamic dependencyValue) {
    return dependencyValue.toString();
  }

  @override
  String replaceDependencyInContent({
    required String manifestContent,
    required DependencyReference reference,
    required String newValue,
  }) {
    return manifestContent;
  }

  @override
  String stringifyManifest(dynamic manifest) {
    return '';
  }
}
