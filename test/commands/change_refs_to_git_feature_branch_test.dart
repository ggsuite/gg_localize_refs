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
import 'package:gg_localize_refs/src/commands/change_refs_to_git_feature_branch.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;

  Directory dNoProjectRootError = Directory('');
  Directory dParseError = Directory('');
  Directory dNodeNotFound = Directory('');
  Directory dWorkspaceSucceed = Directory('');
  Directory dWorkspaceAlreadyLocalized = Directory('');
  Directory dGitNoRepo = Directory('');

  Directory dWorkspaceSucceedTs = Directory('');
  Directory dWorkspaceAlreadyLocalizedTs = Directory('');
  Directory dGitNoRepoTs = Directory('');

  setUp(() async {
    messages.clear();
    runner = CommandRunner<void>('gitrefs', 'Description of git refs command.');
    final myCommand = ChangeRefsToGitFeatureBranch(ggLog: messages.add);
    runner.addCommand(myCommand);

    dNoProjectRootError = createTempDir(
      'git_feature_no_project_root',
      'project1',
    );
    dParseError = createTempDir('git_feature_parse_error', 'project1');
    dNodeNotFound = createTempDir('git_feature_node_not_found', 'project1');
    dWorkspaceSucceed = createTempDir('git_feature_succeed');
    dWorkspaceAlreadyLocalized = createTempDir('git_feature_already_localized');
    dGitNoRepo = createTempDir('git_feature_git_no_repo');

    dWorkspaceSucceedTs = createTempDir('git_feature_ts_succeed');
    dWorkspaceAlreadyLocalizedTs = createTempDir(
      'git_feature_ts_already_localized',
    );
    dGitNoRepoTs = createTempDir('git_feature_ts_git_no_repo');

    copyDirectory(
      Directory(
        p.join('test', 'sample_folder', 'localize_refs', 'git_succeed'),
      ),
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
        p.join('test', 'sample_folder', 'localize_refs', 'git_no_repo'),
      ),
      dGitNoRepo,
    );

    copyDirectory(
      Directory(
        p.join('test', 'sample_folder_ts', 'localize_refs', 'git_succeed'),
      ),
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
        p.join('test', 'sample_folder_ts', 'localize_refs', 'git_no_repo'),
      ),
      dGitNoRepoTs,
    );
  });

  tearDown(() {
    deleteDirs(<Directory>[
      dNoProjectRootError,
      dParseError,
      dNodeNotFound,
      dWorkspaceSucceed,
      dWorkspaceAlreadyLocalized,
      dGitNoRepo,
      dWorkspaceSucceedTs,
      dWorkspaceAlreadyLocalizedTs,
      dGitNoRepoTs,
    ]);
  });

  group('ChangeRefsToGitFeatureBranch Command', () {
    group('run()', () {
      group('should print a usage description', () {
        test('when called args=[--help]', () async {
          capturePrint(
            ggLog: messages.add,
            code: () => runner.run(<String>[
              'change-refs-to-git-feature-branch',
              '--help',
            ]),
          );

          expect(
            messages.last,
            contains('Changes dependencies to git dependencies.'),
          );
          expect(messages.join('\n'), contains('--git-ref'));
        });
      });

      group('should throw', () {
        test('when project root was not found', () async {
          await expectLater(
            runner.run(<String>[
              'change-refs-to-git-feature-branch',
              '--input',
              dNoProjectRootError.path,
              '--git-ref',
              'feature/test',
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

        test('when --git-ref is missing', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceed.path, 'project1'),
          );

          await expectLater(
            runner.run(<String>[
              'change-refs-to-git-feature-branch',
              '--input',
              dProject1.path,
            ]),
            throwsA(
              isA<Exception>().having(
                (Object e) => e.toString(),
                'message',
                contains('Please provide the git ref via --git-ref'),
              ),
            ),
          );
        });

        test('when pubspec.yaml cannot be parsed', () async {
          File(
            p.join(dParseError.path, 'pubspec.yaml'),
          ).writeAsStringSync('invalid yaml');

          await expectLater(
            runner.run(<String>[
              'change-refs-to-git-feature-branch',
              '--input',
              dParseError.path,
              '--git-ref',
              'feature/test',
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

        test('when node not found', () async {
          final localMessages = <String>[];

          File(p.join(dNodeNotFound.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test_package\nversion: 1.0.0\n'
            'dependencies:',
          );

          final loc = ChangeRefsToGitFeatureBranch(ggLog: localMessages.add)
            ..gitRefOverride = 'feature/test';

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

        test('when repo has no git for Dart dependency', () async {
          final dProject1 = Directory(p.join(dGitNoRepo.path, 'project1'));

          await runner
              .run(<String>[
                'change-refs-to-git-feature-branch',
                '--git-ref',
                'feature/test',
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

        test('when repo has no git for TypeScript dependency', () async {
          final dProject1 = Directory(p.join(dGitNoRepoTs.path, 'project1'));

          await runner
              .run(<String>[
                'change-refs-to-git-feature-branch',
                '--git-ref',
                'feature/test',
                '--input',
                dProject1.path,
              ])
              .catchError((Object e) {
                expect(
                  e.toString(),
                  contains('Cannot get git remote url for dependency test2_ts'),
                );
              });
        });
      });

      group('should succeed', () {
        test('with Dart dependencies converts to git refs', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceed.path, 'project1'),
          );
          final dProject2 = Directory(
            p.join(dWorkspaceSucceed.path, 'project2'),
          );

          Process.runSync('git', <String>[
            'init',
          ], workingDirectory: dProject2.path);
          Process.runSync('git', <String>[
            'remote',
            'add',
            'origin',
            'git@github.com:user/test2.git',
          ], workingDirectory: dProject2.path);

          final localMessages = <String>[];
          final local = ChangeRefsToGitFeatureBranch(ggLog: localMessages.add);
          await local.get(
            directory: dProject1,
            ggLog: localMessages.add,
            gitRef: 'feature123',
          );

          expect(
            localMessages[0],
            contains('Running change-refs-to-git-feature-branch in'),
          );
          expect(localMessages[1], contains('Localize refs of test1'));

          final resultYaml = File(
            p.join(dProject1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(resultYaml, contains('test2:'));
          expect(resultYaml, contains('git:'));
          expect(resultYaml, contains('url: git@github.com:user/test2.git'));
          expect(resultYaml, contains('ref: feature123'));
          expect(resultYaml, contains('publish_to: none'));
        });

        test(
          'with Dart git version dependency converts to plain git ref',
          () async {
            final workspace = createTempDir('git_feature_tag_pattern_ws');
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  project2:\n'
              '    git: git@github.com:user/project2.git\n'
              '    version: ^2.0.4\n',
            );
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: project2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/project2.git',
            ], workingDirectory: project2.path);

            final local = ChangeRefsToGitFeatureBranch(ggLog: messages.add);
            await local.get(
              directory: project1,
              ggLog: messages.add,
              gitRef: 'feature/tag',
            );

            final resultYaml = File(
              p.join(project1.path, 'pubspec.yaml'),
            ).readAsStringSync();
            expect(resultYaml, contains('git:'));
            expect(resultYaml, contains('ref: feature/tag'));
            expect(resultYaml, isNot(contains('tag_pattern:')));
            expect(resultYaml, isNot(contains('version: ^2.0.4')));

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'keeps existing backup version when dependency was a path entry',
          () async {
            final workspace = createTempDir('git_feature_keep_path_backup_ws');
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

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: project2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/project2.git',
            ], workingDirectory: project2.path);

            final local = ChangeRefsToGitFeatureBranch(ggLog: messages.add);
            await local.get(
              directory: project1,
              ggLog: messages.add,
              gitRef: 'feature/path',
            );

            final backupJson = File(
              p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
            ).readAsStringSync();
            final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

            expect(backupMap['project2'], '^7.0.0');

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'keeps existing backup version when dependency was plain git ref',
          () async {
            final workspace = createTempDir('git_feature_keep_git_backup_ws');
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
              '      ref: old-feature\n',
            );
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );
            File(p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'))
              ..createSync(recursive: true)
              ..writeAsStringSync('{"project2":"^8.0.0"}');

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: project2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/project2.git',
            ], workingDirectory: project2.path);

            final local = ChangeRefsToGitFeatureBranch(ggLog: messages.add);
            await local.get(
              directory: project1,
              ggLog: messages.add,
              gitRef: 'feature/new',
            );

            final backupJson = File(
              p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
            ).readAsStringSync();
            final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

            expect(backupMap['project2'], '^8.0.0');

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'stores only version values in backup after converting to git refs',
          () async {
            final workspace = createTempDir('git_feature_backup_only_versions');
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  project2: ^3.1.0\n',
            );
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: project2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/project2.git',
            ], workingDirectory: project2.path);

            final local = ChangeRefsToGitFeatureBranch(ggLog: messages.add);
            await local.get(
              directory: project1,
              ggLog: messages.add,
              gitRef: 'feature/backup',
            );

            final backupJson = File(
              p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
            ).readAsStringSync();
            final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

            expect(backupMap['project2'], '^3.1.0');
            expect(backupJson, isNot(contains('path')));
            expect(backupJson, isNot(contains('git')));

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'backs up publish_to only for pub.dev and git version refs',
          () async {
            final workspace = createTempDir('git_feature_publish_to_allowed');
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'publish_to: none\n'
              'dependencies:\n'
              '  project2:\n'
              '    git: git@github.com:user/project2.git\n'
              '    version: ^2.0.0\n',
            );
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: project2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/project2.git',
            ], workingDirectory: project2.path);

            final local = ChangeRefsToGitFeatureBranch(ggLog: messages.add);
            await local.get(
              directory: project1,
              ggLog: messages.add,
              gitRef: 'feature/backup-publish-to',
            );

            final backupJson = File(
              p.join(project1.path, '.gg', '.gg_localize_refs_backup.json'),
            ).readAsStringSync();
            final backupMap = jsonDecode(backupJson) as Map<String, dynamic>;

            expect(backupMap['publish_to_original'], 'none');

            deleteDirs(<Directory>[workspace]);
          },
        );

        test('with TypeScript dependencies converts to git refs', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceedTs.path, 'project1'),
          );
          final dProject2 = Directory(
            p.join(dWorkspaceSucceedTs.path, 'project2'),
          );

          Process.runSync('git', <String>[
            'init',
          ], workingDirectory: dProject2.path);
          Process.runSync('git', <String>[
            'remote',
            'add',
            'origin',
            'git@github.com:user/test2_ts.git',
          ], workingDirectory: dProject2.path);

          final localMessages = <String>[];
          final local = ChangeRefsToGitFeatureBranch(ggLog: localMessages.add);
          await local.get(
            directory: dProject1,
            ggLog: localMessages.add,
            gitRef: 'feature123',
          );

          expect(
            localMessages[0],
            contains('Running change-refs-to-git-feature-branch in'),
          );
          expect(localMessages[1], contains('Localize refs of test1_ts'));

          final resultJson = File(
            p.join(dProject1.path, 'package.json'),
          ).readAsStringSync();
          expect(resultJson, contains('test2_ts'));
          expect(
            resultJson,
            contains('git+git@github.com:user/test2_ts.git#feature123'),
          );
        });

        test(
          'when already localized TypeScript dependency stays unchanged',
          () async {
            final workspace = createTempDir('git_feature_ts_already_git_ws');
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(p.join(project1.path, 'package.json')).writeAsStringSync(
              '{"name":"proj1_ts","version":"1.0.0",'
              '"dependencies":{"proj2_ts":"git+git@github.com:user/proj2_ts.git#feature123"}}',
            );
            File(
              p.join(project2.path, 'package.json'),
            ).writeAsStringSync('{"name":"proj2_ts","version":"1.0.0"}');

            final localMessages = <String>[];
            final local = ChangeRefsToGitFeatureBranch(
              ggLog: localMessages.add,
            );
            await local.get(
              directory: project1,
              ggLog: localMessages.add,
              gitRef: 'feature123',
            );

            expect(localMessages[1], contains('No files were changed.'));

            deleteDirs(<Directory>[workspace]);
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
            final local = ChangeRefsToGitFeatureBranch(ggLog: messages.add)
              ..gitRefOverride = 'feature/test';
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

        test(
          'TypeScript: converts devDependencies when dependencies are missing',
          () async {
            final workspace = createTempDir('git_feature_ts_dev_only_ws');
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

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: project2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/proj2_ts.git',
            ], workingDirectory: project2.path);

            await runner.run(<String>[
              'change-refs-to-git-feature-branch',
              '--git-ref',
              'feature/dev-only',
              '--input',
              project1.path,
            ]);

            final resultJson = File(
              p.join(project1.path, 'package.json'),
            ).readAsStringSync();
            expect(resultJson, contains('proj2_ts'));
            expect(resultJson, contains('git+'));
            expect(resultJson, contains('#feature/dev-only'));

            deleteDirs(<Directory>[workspace]);
          },
        );
      });
    });
  });
}
