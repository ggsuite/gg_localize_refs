// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

import '../../test_helpers.dart';

void main() {
  group('DartProjectLanguage', () {
    late DartProjectLanguage language;
    late Directory workspace;

    setUp(() {
      language = DartProjectLanguage();
      workspace = createTempDir('dart_lang_ws');
    });

    tearDown(() {
      deleteDirs(<Directory>[workspace]);
    });

    test('exposes correct id and manifestFileName', () {
      expect(language.id, ProjectLanguageId.dart);
      expect(language.manifestFileName, 'pubspec.yaml');
    });

    test('isProjectRoot returns true only when pubspec.yaml exists', () {
      final projectDir = Directory(join(workspace.path, 'project'));
      createDirs(<Directory>[projectDir]);

      // No pubspec.yaml yet.
      expect(language.isProjectRoot(projectDir), isFalse);

      File(
        join(projectDir.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: my_pkg\nversion: 1.0.0\n');

      expect(language.isProjectRoot(projectDir), isTrue);
    });

    test('createNode parses pubspec.yaml and returns ProjectNode', () async {
      final projectDir = Directory(join(workspace.path, 'project1'));
      createDirs(<Directory>[projectDir]);

      File(
        join(projectDir.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: my_pkg\nversion: 1.0.0\n');

      final node = await language.createNode(projectDir);

      expect(node.name, 'my_pkg');
      expect(node.directory.path, projectDir.path);
      expect(node.language, same(language));
    });

    test('createNode throws when pubspec.yaml cannot be parsed', () async {
      final projectDir = Directory(join(workspace.path, 'invalid_project'));
      createDirs(<Directory>[projectDir]);

      File(
        join(projectDir.path, 'pubspec.yaml'),
      ).writeAsStringSync('invalid yaml');

      await expectLater(
        language.createNode(projectDir),
        throwsA(
          isA<Exception>().having(
            (Object e) => e.toString(),
            'message',
            contains('Error parsing pubspec.yaml'),
          ),
        ),
      );
    });

    test(
      'readDeclaredDependencies merges dependencies and dev_dependencies',
      () async {
        final projectDir = Directory(join(workspace.path, 'deps_project'));
        createDirs(<Directory>[projectDir]);

        File(join(projectDir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: deps_project\n'
          'version: 1.0.0\n'
          'dependencies:\n'
          '  a: ^1.0.0\n'
          'dev_dependencies:\n'
          '  b: ^2.0.0\n',
        );

        final node = await language.createNode(projectDir);
        final deps = await language.readDeclaredDependencies(node);

        expect(deps['a'], '^1.0.0');
        expect(deps['b'], '^2.0.0');
        expect(deps.length, 2);
      },
    );

    test(
      'readDeclaredDependencies throws when pubspec.yaml cannot be parsed',
      () async {
        final projectDir = Directory(join(workspace.path, 'deps_invalid'));
        createDirs(<Directory>[projectDir]);

        File(join(projectDir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: deps_invalid\n'
          'version: 1.0.0\n'
          'dependencies: : invalid',
        );

        // Construct a ProjectNode directly so
        // that only readDeclaredDependencies
        // is under test (createNode would already fail on this pubspec).
        final node = ProjectNode(
          name: 'deps_invalid',
          directory: projectDir,
          language: language,
        );

        await expectLater(
          language.readDeclaredDependencies(node),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('Error parsing pubspec.yaml'),
            ),
          ),
        );
      },
    );

    test('parseManifestContent returns a map for valid YAML content', () {
      const yaml = 'name: pkg\nversion: 1.0.0\n';

      final result = language.parseManifestContent(yaml);

      expect(result['name'], 'pkg');
      expect(result['version'], '1.0.0');
    });

    test('parseManifestContent returns empty map when root is not a map', () {
      const yaml = '- a\n- b\n';

      final result = language.parseManifestContent(yaml);

      expect(result, isEmpty);
    });
  });
}
