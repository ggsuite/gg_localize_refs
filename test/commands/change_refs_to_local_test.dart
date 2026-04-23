// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
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
import 'package:gg_localize_refs/src/commands/change_refs_to_local.dart';
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

  Directory dWorkspaceSucceedTs = Directory('');
  Directory dWorkspaceAlreadyLocalizedTs = Directory('');

  setUp(() async {
    messages.clear();
    runner = CommandRunner<void>('local', 'Description of local command.');
    final myCommand = ChangeRefsToLocal(ggLog: messages.add);
    runner.addCommand(myCommand);

    dNoProjectRootError = createTempDir('no_project_root_error', 'project1');
    dParseError = createTempDir('parse_error', 'project1');
    dNoDependencies = createTempDir('no_dependencies', 'project1');
    dNodeNotFound = createTempDir('node_not_found', 'project1');
    dWorkspaceSucceed = createTempDir('succeed');
    dWorkspaceAlreadyLocalized = createTempDir('already_localized');

    dWorkspaceSucceedTs = createTempDir('ts_succeed');
    dWorkspaceAlreadyLocalizedTs = createTempDir('ts_already_localized');

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
  });

  tearDown(() {
    deleteDirs(<Directory>[
      dNoProjectRootError,
      dParseError,
      dNoDependencies,
      dNodeNotFound,
      dWorkspaceAlreadyLocalized,
      dWorkspaceSucceed,
      dWorkspaceSucceedTs,
      dWorkspaceAlreadyLocalizedTs,
    ]);
  });

  group('Local Command', () {
    group('run()', () {
      group('should print a usage description', () {
        test('when called args=[--help]', () async {
          capturePrint(
            ggLog: messages.add,
            code: () => runner.run(<String>['change-refs-to-local', '--help']),
          );

          expect(
            messages.last,
            contains('Localize references to local path dependencies'),
          );
          expect(
            messages.join('\n'),
            isNot(contains('Use git references instead of local paths.')),
          );
          expect(messages.join('\n'), isNot(contains('--git-ref')));
        });
      });

      group('should throw', () {
        test('when project root was not found', () async {
          await expectLater(
            runner.run(<String>[
              'change-refs-to-local',
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
                'change-refs-to-local',
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

          final loc = ChangeRefsToLocal(ggLog: localMessages.add);

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

      group('should succeed', () {
        test('when pubspec is correct', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceed.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[0], contains('Running change-refs-to-local in'));
          expect(localMessages[1], contains('Localize refs of test1'));

          final resultYaml = File(
            p.join(dProject1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(resultYaml, contains('publish_to: none'));
          expect(resultYaml, contains('path: ../project2'));
          expect(resultYaml, isNot(contains('git:')));

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

          final gitignoreFile = File(p.join(dProject1.path, '.gitignore'));
          gitignoreFile.writeAsStringSync('build/\n');

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);

          await local.get(directory: dProject1, ggLog: localMessages.add);

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
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[0], contains('Running change-refs-to-local in'));
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
            '    git: git@github.com:ggsuite/testproject_gg_2.git\n'
            '    version: ^1.0.0\n',
          );
          File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project2\n'
            'version: 1.0.0\n',
          );

          final local = ChangeRefsToLocal(ggLog: messages.add);
          await local.get(directory: project1, ggLog: messages.add);

          final backupJson = File(
            p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

          expect(backupMap['project2'], '^1.0.0');

          deleteDirs(<Directory>[workspace]);
        });

        test(
          'backs up dependency version when dependency map has git and version',
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
              '    git: git@github.com:user/project2.git\n'
              '    version: ^4.0.0\n',
            );
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );

            final local = ChangeRefsToLocal(ggLog: messages.add);
            await local.get(directory: project1, ggLog: messages.add);

            final backupJson = File(
              p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
            ).readAsStringSync();
            final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

            expect(backupMap['project2'], '^4.0.0');

            deleteDirs(<Directory>[workspace]);
          },
        );

        test('keeps existing backup version when '
            'dependency is already a path entry', () async {
          final workspace = createTempDir('localize_keep_path_backup_ws');
          final project1 = Directory(p.join(workspace.path, 'project1'));
          final project2 = Directory(p.join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project1\n'
            'version: 1.0.0\n'
            'dependencies:\n'
            '  project2:\n'
            '    path: ../project2\n',
          );
          File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project2\n'
            'version: 1.0.0\n',
          );
          File(p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'))
            ..createSync(recursive: true)
            ..writeAsStringSync('{"project2":"^7.0.0"}');

          final local = ChangeRefsToLocal(ggLog: messages.add);
          await local.get(directory: project1, ggLog: messages.add);

          final backupJson = File(
            p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

          expect(backupMap['project2'], '^7.0.0');
          expect(backupJson, isNot(contains('path')));
          expect(backupJson, isNot(contains('git')));

          deleteDirs(<Directory>[workspace]);
        });

        test(
          'keeps existing backup version when dependency is plain git ref',
          () async {
            final workspace = createTempDir('localize_keep_git_backup_ws');
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
              '      ref: main\n',
            );
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );
            File(p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'))
              ..createSync(recursive: true)
              ..writeAsStringSync('{"project2":"^8.0.0"}');

            final local = ChangeRefsToLocal(ggLog: messages.add);
            await local.get(directory: project1, ggLog: messages.add);

            final backupJson = File(
              p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
            ).readAsStringSync();
            final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

            expect(backupMap['project2'], '^8.0.0');
            expect(backupJson, isNot(contains('path')));
            expect(backupJson, isNot(contains('git')));

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'backs up publish_to only for pub.dev and git version refs',
          () async {
            final workspace = createTempDir(
              'localize_publish_to_backup_allowed',
            );
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'publish_to: none\n'
              'dependencies:\n'
              '  project2: ^1.2.3\n',
            );
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );

            final local = ChangeRefsToLocal(ggLog: messages.add);
            await local.get(directory: project1, ggLog: messages.add);

            final backupJson = File(
              p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
            ).readAsStringSync();
            final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

            expect(backupMap['publish_to_original'], 'none');

            deleteDirs(<Directory>[workspace]);
          },
        );

        test('does not back up publish_to for plain git refs', () async {
          final workspace = createTempDir('localize_publish_to_backup_blocked');
          final project1 = Directory(p.join(workspace.path, 'project1'));
          final project2 = Directory(p.join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project1\n'
            'version: 1.0.0\n'
            'publish_to: none\n'
            'dependencies:\n'
            '  project2:\n'
            '    git:\n'
            '      url: git@github.com:user/project2.git\n'
            '      ref: main\n',
          );
          File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project2\n'
            'version: 1.0.0\n',
          );

          final local = ChangeRefsToLocal(ggLog: messages.add);
          await local.get(directory: project1, ggLog: messages.add);

          final backupJson = File(
            p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

          expect(backupMap.containsKey('publish_to_original'), isFalse);

          deleteDirs(<Directory>[workspace]);
        });

        test('TypeScript: when package.json is correct (path mode)', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceedTs.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[0], contains('Running change-refs-to-local in'));
          expect(localMessages[1], contains('Localize refs of test1_ts'));

          final resultJson = File(
            p.join(dProject1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('"test2_ts": "file:../project2"'));

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
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[0], contains('Running change-refs-to-local in'));
          expect(localMessages[1], contains('No files were changed.'));
        });

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
            final local = ChangeRefsToLocal(ggLog: messages.add);
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
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: project1, ggLog: localMessages.add);

          final resultJson = File(
            p.join(project1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('"proj2_ts": "file:../project2"'));

          final backupJson = File(
            p.join(project1.path, '.gg_localize_refs_backup.json'),
          ).readAsStringSync();
          expect(backupJson, contains('^1.0.0'));

          deleteDirs(<Directory>[workspace]);
        });
      });
    });
  });
}
