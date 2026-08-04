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
// ignore: lines_longer_than_80_chars
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
// ignore: lines_longer_than_80_chars
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
  Directory dWorkspaceOverridesPresent = Directory('');

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
    dWorkspaceOverridesPresent = createTempDir('git_feature_overrides_present');

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
        p.join(
          'test',
          'sample_folder',
          'localize_refs',
          'git_overrides_present',
        ),
      ),
      dWorkspaceOverridesPresent,
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
      dWorkspaceOverridesPresent,
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
        test('with Dart dependencies writes git overrides', () async {
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

          final pubspecBefore = File(
            p.join(dProject1.path, 'pubspec.yaml'),
          ).readAsStringSync();

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

          // The git refs live in pubspec_overrides.yaml ...
          final overrides = File(
            p.join(dProject1.path, 'pubspec_overrides.yaml'),
          ).readAsStringSync();
          expect(overrides, contains('dependency_overrides:'));
          expect(overrides, contains('test2:'));
          expect(overrides, contains('url: git@github.com:user/test2.git'));
          expect(overrides, contains('ref: feature123'));

          // ... and pubspec.yaml keeps its published constraints.
          expect(
            File(p.join(dProject1.path, 'pubspec.yaml')).readAsStringSync(),
            pubspecBefore,
          );
        });

        test('running it twice changes nothing the second time', () async {
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

          final local = ChangeRefsToGitFeatureBranch(ggLog: messages.add);
          await local.get(
            directory: dProject1,
            ggLog: messages.add,
            gitRef: 'feature123',
          );

          final localMessages = <String>[];
          await ChangeRefsToGitFeatureBranch(ggLog: localMessages.add).get(
            directory: dProject1,
            ggLog: localMessages.add,
            gitRef: 'feature123',
          );

          expect(localMessages.join('\n'), contains('No files were changed.'));
        });

        test('writes a git ref for a transitive dependency', () async {
          // project1 -> project2 -> project3. Pub reads dependency_overrides
          // from the root package only, so project1 has to pin project3 to
          // the feature branch itself - otherwise it resolves against the
          // published constraint while its siblings sit on the branch.
          final workspace = createTempDir('git_feature_transitive_ws');
          final project1 = Directory(p.join(workspace.path, 'project1'));
          final project2 = Directory(p.join(workspace.path, 'project2'));
          final project3 = Directory(p.join(workspace.path, 'project3'));
          await createDirs(<Directory>[project1, project2, project3]);

          File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project1\n'
            'version: 1.0.0\n'
            'dependencies:\n'
            '  project2: ^1.0.0\n',
          );
          File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project2\n'
            'version: 1.0.0\n'
            'dependencies:\n'
            '  project3: ^1.0.0\n',
          );
          File(p.join(project3.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project3\n'
            'version: 1.0.0\n',
          );

          for (final MapEntry<Directory, String> entry in <Directory, String>{
            project2: 'git@github.com:user/project2.git',
            project3: 'git@github.com:user/project3.git',
          }.entries) {
            Process.runSync('git', <String>[
              'remote',
              'set-url',
              'origin',
              entry.value,
            ], workingDirectory: entry.key.path);
          }

          await ChangeRefsToGitFeatureBranch(ggLog: messages.add).get(
            directory: project1,
            ggLog: messages.add,
            gitRef: 'feature/transitive',
          );

          final overrides = File(
            p.join(project1.path, 'pubspec_overrides.yaml'),
          ).readAsStringSync();
          expect(overrides, contains('project2:'));
          expect(overrides, contains('project3:'));
          expect(overrides, contains('url: git@github.com:user/project3.git'));
          expect(
            RegExp(r'ref: feature/transitive').allMatches(overrides).length,
            2,
          );

          deleteDirs(<Directory>[workspace]);
        });

        test('replaces the local path overrides with git refs', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceOverridesPresent.path, 'project1'),
          );
          final dProject2 = Directory(
            p.join(dWorkspaceOverridesPresent.path, 'project2'),
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

          final overrides = File(
            p.join(dProject1.path, 'pubspec_overrides.yaml'),
          );
          expect(overrides.readAsStringSync(), contains('path: ../project2'));

          final pubspecBefore = File(
            p.join(dProject1.path, 'pubspec.yaml'),
          ).readAsStringSync();

          final localMessages = <String>[];
          final local = ChangeRefsToGitFeatureBranch(ggLog: localMessages.add);
          await local.get(
            directory: dProject1,
            ggLog: localMessages.add,
            gitRef: 'feature123',
          );

          final content = overrides.readAsStringSync();
          expect(content, isNot(contains('path: ../project2')));
          expect(content, contains('ref: feature123'));
          expect(
            File(p.join(dProject1.path, 'pubspec.yaml')).readAsStringSync(),
            pubspecBefore,
          );
        });

        test(
          'overrides a dependency pubspec.yaml already pins to a git ref',
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

            final overrides = File(
              p.join(project1.path, 'pubspec_overrides.yaml'),
            ).readAsStringSync();
            expect(overrides, contains('ref: feature/tag'));
            expect(overrides, isNot(contains('version: ^2.0.4')));

            // The published constraint of pubspec.yaml stays untouched.
            expect(
              File(p.join(project1.path, 'pubspec.yaml')).readAsStringSync(),
              contains('version: ^2.0.4'),
            );

            deleteDirs(<Directory>[workspace]);
          },
        );

        test('carries the dependency_overrides of pubspec.yaml over', () async {
          // Pub does not merge the two sections - an inherited override left
          // behind would silently stop being in effect.
          final workspace = createTempDir('git_feature_inherited_ws');
          final project1 = Directory(p.join(workspace.path, 'project1'));
          final project2 = Directory(p.join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project1\n'
            'version: 1.0.0\n'
            'dependencies:\n'
            '  project2: ^1.0.0\n'
            'dependency_overrides:\n'
            '  foreign: ^9.0.0\n',
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

          await ChangeRefsToGitFeatureBranch(ggLog: messages.add).get(
            directory: project1,
            ggLog: messages.add,
            gitRef: 'feature/inherited',
          );

          final overrides = File(
            p.join(project1.path, 'pubspec_overrides.yaml'),
          ).readAsStringSync();
          expect(overrides, contains('foreign: ^9.0.0'));
          expect(overrides, contains('ref: feature/inherited'));

          deleteDirs(<Directory>[workspace]);
        });

        test(
          'removes a pubspec_overrides.yaml entry from .gitignore',
          () async {
            // The file has to be committable: it is what makes the ticket
            // resolve against the feature branch on every checkout.
            final dProject1 = Directory(
              p.join(dWorkspaceSucceed.path, 'project1'),
            );
            final dProject2 = Directory(
              p.join(dWorkspaceSucceed.path, 'project2'),
            );

            File(
              p.join(dProject1.path, '.gitignore'),
            ).writeAsStringSync('pubspec_overrides.yaml\n');

            Process.runSync('git', <String>[
              'init',
            ], workingDirectory: dProject2.path);
            Process.runSync('git', <String>[
              'remote',
              'add',
              'origin',
              'git@github.com:user/test2.git',
            ], workingDirectory: dProject2.path);

            await ChangeRefsToGitFeatureBranch(ggLog: messages.add).get(
              directory: dProject1,
              ggLog: messages.add,
              gitRef: 'feature123',
            );

            expect(
              File(p.join(dProject1.path, '.gitignore')).readAsStringSync(),
              isNot(contains('pubspec_overrides.yaml')),
            );
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
          // SCP shorthand must be normalized to npm `git+ssh://…` form.
          expect(
            resultJson,
            contains('git+ssh://git@github.com/user/test2_ts.git#feature123'),
          );
        });

        test('TypeScript pnpm: writes git overrides into '
            'pnpm-workspace.yaml and leaves package.json untouched', () async {
          final workspace = createTempDir('git_feature_ts_pnpm_ws');
          copyDirectory(
            Directory(
              p.join(
                'test',
                'sample_folder_ts',
                'localize_refs',
                'pnpm_succeed',
              ),
            ),
            workspace,
          );
          final dProject1 = Directory(p.join(workspace.path, 'project1'));
          final dProject2 = Directory(p.join(workspace.path, 'project2'));

          Process.runSync('git', <String>[
            'init',
          ], workingDirectory: dProject2.path);
          Process.runSync('git', <String>[
            'remote',
            'add',
            'origin',
            'git@github.com:user/test2_ts.git',
          ], workingDirectory: dProject2.path);

          final manifestBefore = File(
            p.join(dProject1.path, 'package.json'),
          ).readAsStringSync();

          final localMessages = <String>[];
          final local = ChangeRefsToGitFeatureBranch(ggLog: localMessages.add);
          await local.get(
            directory: dProject1,
            ggLog: localMessages.add,
            gitRef: 'feature123',
          );

          expect(localMessages[1], contains('Localize refs of test1_ts'));

          // The manifest keeps its published constraints.
          final manifestAfter = File(
            p.join(dProject1.path, 'package.json'),
          ).readAsStringSync();
          expect(manifestAfter, manifestBefore);

          // The feature branch pin sits in the overrides, SCP shorthand
          // normalized to the npm `git+ssh://…` form.
          final overrides = File(
            p.join(dProject1.path, 'pnpm-workspace.yaml'),
          ).readAsStringSync();
          expect(
            overrides,
            contains(
              'test2_ts: '
              'git+ssh://git@github.com/user/test2_ts.git#feature123',
            ),
          );

          // A second run changes nothing.
          final againMessages = <String>[];
          await ChangeRefsToGitFeatureBranch(ggLog: againMessages.add).get(
            directory: dProject1,
            ggLog: againMessages.add,
            gitRef: 'feature123',
          );
          expect(againMessages[1], contains('No files were changed.'));

          deleteDirs(<Directory>[workspace]);
        });

        test('TypeScript pnpm: migrates a manifest an earlier version '
            'pinned in place', () async {
          final workspace = createTempDir('git_feature_ts_pnpm_legacy_ws');
          copyDirectory(
            Directory(
              p.join(
                'test',
                'sample_folder_ts',
                'localize_refs',
                'pnpm_legacy_localized',
              ),
            ),
            workspace,
          );
          final dProject1 = Directory(p.join(workspace.path, 'project1'));
          final dProject2 = Directory(p.join(workspace.path, 'project2'));

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
            localMessages.join('\n'),
            contains('Migrate refs of test1_ts out of package.json'),
          );

          // The backed up constraint is back in the manifest …
          final manifest = File(
            p.join(dProject1.path, 'package.json'),
          ).readAsStringSync();
          expect(manifest, contains('"test2_ts": "^1.0.0"'));
          expect(manifest, isNot(contains('link:')));

          // … and the pin moved into the overrides.
          final overrides = File(
            p.join(dProject1.path, 'pnpm-workspace.yaml'),
          ).readAsStringSync();
          expect(overrides, contains('#feature123'));

          deleteDirs(<Directory>[workspace]);
        });

        test('TypeScript pnpm: warns when the migration backup is missing '
            'but still writes the overrides', () async {
          final workspace = createTempDir('git_feature_ts_pnpm_nobackup_ws');
          copyDirectory(
            Directory(
              p.join(
                'test',
                'sample_folder_ts',
                'localize_refs',
                'pnpm_legacy_localized',
              ),
            ),
            workspace,
          );
          final dProject1 = Directory(p.join(workspace.path, 'project1'));
          final dProject2 = Directory(p.join(workspace.path, 'project2'));
          File(
            p.join(dProject1.path, '.gg', 'gg_localize_refs_backup_ts.json'),
          ).deleteSync();

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
            localMessages.join('\n'),
            contains('cannot be migrated automatically'),
          );

          final overrides = File(
            p.join(dProject1.path, 'pnpm-workspace.yaml'),
          ).readAsStringSync();
          expect(overrides, contains('#feature123'));

          deleteDirs(<Directory>[workspace]);
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
              '"dependencies":{"proj2_ts":'
              '"git+git@github.com:user/proj2_ts.git#feature123"}}',
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
