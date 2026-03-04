// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:test/test.dart';

import '../../test_helpers.dart';

void main() {
  group('DartProjectLanguage', () {
    late DartProjectLanguage language;
    late List<Directory> tempDirs;

    setUp(() {
      language = DartProjectLanguage();
      tempDirs = <Directory>[];
    });

    tearDown(() {
      deleteDirs(tempDirs);
    });

    Directory createTempProject(String suffix) {
      final dir = createTempDir(suffix, 'project');
      tempDirs.add(dir);
      return dir;
    }

    test('isProjectRoot returns true when pubspec.yaml exists', () {
      final dir = createTempProject('dart_lang_is_root_true');
      File(
        '${dir.path}/pubspec.yaml',
      ).writeAsStringSync('name: test_pkg\nversion: 1.0.0');

      expect(language.isProjectRoot(dir), isTrue);
    });

    test('isProjectRoot returns false when pubspec.yaml is missing', () {
      final dir = createTempProject('dart_lang_is_root_false');

      expect(language.isProjectRoot(dir), isFalse);
    });

    test(
      'createNode parses pubspec.yaml and sets name and directory',
      () async {
        final dir = createTempProject('dart_lang_create_node');
        File(
          '${dir.path}/pubspec.yaml',
        ).writeAsStringSync('name: my_package\nversion: 1.0.0');

        final node = await language.createNode(dir);

        expect(node.name, 'my_package');
        expect(node.directory.path, dir.path);
        expect(node.language, same(language));
      },
    );

    test('createNode throws when pubspec.yaml cannot be parsed', () async {
      final dir = createTempProject('dart_lang_create_node_invalid');
      File('${dir.path}/pubspec.yaml').writeAsStringSync('invalid yaml');

      await expectLater(
        language.createNode(dir),
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
      'readDeclaredDependencies returns dependencies and dev_dependencies',
      () async {
        final dir = createTempProject('dart_lang_read_deps');
        File('${dir.path}/pubspec.yaml').writeAsStringSync(
          'name: pkg\n'
          'version: 1.0.0\n'
          'dependencies:\n'
          '  a: ^1.0.0\n'
          'dev_dependencies:\n'
          '  b: ^2.0.0\n',
        );

        final node = await language.createNode(dir);
        final deps = await language.readDeclaredDependencies(node);

        expect(deps.length, 2);
        expect(deps['a'], 'HostedDependency: ^1.0.0');
        expect(deps['b'], 'HostedDependency: ^2.0.0');
      },
    );

    test('parseManifestContent returns a Map for valid YAML', () {
      const content = 'name: pkg\nversion: 1.0.0\ndependencies:\n  a: ^1.0.0\n';

      final manifest = language.parseManifestContent(content) as Map;

      expect(manifest['name'], 'pkg');
      expect(manifest['version'], '1.0.0');
      expect((manifest['dependencies'] as Map)['a'], '^1.0.0');
    });

    test('parseManifestContent returns empty Map for non-Map YAML root', () {
      const content = 'just a scalar value';

      final manifest = language.parseManifestContent(content) as Map;

      expect(manifest, isEmpty);
    });
  });
}
