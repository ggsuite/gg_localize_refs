// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/commands/localize_refs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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

  Directory dWorkspaceSucceedTs = Directory('');
  Directory dWorkspaceAlreadyLocalizedTs = Directory('');
  Directory dGitSucceedTs = Directory('');
  Directory dGitNoRepoTs = Directory('');

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

    dWorkspaceSucceedTs = createTempDir('ts_succeed');
    dWorkspaceAlreadyLocalizedTs = createTempDir('ts_already_localized');
    dGitSucceedTs = createTempDir('ts_git_succeed');
    dGitNoRepoTs = createTempDir('ts_git_no_repo');

    copyDirectory(
      Directory(p.join('test', 'sample_folder', 'localize_refs', 'succeed')),
      dWorkspaceSucceed,
    );
    copyDirectory(
      Directory(
        p.join('test', 'sample_folder', 'localize_refs', 'already_localized'),
      ),
      dWorkspaceAlreadyLocalized,
    );
    copyDirectory(
      Directory(
        p.join('test', 'sample_folder', 'localize_refs', 'git_succeed'),
      ),
      dGitSucceed,
    );
    copyDirectory(
      Directory(
        p.join('test', 'sample_folder', 'localize_refs', 'git_no_repo'),
      ),
      dGitNoRepo,
    );

    copyDirectory(
      Directory(p.join('test', 'sample_folder_ts', 'localize_refs', 'succeed')),
      dWorkspaceSucceedTs,
    );
    copyDirectory(
      Directory(
        p.join(
          'test',
          'sample_folder_ts',
          'localize_refs',
          'already_localized',
        ),
      ),
      dWorkspaceAlreadyLocalizedTs,
    );
    copyDirectory(
      Directory(
        p.join('test', 'sample_folder_ts', 'localize_refs', 'git_succeed'),
      ),
      dGitSucceedTs,
    );
    copyDirectory(
      Directory(
        p.join('test', 'sample_folder_ts', 'localize_refs', 'git_no_repo'),
      ),
      dGitNoRepoTs,
    );
  });

  tearDown(() {
    deleteDirs(<Directory>[
      dNoProjectRootError,
      dParseError,
      dNoDependencies,
      dNodeNotFound,
      dWorkspaceAlreadyLocalized,
      dWorkspaceSucceed,
      dGitSucceed,
      dGitNoRepo,
      dWorkspaceSucceedTs,
      dWorkspaceAlreadyLocalizedTs,
      dGitSucceedTs,
      dGitNoRepoTs,
    ]);
  });

  group('Local Command', () {
    group('run()', () {
      // .......................................................................
      group('should print a usage description', () {
        test('when called args=[--help]', () async {
          capturePrint(
            ggLog: messages.add,
            code: () => runner.run(<String>['localize-refs', '--help']),
          );

          expect(
            messages.last,
            contains('Changes dependencies to local dependencies.'),
          );
          expect(
            messages.join('\n'),
            contains('Use git references instead of local paths.'),
          );
          expect(
            messages.join('\n'),
            contains(
              'Git ref (branch, tag, or commit) '
              'to use when localizing with --git.',
            ),
          );
        });
      });

      // .......................................................................
      group('should throw', () {
        test('when project root was not found', () async {
          await expectLater(
            runner.run(<String>[
              'localize-refs',
              '--input',
              dNoProjectRootError.path,
            ]),
            throwsA(
              isA<Exception>().having(
                (Object e) => e.toString(),
                'message',
                contains('No project root found'),
              ),
            ),
          );
        });

        group('when pubspec.yaml cannot be parsed', () {
          test('when calling command', () async {
            File(
              p.join(dParseError.path, 'pubspec.yaml'),
            ).writeAsStringSync('invalid yaml');

            await expectLater(
              runner.run(<String>[
                'localize-refs',
                '--input',
                dParseError.path,
              ]),
              throwsA(
                isA<Exception>().having(
                  (Object e) => e.toString(),
                  'message',
                  contains('Error parsing pubspec.yaml'),
                ),
              ),
            );
          });
        });

        test('when node not found', () async {
          final localMessages = <String>[];

          File(p.join(dNodeNotFound.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test_package\nversion: 1.0.0\ndependencies:',
          );

          final loc = LocalizeRefs(ggLog: localMessages.add);

          await expectLater(
            () async {
              final language = DartProjectLanguage();
              final node = await language.createNode(dNodeNotFound);
              await processNode(
                node,
                <String, ProjectNode>{},
                <String>{},
                loc.modifyManifest,
                FileChangesBuffer(),
              );
            },
            throwsA(
              isA<Exception>()
                  .having(
                    (Object e) => e.toString(),
                    'message',
                    contains('node for the package'),
                  )
                  .having(
                    (Object e) => e.toString(),
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
          final dProject1 = Directory(
            p.join(dWorkspaceSucceed.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = LocalizeRefs(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[0], contains('Running localize-refs in'));
          expect(localMessages[1], contains('Localize refs of test1'));

          final resultYaml = File(
            p.join(dProject1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(resultYaml, contains('publish_to: none'));
        });

        test('when already localized', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceAlreadyLocalized.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = LocalizeRefs(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[0], contains('Running localize-refs in'));
          expect(localMessages[1], contains('No files were changed.'));
        });

        test('with --git option should succeed', () async {
          final dProject1 = Directory(p.join(dGitSucceed.path, 'project1'));
          final dProject2 = Directory(p.join(dGitSucceed.path, 'project2'));

          final resultInit = Process.runSync('git', <String>[
            'init',
          ], workingDirectory: dProject2.path);
          expect(resultInit.exitCode, 0, reason: resultInit.stderr.toString());
          final resultMain = Process.runSync('git', <String>[
            'checkout',
            '-b',
            'main',
          ], workingDirectory: dProject2.path);
          expect(resultMain.exitCode, 0, reason: resultMain.stderr.toString());
          const remoteUrl = 'git@github.com:user/test2.git';
          final resultRemote = Process.runSync('git', <String>[
            'remote',
            'add',
            'origin',
            remoteUrl,
          ], workingDirectory: dProject2.path);
          expect(
            resultRemote.exitCode,
            0,
            reason: resultRemote.stderr.toString(),
          );

          await runner.run(<String>[
            'localize-refs',
            '--git',
            '--input',
            dProject1.path,
          ]);

          final resultYaml = File(
            p.join(dProject1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(resultYaml, contains('test2:'));
          expect(resultYaml, contains('git:'));
          expect(resultYaml, contains('url: $remoteUrl'));
          expect(resultYaml, contains('ref: main'));
          expect(resultYaml, contains('publish_to: none'));

          final backupJson = File(
            p.join(dProject1.path, '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          expect(backupJson, contains('^1.0.0'));
        });

        test('with --git and --git-ref uses provided ref', () async {
          final dProject1 = Directory(p.join(dGitSucceed.path, 'project1'));
          final dProject2 = Directory(p.join(dGitSucceed.path, 'project2'));

          final resultInit = Process.runSync('git', <String>[
            'init',
          ], workingDirectory: dProject2.path);
          expect(resultInit.exitCode, 0, reason: resultInit.stderr.toString());
          final resultBranch = Process.runSync('git', <String>[
            'checkout',
            '-b',
            'develop',
          ], workingDirectory: dProject2.path);
          expect(
            resultBranch.exitCode,
            0,
            reason: resultBranch.stderr.toString(),
          );
          const remoteUrl = 'git@github.com:user/test2.git';
          final resultRemote = Process.runSync('git', <String>[
            'remote',
            'add',
            'origin',
            remoteUrl,
          ], workingDirectory: dProject2.path);
          expect(
            resultRemote.exitCode,
            0,
            reason: resultRemote.stderr.toString(),
          );

          const customRef = 'feature123';

          await runner.run(<String>[
            'localize-refs',
            '--git',
            '--git-ref',
            customRef,
            '--input',
            dProject1.path,
          ]);

          final resultYaml = File(
            p.join(dProject1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(resultYaml, contains('test2:'));
          expect(resultYaml, contains('git:'));
          expect(resultYaml, contains('url: $remoteUrl'));
          expect(resultYaml, contains('ref: $customRef'));
          expect(resultYaml, isNot(contains('ref: main')));
        });

        test('with --git should throw if repo has no git', () async {
          final dProject1 = Directory(p.join(dGitNoRepo.path, 'project1'));

          await runner
              .run(<String>[
                'localize-refs',
                '--git',
                '--input',
                dProject1.path,
              ])
              .catchError((Object e) {
                expect(
                  e.toString(),
                  contains('Cannot get git remote url for dependency test2'),
                );
              });
        });

        test('TypeScript: when package.json is correct (path mode)', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceedTs.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = LocalizeRefs(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[0], contains('Running localize-refs in'));
          expect(localMessages[1], contains('Localize refs of test1_ts'));

          final resultJson = File(
            p.join(dProject1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('"test2_ts":"file:../project2"'));

          final backupJson = File(
            p.join(dProject1.path, '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          expect(backupJson, contains('^1.0.0'));
        });

        test('TypeScript: when already localized', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceAlreadyLocalizedTs.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = LocalizeRefs(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[0], contains('Running localize-refs in'));
          expect(localMessages[1], contains('No files were changed.'));
        });

        test('TypeScript: with --git option should succeed', () async {
          final dProject1 = Directory(p.join(dGitSucceedTs.path, 'project1'));
          final dProject2 = Directory(p.join(dGitSucceedTs.path, 'project2'));

          final resultInit = Process.runSync('git', <String>[
            'init',
          ], workingDirectory: dProject2.path);
          expect(resultInit.exitCode, 0, reason: resultInit.stderr.toString());
          final resultMain = Process.runSync('git', <String>[
            'checkout',
            '-b',
            'main',
          ], workingDirectory: dProject2.path);
          expect(resultMain.exitCode, 0, reason: resultMain.stderr.toString());
          const remoteUrl = 'git@github.com:user/test2_ts.git';
          final resultRemote = Process.runSync('git', <String>[
            'remote',
            'add',
            'origin',
            remoteUrl,
          ], workingDirectory: dProject2.path);
          expect(
            resultRemote.exitCode,
            0,
            reason: resultRemote.stderr.toString(),
          );

          await runner.run(<String>[
            'localize-refs',
            '--git',
            '--input',
            dProject1.path,
          ]);

          final resultJson = File(
            p.join(dProject1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('test2_ts'));
          expect(resultJson, contains('git+'));
          expect(resultJson, contains(remoteUrl));
          expect(resultJson, contains('#main'));
        });

        test(
          'TypeScript: with --git should throw if repo has no git',
          () async {
            final dProject1 = Directory(p.join(dGitNoRepoTs.path, 'project1'));

            await runner
                .run(<String>[
                  'localize-refs',
                  '--git',
                  '--input',
                  dProject1.path,
                ])
                .catchError((Object e) {
                  expect(
                    e.toString(),
                    contains(
                      'Cannot get git remote url for dependency test2_ts',
                    ),
                  );
                });
          },
        );
      });
    });
  });

  group('getDependency', () {
    test('should return the dependency from dependencies', () {
      final yamlMap = <String, dynamic>{
        'dependencies': <String, dynamic>{'some_dependency': '^1.0.0'},
        'dev_dependencies': <String, dynamic>{},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, equals('^1.0.0'));
    });

    test('should return the dependency from dev_dependencies '
        'when not in dependencies', () {
      final yamlMap = <String, dynamic>{
        'dependencies': <String, dynamic>{},
        'dev_dependencies': <String, dynamic>{'some_dependency': '^2.0.0'},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, equals('^2.0.0'));
    });

    test('should return the dependency from dependencies when '
        'in both dependencies and dev_dependencies', () {
      final yamlMap = <String, dynamic>{
        'dependencies': <String, dynamic>{'some_dependency': '^1.0.0'},
        'dev_dependencies': <String, dynamic>{'some_dependency': '^2.0.0'},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, equals('^1.0.0'));
    });

    test('should return null when the dependency is not present', () {
      final yamlMap = <String, dynamic>{
        'dependencies': <String, dynamic>{},
        'dev_dependencies': <String, dynamic>{},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, isNull);
    });

    test('should handle missing dependencies section', () {
      final yamlMap = <String, dynamic>{
        'dev_dependencies': <String, dynamic>{'some_dependency': '^1.0.0'},
      };
      final result = getDependency('some_dependency', yamlMap);
      expect(result, equals('^1.0.0'));
    });

    test('should handle missing dev_dependencies section', () {
      final yamlMap = <String, dynamic>{
        'dependencies': <String, dynamic>{'some_dependency': '^1.0.0'},
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
      },
    );
  });

  group('LocalizeRefs._getGitDependencyYaml falls back to main', () {
    test(
      'should use "main" as ref if the git rev-parse fails (exitCode != 0)',
      () async {
        final fakeDepDir = Directory.systemTemp.createTempSync('fakegit');
        final fakeRefs = FakeLocalizeRefs(
          ggLog: (_) {},
          runProcess:
              (
                String executable,
                List<String> arguments, {
                String? workingDirectory,
              }) async {
                if (arguments.join(' ') == 'remote get-url origin') {
                  return ProcessResult(
                    0,
                    0,
                    'git@github.com:user/fake.git',
                    '',
                  );
                }
                if (arguments.join(' ') == 'rev-parse --abbrev-ref HEAD') {
                  return ProcessResult(0, 1, '', 'fail');
                }
                throw UnimplementedError('Unknown process for args $arguments');
              },
        );

        final yaml = await fakeRefs.rawGitDependencyYaml(fakeDepDir, 'somedep');
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
          runProcess:
              (
                String executable,
                List<String> arguments, {
                String? workingDirectory,
              }) async {
                if (arguments.join(' ') == 'remote get-url origin') {
                  return ProcessResult(
                    0,
                    0,
                    'git@github.com:user/fake.git',
                    '',
                  );
                }
                if (arguments.join(' ') == 'rev-parse --abbrev-ref HEAD') {
                  return ProcessResult(0, 0, 'HEAD', '');
                }
                throw UnimplementedError('Unknown process for args $arguments');
              },
        );
        final yaml = await fakeRefs.rawGitDependencyYaml(fakeDepDir, 'somedep');
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
          runProcess:
              (
                String executable,
                List<String> arguments, {
                String? workingDirectory,
              }) async {
                if (arguments.join(' ') == 'remote get-url origin') {
                  return ProcessResult(
                    0,
                    0,
                    'git@github.com:user/fake.git',
                    '',
                  );
                }
                if (arguments.join(' ') == 'rev-parse --abbrev-ref HEAD') {
                  return ProcessResult(0, 0, '', '');
                }
                throw UnimplementedError('Unknown process for args $arguments');
              },
        );
        final yaml = await fakeRefs.rawGitDependencyYaml(fakeDepDir, 'somedep');
        expect(yaml, contains('ref: main'));
        expect(yaml, contains('git:'));
        expect(yaml, contains('url: git@github.com:user/fake.git'));
        fakeDepDir.deleteSync(recursive: true);
      },
    );
  });
}

// Implements a fake version of LocalizeRefs with injectable runProcess for
// testing git ref fallback.
class FakeLocalizeRefs extends LocalizeRefs {
  FakeLocalizeRefs({
    required super.ggLog,
    required Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    })
    runProcess,
  }) : super() {
    this.runProcess = runProcess;
  }

  /// Exposes the getGitDependencyYaml method for testing
  Future<String> rawGitDependencyYaml(Directory dir, String depName) async {
    return getGitDependencyYaml(dir, depName);
  }
}
