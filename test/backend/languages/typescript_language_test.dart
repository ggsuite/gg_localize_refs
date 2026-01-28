// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

import '../../test_helpers.dart';

void main() {
  group('TypeScriptProjectLanguage', () {
    late TypeScriptProjectLanguage language;
    late Directory workspace;

    setUp(() {
      language = TypeScriptProjectLanguage();
      workspace = createTempDir('ts_lang_ws');
    });

    tearDown(() {
      deleteDirs(<Directory>[workspace]);
    });

    test('isProjectRoot returns true only when package.json exists', () {
      final projectDir = Directory(join(workspace.path, 'project'));
      createDirs(<Directory>[projectDir]);

      final manifest = File(join(projectDir.path, 'package.json'));
      expect(language.isProjectRoot(projectDir), isFalse);

      manifest.writeAsStringSync('{"name":"test","version":"1.0.0"}');

      expect(language.isProjectRoot(projectDir), isTrue);
    });

    test('createNode reads name from package.json', () async {
      final projectDir = Directory(join(workspace.path, 'project1'));
      createDirs(<Directory>[projectDir]);

      File(
        join(projectDir.path, 'package.json'),
      ).writeAsStringSync('{"name":"my_ts_pkg","version":"1.0.0"}');

      final node = await language.createNode(projectDir);

      expect(node.name, 'my_ts_pkg');
      expect(node.directory.path, projectDir.path);
      expect(node.language, same(language));
    });

    test('createNode throws when name is missing', () async {
      final projectDir = Directory(join(workspace.path, 'project_no_name'));
      createDirs(<Directory>[projectDir]);

      File(
        join(projectDir.path, 'package.json'),
      ).writeAsStringSync('{"version":"1.0.0"}');

      await expectLater(
        language.createNode(projectDir),
        throwsA(
          isA<FormatException>().having(
            (Object e) => e.toString(),
            'message',
            contains('has no "name" field'),
          ),
        ),
      );
    });

    test('readDeclaredDependencies merges '
        'dependencies and devDependencies', () async {
      final projectDir = Directory(join(workspace.path, 'deps_project'));
      createDirs(<Directory>[projectDir]);

      File(join(projectDir.path, 'package.json')).writeAsStringSync(
        '{"name":"deps_project","version":"1.0.0",'
        '"dependencies":{"a":"^1.0.0"},'
        '"devDependencies":{"b":"^2.0.0"}}',
      );

      final node = await language.createNode(projectDir);
      final deps = await language.readDeclaredDependencies(node);

      expect(deps['a'], '^1.0.0');
      expect(deps['b'], '^2.0.0');
      expect(deps.length, 2);
    });

    test('parseManifestContent returns empty map for non-object JSON', () {
      final result = language.parseManifestContent('["a","b"]');

      expect(result, isA<Map<String, dynamic>>());
      expect(result, isEmpty);
    });
  });
}
