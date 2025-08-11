// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
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
  Directory dGitSucceed = Directory('');
  Directory dGitNoRepo = Directory('');

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
    dGitSucceed = createTempDir('git_succeed');
    dGitNoRepo = createTempDir('git_no_repo');
  });

  tearDown(() {
    deleteDirs([
      dNoProjectRootError,
      dParseError,
      dNoDependencies,
      dNodeNotFound,
      dWorkspaceAlreadyLocalized,
      dWorkspaceSucceed,
      dGitSucceed,
      dGitNoRepo,
    ]);
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
          expect(
            messages.join('\n'),
            contains('Use git references instead of local paths.'),
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
            '''name: test1\nversion: 1.0.0\ndependencies:\n  test2: ^1.0.0\ndev_dependencies:\n  test2: ^1.0.0''',
          );

          File(p.join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test2\nversion: 1.0.0''',
          );

          final messages = <String>[];
          LocalizeRefs local = LocalizeRefs(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          expect(messages[0], contains('Running localize-refs in'));
          expect(
            messages[1],
            contains('Localize refs of test1'),
          );

          // Check if publish_to: none was added
          final resultYaml =
              File(p.join(dProject1.path, 'pubspec.yaml')).readAsStringSync();
          expect(resultYaml, contains('publish_to: none'));
        });

        test('when already localized', () async {
          Directory dProject1 =
              Directory(p.join(dWorkspaceAlreadyLocalized.path, 'project1'));
          Directory dProject2 =
              Directory(p.join(dWorkspaceAlreadyLocalized.path, 'project2'));

          createDirs([dProject1, dProject2]);

          File(p.join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test1\nversion: 1.0.0\ndependencies:\n  test2:\n    path: ../project2''',
          );

          File(p.join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test2\nversion: 1.0.0''',
          );

          final messages = <String>[];
          LocalizeRefs local = LocalizeRefs(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          expect(messages[0], contains('Running localize-refs in'));
          expect(
            messages[1],
            contains('No files were changed.'),
          );
        });

        test('with --git option should succeed', () async {
          Directory dProject1 = Directory(p.join(dGitSucceed.path, 'project1'));
          Directory dProject2 = Directory(p.join(dGitSucceed.path, 'project2'));

          createDirs([dProject1, dProject2]);

          File(p.join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test1\nversion: 1.0.0\ndependencies:\n  test2: ^1.0.0''',
          );

          File(p.join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test2\nversion: 1.0.0''',
          );

          // In project2, init a git repo and set remote
          final resultInit = Process.runSync(
            'git',
            ['init'],
            workingDirectory: dProject2.path,
          );
          expect(resultInit.exitCode, 0, reason: resultInit.stderr.toString());
          final resultMain = Process.runSync(
            'git',
            ['checkout', '-b', 'main'],
            workingDirectory: dProject2.path,
          );
          expect(resultMain.exitCode, 0, reason: resultMain.stderr.toString());
          const remoteUrl = 'git@github.com:user/test2.git';
          final resultRemote = Process.runSync(
            'git',
            ['remote', 'add', 'origin', remoteUrl],
            workingDirectory: dProject2.path,
          );
          expect(
            resultRemote.exitCode,
            0,
            reason: resultRemote.stderr.toString(),
          );

          // Now run localize-refs --git
          await runner.run([
            'localize-refs',
            '--git',
            '--input',
            dProject1.path,
          ]);

          // pubspec.yaml should now contain a git block for test2
          final resultYaml =
              File(p.join(dProject1.path, 'pubspec.yaml')).readAsStringSync();
          expect(resultYaml, contains('test2:'));
          expect(resultYaml, contains('git:'));
          expect(resultYaml, contains('url: $remoteUrl'));
          expect(resultYaml, contains('ref: main'));
          expect(resultYaml, contains('publish_to: none'));

          // .gg_localize_refs_backup.json
          // should still save the previous version
          final backupJson = File(
            p.join(dProject1.path, '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          expect(backupJson, contains('^1.0.0'));
        });

        test('with --git should throw if repo has no git', () async {
          Directory dProject1 = Directory(p.join(dGitNoRepo.path, 'project1'));
          Directory dProject2 = Directory(p.join(dGitNoRepo.path, 'project2'));

          createDirs([dProject1, dProject2]);

          File(p.join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test1\nversion: 1.0.0\ndependencies:\n  test2: ^1.0.0',
          );
          File(p.join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test2\nversion: 1.0.0',
          );

          // project2 has no git repo

          // Should throw meaningful error
          await runner.run([
            'localize-refs',
            '--git',
            '--input',
            dProject1.path,
          ]).catchError(
            (dynamic e) {
              expect(
                e.toString(),
                contains('Cannot get git remote url for dependency test2'),
              );
            },
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

  group('LocalizeRefs._getGitDependencyYaml falls back to main', () {
    test(
      'should use "main" as ref if the git rev-parse fails (exitCode != 0)',
      () async {
        // Arrange
        final fakeDepDir = Directory.systemTemp.createTempSync('fakegit');
        final fakeRefs = FakeLocalizeRefs(
          ggLog: (_) {},
          runProcess: (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
          }) async {
            if (arguments.join(' ') == 'remote get-url origin') {
              // Simulate git remote get-url origin success
              return ProcessResult(0, 0, 'git@github.com:user/fake.git', '');
            }
            if (arguments.join(' ') == 'rev-parse --abbrev-ref HEAD') {
              // Simulate rev-parse fails (non-zero exit code)
              return ProcessResult(0, 1, '', 'fail');
            }
            throw UnimplementedError('Unknown process for args $arguments');
          },
        );

        // Act
        final yaml = await fakeRefs.rawGitDependencyYaml(
          fakeDepDir,
          'somedep',
        );
        // Assert
        expect(yaml, contains('ref: main'));
        expect(yaml, contains('git:'));
        expect(yaml, contains('url: git@github.com:user/fake.git'));
        fakeDepDir.deleteSync(recursive: true);
      },
    );

    test(
      'should fallback to main if git rev-parse returns HEAD as stdout',
      () async {
        final fakeDepDir = Directory.systemTemp.createTempSync('fakegit2');
        final fakeRefs = FakeLocalizeRefs(
          ggLog: (_) {},
          runProcess: (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
          }) async {
            if (arguments.join(' ') == 'remote get-url origin') {
              // Simulate git remote get-url origin success
              return ProcessResult(0, 0, 'git@github.com:user/fake.git', '');
            }
            if (arguments.join(' ') == 'rev-parse --abbrev-ref HEAD') {
              // Simulate rev-parse returns exitCode 0 with stdout 'HEAD'
              return ProcessResult(0, 0, 'HEAD', '');
            }
            throw UnimplementedError('Unknown process for args $arguments');
          },
        );
        final yaml = await fakeRefs.rawGitDependencyYaml(
          fakeDepDir,
          'somedep',
        );
        expect(yaml, contains('ref: main'));
        expect(yaml, contains('git:'));
        expect(yaml, contains('url: git@github.com:user/fake.git'));
        fakeDepDir.deleteSync(recursive: true);
      },
    );

    test(
      'should fallback to main if git rev-parse returns empty stdout',
      () async {
        final fakeDepDir = Directory.systemTemp.createTempSync('fakegit3');
        final fakeRefs = FakeLocalizeRefs(
          ggLog: (_) {},
          runProcess: (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
          }) async {
            if (arguments.join(' ') == 'remote get-url origin') {
              // Simulate git remote get-url origin success
              return ProcessResult(0, 0, 'git@github.com:user/fake.git', '');
            }
            if (arguments.join(' ') == 'rev-parse --abbrev-ref HEAD') {
              // Simulate rev-parse returns exitCode 0 but no stdout
              return ProcessResult(0, 0, '', '');
            }
            throw UnimplementedError('Unknown process for args $arguments');
          },
        );
        final yaml = await fakeRefs.rawGitDependencyYaml(
          fakeDepDir,
          'somedep',
        );
        expect(yaml, contains('ref: main'));
        expect(yaml, contains('git:'));
        expect(yaml, contains('url: git@github.com:user/fake.git'));
        fakeDepDir.deleteSync(recursive: true);
      },
    );
  });
}

// Implements a fake version of LocalizeRefs with injectable runProcess for
// testing git ref fallback. No runProcess in superclass anymore; assign here.
class FakeLocalizeRefs extends LocalizeRefs {
  FakeLocalizeRefs({
    required super.ggLog,
    required Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) runProcess,
  }) : super() {
    this.runProcess = runProcess;
  }

  /// Exposes the getGitDependencyYaml method for testing
  Future<String> rawGitDependencyYaml(Directory dir, String depName) async {
    return await getGitDependencyYaml(dir, depName);
  }
}
