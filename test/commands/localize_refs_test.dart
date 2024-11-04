// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_localize_refs/src/commands/localize_refs.dart';
import 'package:gg_localize_refs/src/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/process_dependencies.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../test_helpers.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;

  Directory dNoProjectRootError = Directory('');
  Directory dParseError = Directory('');
  Directory dNoDependencies = Directory('');
  Directory dNodeNotFound = Directory('');
  Directory dWorkspaceSucceed = Directory('');
  Directory dWorkspaceAlreadyLocalized = Directory('');

  setUp(() async {
    messages.clear();
    runner = CommandRunner<void>('local', 'Description of local command.');
    final myCommand = LocalizeRefs(ggLog: messages.add);
    runner.addCommand(myCommand);

    dNoProjectRootError = createTempDir('no_project_root_error', 'project1');
    dParseError = createTempDir('parse_error', 'project1');
    dNoDependencies = createTempDir('no_dependencies', 'project1');
    dNodeNotFound = createTempDir('node_not_found', 'project1');
    dWorkspaceSucceed = createTempDir('succeed');
    dWorkspaceAlreadyLocalized = createTempDir('already_localized');
  });

  tearDown(() {
    deleteDirs(
      [
        dNoProjectRootError,
        dParseError,
        dNoDependencies,
        dNodeNotFound,
        dWorkspaceAlreadyLocalized,
        dWorkspaceSucceed,
      ],
    );
  });

  group('Local Command', () {
    group('run()', () {
      // .......................................................................
      group('should print a usage description', () {
        test('when called args=[--help]', () async {
          capturePrint(
            ggLog: messages.add,
            code: () => runner.run(
              ['localize-refs', '--help'],
            ),
          );

          expect(
            messages.last,
            contains('Changes dependencies to local dependencies.'),
          );
        });
      });

      // .......................................................................
      group('should throw', () {
        test('when project root was not found', () async {
          await expectLater(
            runner.run(
              ['localize-refs', '--input', dNoProjectRootError.path],
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('No project root found'),
              ),
            ),
          );
        });

        group('when pubspec.yaml cannot be parsed', () {
          test('when calling command', () async {
            // Create a pubspec.yaml with invalid content in tempDir
            File(p.join(dParseError.path, 'pubspec.yaml'))
                .writeAsStringSync('invalid yaml');

            await expectLater(
              runner.run(
                ['localize-refs', '--input', dParseError.path],
              ),
              throwsA(
                isA<Exception>().having(
                  (e) => e.toString(),
                  'message',
                  contains('Error parsing pubspec.yaml'),
                ),
              ),
            );
          });
        });

        test('when node not found', () async {
          final messages = <String>[];

          // Create a pubspec.yaml with invalid content in tempDir
          File(p.join(dNodeNotFound.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test_package\nversion: 1.0.0\ndependencies:',
          );

          LocalizeRefs loc = LocalizeRefs(ggLog: messages.add);

          await expectLater(
            processNode(
              dNodeNotFound,
              {},
              {},
              loc.modifyYaml,
              FileChangesBuffer(),
            ),
            throwsA(
              isA<Exception>()
                  .having(
                    (e) => e.toString(),
                    'message',
                    contains('node for the package'),
                  )
                  .having(
                    (e) => e.toString(),
                    'message',
                    contains('not found'),
                  ),
            ),
          );
        });
      });

      // .......................................................................

      group('should succeed', () {
        test('when pubspec is correct', () async {
          Directory dProject1 =
              Directory(p.join(dWorkspaceSucceed.path, 'project1'));
          Directory dProject2 =
              Directory(p.join(dWorkspaceSucceed.path, 'project2'));

          createDirs([dProject1, dProject2]);

          File(p.join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test1
version: 1.0.0
dependencies:
  test2: ^1.0.0
dev_dependencies:
  test2: ^1.0.0''',
          );

          File(p.join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test2
version: 1.0.0''',
          );

          final messages = <String>[];
          LocalizeRefs local = LocalizeRefs(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          expect(messages[0], contains('Running localize-refs in'));
          expect(
            messages[1],
            contains('Processing dependencies of package test1'),
          );
          expect(messages[2], contains('test2'));
        });

        test('when already localized', () async {
          Directory dProject1 =
              Directory(p.join(dWorkspaceAlreadyLocalized.path, 'project1'));
          Directory dProject2 =
              Directory(p.join(dWorkspaceAlreadyLocalized.path, 'project2'));

          createDirs([dProject1, dProject2]);

          File(p.join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test1
version: 1.0.0
dependencies:
  test2:
    path: ../project2''',
          );

          File(p.join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test2
version: 1.0.0''',
          );

          final messages = <String>[];
          LocalizeRefs local = LocalizeRefs(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          expect(messages[0], contains('Running localize-refs in'));
          expect(
            messages[1],
            contains('Processing dependencies of package test1'),
          );
          expect(
            messages[2],
            contains('Dependencies already localized.'),
          );
        });
      });
    });
  });

  group('getDependency', () {
    test('should return the dependency from dependencies', () {
      final yamlMap = {
        'dependencies': {'some_dependency': '^1.0.0'},
        'dev_dependencies': <String, dynamic>{},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, equals('^1.0.0'));
    });

    test(
        'should return the dependency from dev_dependencies '
        'when not in dependencies', () {
      final yamlMap = {
        'dependencies': <String, dynamic>{},
        'dev_dependencies': {'some_dependency': '^2.0.0'},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, equals('^2.0.0'));
    });

    test(
        'should return the dependency from dependencies when '
        'in both dependencies and dev_dependencies', () {
      final yamlMap = {
        'dependencies': {'some_dependency': '^1.0.0'},
        'dev_dependencies': {'some_dependency': '^2.0.0'},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, equals('^1.0.0'));
    });

    test('should return null when the dependency is not present', () {
      final yamlMap = {
        'dependencies': <String, dynamic>{},
        'dev_dependencies': <String, dynamic>{},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, isNull);
    });

    test('should handle missing dependencies section', () {
      final yamlMap = {
        'dev_dependencies': {'some_dependency': '^1.0.0'},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, equals('^1.0.0'));
    });

    test('should handle missing dev_dependencies section', () {
      final yamlMap = {
        'dependencies': {'some_dependency': '^1.0.0'},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, equals('^1.0.0'));
    });

    test(
        'should handle both dependencies and dev_dependencies sections missing',
        () {
      final yamlMap = <String, dynamic>{};
      final result = getDependency('some_dependency', yamlMap);
      expect(result, isNull);
    });
  });
}
