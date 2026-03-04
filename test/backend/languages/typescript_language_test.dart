// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:test/test.dart';

import '../../test_helpers.dart';

void main() {
  group('TypeScriptProjectLanguage', () {
    late TypeScriptProjectLanguage language;
    late List<Directory> tempDirs;

    setUp(() {
      language = TypeScriptProjectLanguage();
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

    test('isProjectRoot returns true when package.json exists', () {
      final dir = createTempProject('ts_lang_is_root_true');
      File(
        '${dir.path}/package.json',
      ).writeAsStringSync('{"name":"pkg","version":"1.0.0"}');

      expect(language.isProjectRoot(dir), isTrue);
    });

    test('isProjectRoot returns false when package.json is missing', () {
      final dir = createTempProject('ts_lang_is_root_false');

      expect(language.isProjectRoot(dir), isFalse);
    });

    test(
      'createNode parses package.json and sets name and directory',
      () async {
        final dir = createTempProject('ts_lang_create_node');
        File(
          '${dir.path}/package.json',
        ).writeAsStringSync('{"name":"my_ts_pkg","version":"1.0.0"}');

        final node = await language.createNode(dir);

        expect(node.name, 'my_ts_pkg');
        expect(node.directory.path, dir.path);
        expect(node.language, same(language));
      },
    );

    test('createNode throws when name field is missing', () async {
      final dir = createTempProject('ts_lang_create_node_invalid');
      File('${dir.path}/package.json').writeAsStringSync('{"version":"1.0.0"}');

      await expectLater(
        language.createNode(dir),
        throwsA(
          isA<FormatException>().having(
            (Object e) => e.toString(),
            'message',
            contains('has no "name" field'),
          ),
        ),
      );
    });

    test(
      'readDeclaredDependencies returns dependencies and devDependencies',
      () async {
        final dir = createTempProject('ts_lang_read_deps');
        File('${dir.path}/package.json').writeAsStringSync(
          '{"name":"pkg","version":"1.0.0","dependencies":'
          '{"a":"^1.0.0"},"devDependencies":{"b":"^2.0.0"}}',
        );

        final node = await language.createNode(dir);
        final deps = await language.readDeclaredDependencies(node);

        expect(deps.length, 2);
        expect(deps['a'], '^1.0.0');
        expect(deps['b'], '^2.0.0');
      },
    );

    test('parseManifestContent returns Map for valid JSON object', () {
      const content = '{"name":"pkg","version":"1.0.0"}';

      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;

      expect(manifest['name'], 'pkg');
      expect(manifest['version'], '1.0.0');
    });

    test('parseManifestContent returns empty Map for non-object JSON', () {
      const content = '"just a string"';

      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;

      expect(manifest, isEmpty);
    });
  });
}
