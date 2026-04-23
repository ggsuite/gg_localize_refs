// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights
// Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
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

    test('id returns ProjectLanguageId.typescript', () {
      expect(language.id, ProjectLanguageId.typescript);
    });

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

    test('hasAnyDependencies returns true for dependencies', () {
      const content = '{"dependencies":{"dep":"^1.0.0"}}';
      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;

      expect(language.hasAnyDependencies(manifest), isTrue);
    });

    test('hasAnyDependencies returns true for devDependencies', () {
      const content = '{"devDependencies":{"dep":"^1.0.0"}}';
      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;

      expect(language.hasAnyDependencies(manifest), isTrue);
    });

    test('hasAnyDependencyEntries returns false for non-map manifest', () {
      expect(language.hasAnyDependencyEntries('not_a_map'), isFalse);
    });

    test('hasAnyDependencyEntries returns false for empty sections', () {
      const content = '{"dependencies":{},"devDependencies":{}}';
      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;

      expect(language.hasAnyDependencyEntries(manifest), isFalse);
    });

    test('hasAnyDependencyEntries returns true for dependencies entries', () {
      const content = '{"dependencies":{"dep":"^1.0.0"}}';
      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;

      expect(language.hasAnyDependencyEntries(manifest), isTrue);
    });

    test('hasAnyDependencyEntries returns true for '
        'devDependencies entries', () {
      const content = '{"devDependencies":{"dep":"^1.0.0"}}';
      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;

      expect(language.hasAnyDependencyEntries(manifest), isTrue);
    });

    test('findDependency returns dependency from devDependencies', () {
      const content = '{"name":"pkg","devDependencies":{"dep":"^2.0.0"}}';

      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;
      final reference = language.findDependency(manifest, 'dep');

      expect(reference, isNotNull);
      expect(reference!.sectionName, 'devDependencies');
      expect(reference.value, '^2.0.0');
    });

    test('listDependencyReferences returns both dependency sections', () {
      const content =
          '{"name":"pkg","dependencies":{"a":"^1.0.0"},'
          '"devDependencies":{"b":"^2.0.0"}}';

      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;
      final references = language.listDependencyReferences(manifest);

      expect(references.keys, containsAll(<String>['a', 'b']));
      expect(references['a']!.sectionName, 'dependencies');
      expect(references['a']!.value, '^1.0.0');
      expect(references['b']!.sectionName, 'devDependencies');
      expect(references['b']!.value, '^2.0.0');
    });

    test('replaceDependencyInContent updates package.json section', () {
      const content = '{"name":"pkg","dependencies":{"dep":"^1.0.0"}}';
      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;
      final reference = language.findDependency(manifest, 'dep')!;

      final updated = language.replaceDependencyInContent(
        manifestContent: content,
        reference: reference,
        newValue: '^2.0.0',
      );

      expect(updated, contains('"dep": "^2.0.0"'));
      expect(updated, contains('\n'));
    });

    test('replaceDependencyInContent returns original content with newline '
        'when section is not a map', () {
      const content = '{"name":"pkg","dependencies":"invalid"}';
      const reference = DependencyReference(
        sectionName: 'dependencies',
        name: 'dep',
        value: '^1.0.0',
      );

      final updated = language.replaceDependencyInContent(
        manifestContent: content,
        reference: reference,
        newValue: '^2.0.0',
      );

      expect(updated, '$content\n');
    });

    test('readPackageVersion returns null for non-map manifest', () {
      final version = language.readPackageVersion('not_a_map');

      expect(version, isNull);
    });

    test('readPackageVersion returns version for package.json map', () {
      const content = '{"name":"pkg","version":"3.2.1"}';
      final manifest =
          language.parseManifestContent(content) as Map<String, dynamic>;

      final version = language.readPackageVersion(manifest);

      expect(version, '3.2.1');
    });

    test('stringifyDependencyForReading returns string values unchanged', () {
      final result = language.stringifyDependencyForReading('^1.2.3');

      expect(result, '^1.2.3');
    });

    test('stringifyDependencyForReading encodes non-string values as json', () {
      final result = language.stringifyDependencyForReading(<String, dynamic>{
        'workspace': true,
      });

      expect(result, '{"workspace":true}');
    });

    test('stringifyManifest returns json with trailing newline', () {
      final manifest = <String, dynamic>{
        'name': 'pkg',
        'dependencies': <String, dynamic>{'dep': '^1.0.0'},
      };

      final result = language.stringifyManifest(manifest);
      final decoded = jsonDecode(result.trimRight()) as Map<String, dynamic>;

      expect(result.endsWith('\n'), isTrue);
      expect(decoded['name'], 'pkg');
      expect(
        (decoded['dependencies'] as Map<String, dynamic>)['dep'],
        '^1.0.0',
      );
    });
  });
}
