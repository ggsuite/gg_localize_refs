// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:test/test.dart';

import '../../test_helpers.dart';

void main() {
  group('ProjectNode', () {
    test('stores name, directory and language '
        'and provides a readable toString', () {
      final dir = createTempDir('project_node_test');
      final language = _FakeLanguage();

      final node = ProjectNode(
        name: 'my_package',
        directory: dir,
        language: language,
      );

      expect(node.name, 'my_package');
      expect(node.directory.path, dir.path);
      expect(node.language, same(language));
      expect(node.dependencies, isEmpty);
      expect(node.dependents, isEmpty);

      final text = node.toString();
      expect(text, contains('my_package'));
      expect(text, contains(dir.path));

      deleteDirs(<Directory>[dir]);
    });
  });
}

/// Minimal fake language used only for testing [ProjectNode].
class _FakeLanguage extends ProjectLanguage {
  @override
  ProjectLanguageId get id => ProjectLanguageId.dart;

  @override
  String get manifestFileName => 'pubspec.yaml';

  @override
  bool isProjectRoot(Directory directory) => false;

  @override
  Future<ProjectNode> createNode(Directory directory) {
    throw UnimplementedError('createNode is not needed in this test.');
  }

  @override
  Future<Map<String, String>> readDeclaredDependencies(ProjectNode node) {
    throw UnimplementedError(
      'readDeclaredDependencies is not needed in this test.',
    );
  }

  @override
  dynamic parseManifestContent(String content) => <String, dynamic>{};
}
