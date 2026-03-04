// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:test/test.dart';

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
    return <String, dynamic>{};
  }
}
