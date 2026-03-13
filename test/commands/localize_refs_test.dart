// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
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
      // .....................................................................
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

      // .....................................................................
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
            'name: test_package\nversion: 1.0.0\n'
            'dependencies:',
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
                <String>[].add,
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

      // .....................................................................

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

          // Check that .gitignore has been updated for .gg
          final gitignoreFile = File(p.join(dProject1.path, '.gitignore'));
          expect(gitignoreFile.existsSync(), isTrue);
          final gitignoreContent = gitignoreFile.readAsStringSync();
          expect(gitignoreContent, contains('.gg'));
          expect(gitignoreContent, contains('!.gg/.gg.json'));
        });

        test('updates existing .gitignore when missing entries', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceed.path, 'project1'),
          );

          // Create an existing .gitignore without the required .gg entries.
          final gitignoreFile = File(p.join(dProject1.path, '.gitignore'));
          gitignoreFile.writeAsStringSync('build/\n');

          final localMessages = <String>[];
          final local = LocalizeRefs(ggLog: localMessages.add);

          await local.get(directory: dProject1, ggLog: localMessages.add);

          // Existing content should be preserved and required entries added.
          final gitignoreContent = gitignoreFile.readAsStringSync();
          expect(gitignoreContent, contains('build/'));
          expect(gitignoreContent, contains('.gg'));
          expect(gitignoreContent, contains('!.gg/.gg.json'));
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

        test('stores only version strings in Dart backup json', () async {
          final workspace = createTempDir('localize_backup_versions_only_ws');
          final project1 = Directory(p.join(workspace.path, 'project1'));
          final project2 = Directory(p.join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project1\n'
            'version: 1.0.0\n'
            'dependencies:\n'
            '  project2:\n'
            '    git:\n'
            '      url: git@github.com:ggsuite/testproject_gg_2.git\n'
            '      tag_pattern: {{version}}\n'
            '    version: ^1.0.0\n',
          );
          File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project2\n'
            'version: 1.0.0\n',
          );

          final local = LocalizeRefs(ggLog: messages.add);
          await local.get(directory: project1, ggLog: messages.add, git: true);

          final backupJson = File(
            p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

          expect(backupMap['project2'], '^1.0.0');

          deleteDirs(<Directory>[workspace]);
        });

        test(
          'backs up git.version when dependency map has nested git version',
          () async {
            final workspace = createTempDir('localize_backup_git_version_ws');
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  project2:\n'
              '    git:\n'
              '      url: git@github.com:user/project2.git\n'
              '      version: ^4.0.0\n',
            );
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );

            final local = LocalizeRefs(ggLog: messages.add);
            await local.get(directory: project1, ggLog: messages.add);

            final backupJson = File(
              p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
            ).readAsStringSync();
            final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

            expect(backupMap['project2'], '^4.0.0');

            deleteDirs(<Directory>[workspace]);
          },
        );

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
            p.join(dProject1.path, '.gg', '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          expect(backupJson, contains('^1.0.0'));
        });

        test('with --git localizes git tag_pattern dependencies back to git '
            'refs without version', () async {
          final workspace = createTempDir('localize_git_tag_pattern_ws');
          final project1 = Directory(p.join(workspace.path, 'project1'));
          final project2 = Directory(p.join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project1\n'
            'version: 1.0.0\n'
            'dependencies:\n'
            '  project2:\n'
            '    git:\n'
            '      url: git@github.com:user/project2.git\n'
            '      tag_pattern: {{version}}\n'
            '    version: ^2.0.4\n',
          );
          File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project2\n'
            'version: 1.0.0\n',
          );

          final localMessages = <String>[];
          final local = LocalizeRefs(ggLog: localMessages.add);
          await local.get(
            directory: project1,
            ggLog: localMessages.add,
            git: true,
          );

          final resultYaml = File(
            p.join(project1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(resultYaml, contains('project2:'));
          expect(resultYaml, contains('git:'));
          expect(resultYaml, contains('url:'));
          expect(resultYaml, contains('ref: main'));
          expect(resultYaml, isNot(contains('tag_pattern:')));
          expect(resultYaml, isNot(contains('version: ^2.0.4')));

          deleteDirs(<Directory>[workspace]);
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

        test(
          'TypeScript: handles package.json without dependency sections',
          () async {
            final root = Directory(
              p.join(dWorkspaceSucceedTs.path, 'nodeps_root'),
            );
            await createDirs(<Directory>[root]);
            final pkgDir = Directory(p.join(root.path, 'project_no_deps'));
            await createDirs(<Directory>[pkgDir]);

            File(
              p.join(pkgDir.path, 'package.json'),
            ).writeAsStringSync('{"name":"nodeps","version":"1.0.0"}');

            final language = TypeScriptProjectLanguage();
            final node = await language.createNode(pkgDir);
            final manifestFile = File(p.join(pkgDir.path, 'package.json'));
            final content = manifestFile.readAsStringSync();
            final manifestMap =
                language.parseManifestContent(content) as Map<String, dynamic>;

            final buffer = FileChangesBuffer();
            final local = LocalizeRefs(ggLog: messages.add);
            await local.modifyManifest(
              node,
              manifestFile,
              content,
              manifestMap,
              buffer,
              messages.add,
            );

            expect(buffer.files, isEmpty);
          },
        );

        test('TypeScript: localizes devDependencies when dependencies are '
            'missing', () async {
          final workspace = createTempDir('ts_dev_only_ws');
          final project1 = Directory(p.join(workspace.path, 'project1'));
          final project2 = Directory(p.join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          File(p.join(project1.path, 'package.json')).writeAsStringSync(
            '{"name":"proj1_ts","version":"1.0.0",'
            '"devDependencies":{"proj2_ts":"^1.0.0"}}',
          );
          File(
            p.join(project2.path, 'package.json'),
          ).writeAsStringSync('{"name":"proj2_ts","version":"1.0.0"}');

          final localMessages = <String>[];
          final local = LocalizeRefs(ggLog: localMessages.add);
          await local.get(directory: project1, ggLog: localMessages.add);

          final resultJson = File(
            p.join(project1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('"proj2_ts":"file:../project2"'));

          final backupJson = File(
            p.join(project1.path, '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          expect(backupJson, contains('^1.0.0'));

          deleteDirs(<Directory>[workspace]);
        });

        test('TypeScript: with --git localizes devDependencies when '
            'dependencies are missing', () async {
          final workspace = createTempDir('ts_git_dev_only_ws');
          final project1 = Directory(p.join(workspace.path, 'project1'));
          final project2 = Directory(p.join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          File(p.join(project1.path, 'package.json')).writeAsStringSync(
            '{"name":"proj1_ts_git","version":"1.0.0",'
            '"devDependencies":{"proj2_ts":"^1.0.0"}}',
          );
          File(
            p.join(project2.path, 'package.json'),
          ).writeAsStringSync('{"name":"proj2_ts","version":"1.0.0"}');

          await runner.run(<String>[
            'localize-refs',
            '--git',
            '--input',
            project1.path,
          ]);

          final resultJson = File(
            p.join(project1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('proj2_ts'));
          expect(resultJson, contains('git+'));

          deleteDirs(<Directory>[workspace]);
        });
      });
    });
  });
}
