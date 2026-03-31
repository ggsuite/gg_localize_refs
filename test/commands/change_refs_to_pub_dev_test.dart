// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_localize_refs/src/commands/change_refs_to_pub_dev.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;

  Directory dNoProjectRootError = Directory('');
  Directory dParseError = Directory('');
  Directory dNoDependencies = Directory('');
  Directory dNodeNotFound = Directory('');
  Directory dJsonNotFound = Directory('');
  Directory dWorkspaceAlreadyUnlocalized = Directory('');
  Directory dWorkspaceSucceed = Directory('');
  Directory dWorkspaceSucceedGit = Directory('');

  Directory dWorkspaceSucceedTs = Directory('');
  Directory dWorkspaceSucceedGitTs = Directory('');
  Directory dWorkspaceAlreadyUnlocalizedTs = Directory('');
  Directory dJsonNotFoundTs = Directory('');

  setUp(() async {
    messages.clear();
    runner = CommandRunner<void>(
      'unlocalize',
      'Description of unlocalize command.',
    );
    final myCommand = ChangeRefsToPubDev(ggLog: messages.add);
    runner.addCommand(myCommand);

    dNoProjectRootError = createTempDir(
      'unlocalize_no_project_root_error',
      'project1',
    );
    dParseError = createTempDir('unlocalize_parse_error', 'project1');
    dNoDependencies = createTempDir('unlocalize_no_dependencies', 'project1');
    dNodeNotFound = createTempDir('unlocalize_node_not_found', 'project1');
    dJsonNotFound = createTempDir('unlocalize_json_not_found');
    dWorkspaceSucceed = createTempDir('unlocalize_succeed');
    dWorkspaceSucceedGit = createTempDir('unlocalize_succeed_git');
    dWorkspaceAlreadyUnlocalized = createTempDir(
      'unlocalize_already_unlocalized',
    );

    dWorkspaceSucceedTs = createTempDir('unlocalize_ts_succeed');
    dWorkspaceSucceedGitTs = createTempDir('unlocalize_ts_succeed_git');
    dWorkspaceAlreadyUnlocalizedTs = createTempDir(
      'unlocalize_ts_already_unlocalized',
    );
    dJsonNotFoundTs = createTempDir('unlocalize_ts_json_not_found');

    copyDirectory(
      Directory(
        join('test', 'sample_folder', 'unlocalize_refs', 'path_succeed'),
      ),
      dWorkspaceSucceed,
    );
    copyDirectory(
      Directory(
        join('test', 'sample_folder', 'unlocalize_refs', 'git_succeed'),
      ),
      dWorkspaceSucceedGit,
    );
    copyDirectory(
      Directory(
        join('test', 'sample_folder', 'unlocalize_refs', 'already_unlocalized'),
      ),
      dWorkspaceAlreadyUnlocalized,
    );
    copyDirectory(
      Directory(
        join('test', 'sample_folder', 'unlocalize_refs', 'json_not_found'),
      ),
      dJsonNotFound,
    );

    copyDirectory(
      Directory(
        join('test', 'sample_folder_ts', 'unlocalize_refs', 'path_succeed'),
      ),
      dWorkspaceSucceedTs,
    );
    copyDirectory(
      Directory(
        join('test', 'sample_folder_ts', 'unlocalize_refs', 'git_succeed'),
      ),
      dWorkspaceSucceedGitTs,
    );
    copyDirectory(
      Directory(
        join(
          'test',
          'sample_folder_ts',
          'unlocalize_refs',
          'already_unlocalized',
        ),
      ),
      dWorkspaceAlreadyUnlocalizedTs,
    );
    copyDirectory(
      Directory(
        join('test', 'sample_folder_ts', 'unlocalize_refs', 'json_not_found'),
      ),
      dJsonNotFoundTs,
    );
  });

  tearDown(() {
    deleteDirs(<Directory>[
      dNoProjectRootError,
      dParseError,
      dNoDependencies,
      dNodeNotFound,
      dJsonNotFound,
      dWorkspaceSucceed,
      dWorkspaceSucceedGit,
      dWorkspaceAlreadyUnlocalized,
      dWorkspaceSucceedTs,
      dWorkspaceSucceedGitTs,
      dWorkspaceAlreadyUnlocalizedTs,
      dJsonNotFoundTs,
    ]);
  });

  group('UnlocalizeRefs Command', () {
    group('run()', () {
      // .....................................................................
      group('should print a usage description', () {
        test('when called args=[--help]', () async {
          capturePrint(
            ggLog: messages.add,
            code: () =>
                runner.run(<String>['change-refs-to-pub-dev', '--help']),
          );

          expect(
            messages.last,
            contains('Changes dependencies to remote dependencies.'),
          );
        });
      });

      // .....................................................................
      group('should throw', () {
        test('when project root was not found', () async {
          await expectLater(
            runner.run(<String>[
              'change-refs-to-pub-dev',
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
              join(dParseError.path, 'pubspec.yaml'),
            ).writeAsStringSync('invalid yaml');

            await expectLater(
              runner.run(<String>[
                'change-refs-to-pub-dev',
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

          File(join(dNodeNotFound.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test_package\nversion: 1.0.0\n'
            'dependencies: {}',
          );

          final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);

          await expectLater(
            () async {
              final language = DartProjectLanguage();
              final node = await language.createNode(dNodeNotFound);
              await processNode(
                node,
                <String, ProjectNode>{},
                <String>{},
                unlocal.modifyManifest,
                FileChangesBuffer(),
                localMessages.add,
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
          final dProject1 = Directory(join(dWorkspaceSucceed.path, 'project1'));

          final localMessages = <String>[];
          final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
          await unlocal.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages[0],
            contains('Running change-refs-to-pub-dev in'),
          );
          expect(localMessages[1], contains('Unlocalize refs of test1'));

          final resultYaml = File(
            join(dProject1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(resultYaml, isNot(contains('publish_to: none')));
        });

        test('when pubspec is correct and has git refs', () async {
          final dProject1 = Directory(
            join(dWorkspaceSucceedGit.path, 'project1'),
          );

          final localMessages = <String>[];
          final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
          await unlocal.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages[0],
            contains('Running change-refs-to-pub-dev in'),
          );
          expect(localMessages[1], contains('Unlocalize refs of test1'));
        });

        test('when already localized', () async {
          final dProject1 = Directory(
            join(dWorkspaceAlreadyUnlocalized.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = ChangeRefsToPubDev(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages[0],
            contains('Running change-refs-to-pub-dev in'),
          );
          expect(localMessages[1], contains('No files were changed'));
        });

        test('when .gg_localize_refs_backup.json does not exist', () async {
          final localMessages = <String>[];

          final dProject1 = Directory(join(dJsonNotFound.path, 'project1'));

          final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);

          await unlocal.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages[0],
            contains('Running change-refs-to-pub-dev in'),
          );
          expect(localMessages[1], contains('Unlocalize refs of test1'));
          expect(
            localMessages[2],
            contains(
              'The automatic change of dependencies could not be performed',
            ),
          );
        });

        test(
          'uses git version dependency when package was not published',
          () async {
            final workspace = createTempDir('unlocalize_unpublished_git_ws');
            final project1 = Directory(join(workspace.path, 'project1'));
            final project2 = Directory(join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(join(project1.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  project2:\n'
              '    path: ../project2\n',
            );
            File(join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n'
              'publish_to: none\n',
            );
            File(join(project1.path, '.gg', '.gg_localize_refs_backup.json'))
              ..createSync(recursive: true)
              ..writeAsStringSync('{"project2":"^2.0.4"}');

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: project2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/project2.git',
            ], workingDirectory: project2.path);

            final localMessages = <String>[];
            final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
            await unlocal.get(directory: project1, ggLog: localMessages.add);

            final resultYaml = File(
              join(project1.path, 'pubspec.yaml'),
            ).readAsStringSync();
            expect(
              resultYaml,
              contains('git: git@github.com:user/project2.git'),
            );
            expect(resultYaml, contains('version: ^2.0.4'));
            expect(resultYaml, isNot(contains('ref:')));
            expect(resultYaml, isNot(contains('tag_pattern:')));

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'does not treat git dependency with version as localized',
          () async {
            final workspace = createTempDir('unlocalize_git_version_noop_ws');
            final project1 = Directory(join(workspace.path, 'project1'));
            final project2 = Directory(join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(join(project1.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  project2:\n'
              '    git: git@github.com:user/project2.git\n'
              '    version: ^2.0.4\n',
            );
            File(join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );
            File(join(project1.path, '.gg', '.gg_localize_refs_backup.json'))
              ..createSync(recursive: true)
              ..writeAsStringSync('{"project2":"^2.0.4"}');

            final localMessages = <String>[];
            final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
            await unlocal.get(directory: project1, ggLog: localMessages.add);

            expect(
              localMessages[0],
              contains('Running change-refs-to-pub-dev in'),
            );
            expect(localMessages[1], contains('No files were changed'));

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'uses saved dependency map version when backup entry is a map',
          () async {
            final workspace = createTempDir('unlocalize_map_backup_version_ws');
            final project1 = Directory(join(workspace.path, 'project1'));
            final project2 = Directory(join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(join(project1.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  project2:\n'
              '    path: ../project2\n',
            );
            File(join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n'
              'publish_to: none\n',
            );
            File(join(project1.path, '.gg', '.gg_localize_refs_backup.json'))
              ..createSync(recursive: true)
              ..writeAsStringSync('{"project2":{"version":"^5.0.0"}}');

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: project2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/project2.git',
            ], workingDirectory: project2.path);

            final localMessages = <String>[];
            final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
            await unlocal.get(directory: project1, ggLog: localMessages.add);

            final resultYaml = File(
              join(project1.path, 'pubspec.yaml'),
            ).readAsStringSync();
            expect(resultYaml, contains('version: ^5.0.0'));

            deleteDirs(<Directory>[workspace]);
          },
        );

        test('TypeScript: when package.json is correct (path)', () async {
          final dProject1 = Directory(
            join(dWorkspaceSucceedTs.path, 'project1'),
          );
          await initGit(dProject1);
          final dProject2 = Directory(
            join(dWorkspaceSucceedTs.path, 'project2'),
          );
          await initGit(dProject2);

          final localMessages = <String>[];
          final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
          await unlocal.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages[0],
            contains('Running change-refs-to-pub-dev in'),
          );
          expect(localMessages[1], contains('Unlocalize refs of test1_ts'));

          final resultJson = File(
            join(dProject1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('"test2_ts":"git+'));
        });

        test('TypeScript: when package.json '
            'is correct and has git refs', () async {
          final dProject1 = Directory(
            join(dWorkspaceSucceedGitTs.path, 'project1'),
          );
          await initGit(dProject1);
          final dProject2 = Directory(
            join(dWorkspaceSucceedGitTs.path, 'project2'),
          );
          await initGit(dProject2);

          final localMessages = <String>[];
          final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
          await unlocal.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages[0],
            contains('Running change-refs-to-pub-dev in'),
          );
          expect(localMessages[1], contains('Unlocalize refs of test1_ts'));
        });

        test('TypeScript: when already localized', () async {
          final dProject1 = Directory(
            join(dWorkspaceAlreadyUnlocalizedTs.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = ChangeRefsToPubDev(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages[0],
            contains('Running change-refs-to-pub-dev in'),
          );
          expect(localMessages[1], contains('No files were changed'));
        });

        test(
          'TypeScript: when .gg_localize_refs_backup.json does not exist',
          () async {
            final localMessages = <String>[];

            final dProject1 = Directory(join(dJsonNotFoundTs.path, 'project1'));

            final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);

            await unlocal.get(directory: dProject1, ggLog: localMessages.add);

            expect(
              localMessages[0],
              contains('Running change-refs-to-pub-dev in'),
            );
            expect(localMessages[1], contains('Unlocalize refs of test1_ts'));
            expect(
              localMessages[2],
              contains(
                'The automatic change of dependencies could not be performed',
              ),
            );
            expect(localMessages[2], contains('package.json'));
          },
        );

        test(
          'TypeScript: handles package.json without dependency sections',
          () async {
            final root = Directory(
              join(dWorkspaceSucceedTs.path, 'nodeps_root'),
            );
            await createDirs(<Directory>[root]);
            final pkgDir = Directory(join(root.path, 'project_no_deps'));
            await createDirs(<Directory>[pkgDir]);

            File(
              join(pkgDir.path, 'package.json'),
            ).writeAsStringSync('{"name":"nodeps","version":"1.0.0"}');

            final language = TypeScriptProjectLanguage();
            final node = await language.createNode(pkgDir);
            final manifestFile = File(join(pkgDir.path, 'package.json'));
            final content = manifestFile.readAsStringSync();
            final manifestMap =
                language.parseManifestContent(content) as Map<String, dynamic>;

            final buffer = FileChangesBuffer();
            final unlocal = ChangeRefsToPubDev(ggLog: messages.add);
            await unlocal.modifyManifest(
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

        test('TypeScript: unlocalizes devDependencies when dependencies are '
            'missing', () async {
          final workspace = createTempDir('unlocalize_ts_dev_only_ws');
          final project1 = Directory(join(workspace.path, 'project1'));
          final project2 = Directory(join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          File(join(project1.path, 'package.json')).writeAsStringSync(
            '{"name":"proj1_ts","version":"1.0.0",'
            '"devDependencies":{"proj2_ts":"file:../project2"}}',
          );
          File(
            join(project2.path, 'package.json'),
          ).writeAsStringSync('{"name":"proj2_ts","version":"1.0.0"}');
          File(
            join(project1.path, '.gg_localize_refs_backup.json'),
          ).writeAsStringSync('{"proj2_ts":"^2.0.0"}');

          final localMessages = <String>[];
          final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
          await unlocal.get(directory: project1, ggLog: localMessages.add);

          final resultJson = File(
            join(project1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('"proj2_ts":"git+'));
          expect(resultJson, isNot(contains('file:')));

          deleteDirs(<Directory>[workspace]);
        });

        test('TypeScript: unlocalizes devDependencies with git+ when '
            'dependencies are missing', () async {
          final workspace = createTempDir('unlocalize_ts_dev_git_ws');
          final project1 = Directory(join(workspace.path, 'project1'));
          final project2 = Directory(join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          File(join(project1.path, 'package.json')).writeAsStringSync(
            '{"name":"proj1_ts_git","version":"1.0.0",'
            '"devDependencies":{"proj2_ts":'
            '"git+ssh://git@github.com:user/proj2_ts.git#main"}}',
          );
          File(
            join(project2.path, 'package.json'),
          ).writeAsStringSync('{"name":"proj2_ts","version":"1.0.0"}');
          File(
            join(project1.path, '.gg_localize_refs_backup.json'),
          ).writeAsStringSync('{"proj2_ts":"^2.0.0"}');

          final localMessages = <String>[];
          final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
          await unlocal.get(directory: project1, ggLog: localMessages.add);

          final resultJson = File(
            join(project1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('"proj2_ts":"git+'));

          deleteDirs(<Directory>[workspace]);
        });

        test(
          'TypeScript: falls back to git url when package was not published',
          () async {
            final workspace = createTempDir('unlocalize_ts_unpublished_git_ws');
            final project1 = Directory(join(workspace.path, 'project1'));
            final project2 = Directory(join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(join(project1.path, 'package.json')).writeAsStringSync(
              '{"name":"proj1_ts","version":"1.0.0",'
              '"dependencies":{"proj2_ts":"file:../project2"}}',
            );
            File(
              join(project2.path, 'package.json'),
            ).writeAsStringSync('{"name":"proj2_ts","version":"1.0.0"}');
            File(
              join(project1.path, '.gg_localize_refs_backup.json'),
            ).writeAsStringSync('{"proj2_ts":"^2.0.0"}');

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: project2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/proj2_ts.git',
            ], workingDirectory: project2.path);

            final localMessages = <String>[];
            final unlocal = ChangeRefsToPubDev(ggLog: localMessages.add);
            await unlocal.get(directory: project1, ggLog: localMessages.add);

            final resultJson = File(
              join(project1.path, 'package.json'),
            ).readAsStringSync();
            expect(resultJson, contains('"proj2_ts":"git+'));

            deleteDirs(<Directory>[workspace]);
          },
        );
      });
    });
  });

  group('readDependenciesFromJson', () {
    test('should throw an exception when the json file does not exist', () {
      const nonExistentFilePath = 'non_existent_file.json';

      expect(
        () => Utils.readDependenciesFromJson(nonExistentFilePath),
        throwsA(
          isA<Exception>().having(
            (Object e) => e.toString(),
            'message',
            contains(
              'The json file $nonExistentFilePath with old '
              'dependencies does not exist.',
            ),
          ),
        ),
      );
    });
  });
}
