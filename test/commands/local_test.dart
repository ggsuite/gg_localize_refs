// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_to_local/src/commands/local.dart';
import 'package:test/test.dart';
import 'package:path/path.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;

  final dNoProjectRootError = Directory(
    join(
      'test',
      'sample_folder',
      'workspace_no_project_root_error',
      'no_project_root_error',
    ),
  );
  final dParseError = Directory(
    join('test', 'sample_folder', 'workspace_parse_error', 'parse_error'),
  );
  final dNoDependencies = Directory(
    join(
      'test',
      'sample_folder',
      'workspace_no_dependencies',
      'no_dependencies',
    ),
  );
  final dNodeNotFound = Directory(
    join(
      'test',
      'sample_folder',
      'workspace_node_not_found',
      'node_not_found',
    ),
  );
  final dWorkspaceSucceed = Directory(
    join(
      'test',
      'sample_folder',
      'workspace_succeed',
    ),
  );

  setUp(() async {
    messages.clear();
    runner = CommandRunner<void>('local', 'Description of local command.');
    final myCommand = LocalizeRefs(ggLog: messages.add);
    runner.addCommand(myCommand);

    // create the tempDir
    createDirs(
      [
        dNoProjectRootError,
        dParseError,
        dNoDependencies,
        dNodeNotFound,
        dWorkspaceSucceed,
      ],
    );
  });

  tearDown(() {});

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
            File(join(dParseError.path, 'pubspec.yaml'))
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

          test('when calling parsing method', () async {
            final messages = <String>[];

            expect(
              () => LocalizeRefs(ggLog: messages.add)
                  .getPackageName('invalid yaml'),
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
          File(join(dNodeNotFound.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test_package\nversion: 1.0.0\ndependencies:',
          );

          await expectLater(
            LocalizeRefs(ggLog: messages.add).modifyYaml(dNodeNotFound, {}, {}),
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
              Directory(join(dWorkspaceSucceed.path, 'project1'));
          Directory dProject2 =
              Directory(join(dWorkspaceSucceed.path, 'project2'));

          createDirs([dProject1, dProject2]);

          File(join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test1
version: 1.0.0
dependencies:
  test2: ^1.0.0''',
          );

          File(join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
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
      });
    });
  });

  group('Helper methods', () {
    test('correctDir()', () {
      final messages = <String>[];
      final local = LocalizeRefs(ggLog: messages.add);

      expect(
        local.correctDir(Directory('test/')).path,
        'test',
      );
      expect(
        local.correctDir(Directory('test/.')).path,
        'test',
      );
    });
  });
}

void createDirs(List<Directory> dirs) {
  for (final dir in dirs) {
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    expect(dir.existsSync(), isTrue);
  }
}

void deleteDirs(List<Directory> dirs) {
  for (final dir in dirs) {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    expect(dir.existsSync(), isFalse);
  }
}
