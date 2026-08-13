// @license
// Copyright (c) ggsuite
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
import 'package:gg_localize_refs/src/backend/pnpm_workspace_io.dart';
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
  Directory dWorkspaceTransitive = Directory('');

  Directory dWorkspaceLegacy = Directory('');
  Directory dWorkspaceLegacyPrivate = Directory('');
  Directory dWorkspaceLegacyNoBackup = Directory('');
  Directory dWorkspaceOverridesUnrelated = Directory('');
  Directory dWorkspaceLegacyNoDepsBackup = Directory('');

  Directory dWorkspaceSucceedTs = Directory('');
  Directory dWorkspaceAlreadyLocalizedTs = Directory('');
  Directory dWorkspacePnpmSucceed = Directory('');
  Directory dWorkspacePnpmAlreadyLocalized = Directory('');
  Directory dWorkspacePnpmLegacy = Directory('');
  Directory dWorkspacePnpmOverridesUnrelated = Directory('');

  /// Copies the Dart scenario [name] of `localize_refs` into [target].
  void copyLocalizeScenario(String name, Directory target) {
    copyDirectory(
      Directory(p.join('test', 'sample_folder', 'localize_refs', name)),
      target,
    );
  }

  /// Copies the TypeScript scenario [name] of `localize_refs` into [target].
  void copyLocalizeScenarioTs(String name, Directory target) {
    copyDirectory(
      Directory(p.join('test', 'sample_folder_ts', 'localize_refs', name)),
      target,
    );
  }

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
    dWorkspaceTransitive = createTempDir('transitive');

    dWorkspaceLegacy = createTempDir('legacy_localized');
    dWorkspaceLegacyPrivate = createTempDir('legacy_localized_private');
    dWorkspaceLegacyNoBackup = createTempDir('legacy_localized_no_backup');
    dWorkspaceOverridesUnrelated = createTempDir('overrides_unrelated');
    dWorkspaceLegacyNoDepsBackup = createTempDir('legacy_no_deps_backup');

    dWorkspaceSucceedTs = createTempDir('ts_succeed');
    dWorkspaceAlreadyLocalizedTs = createTempDir('ts_already_localized');
    dWorkspacePnpmSucceed = createTempDir('ts_pnpm_succeed');
    dWorkspacePnpmAlreadyLocalized = createTempDir('ts_pnpm_already_localized');
    dWorkspacePnpmLegacy = createTempDir('ts_pnpm_legacy');
    dWorkspacePnpmOverridesUnrelated = createTempDir(
      'ts_pnpm_overrides_unrelated',
    );

    copyLocalizeScenarioTs('pnpm_succeed', dWorkspacePnpmSucceed);
    copyLocalizeScenarioTs(
      'pnpm_already_localized',
      dWorkspacePnpmAlreadyLocalized,
    );
    copyLocalizeScenarioTs('pnpm_legacy_localized', dWorkspacePnpmLegacy);
    copyLocalizeScenarioTs(
      'pnpm_overrides_unrelated',
      dWorkspacePnpmOverridesUnrelated,
    );

    copyLocalizeScenario('legacy_localized', dWorkspaceLegacy);
    copyLocalizeScenario('legacy_localized_private', dWorkspaceLegacyPrivate);
    copyLocalizeScenario(
      'legacy_localized_no_backup',
      dWorkspaceLegacyNoBackup,
    );
    copyLocalizeScenario('overrides_unrelated', dWorkspaceOverridesUnrelated);
    copyLocalizeScenario('transitive', dWorkspaceTransitive);
    copyDirectory(
      Directory(
        p.join('test', 'sample_folder', 'unlocalize_refs', 'json_not_found'),
      ),
      dWorkspaceLegacyNoDepsBackup,
    );

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
      dWorkspaceLegacy,
      dWorkspaceLegacyPrivate,
      dWorkspaceLegacyNoBackup,
      dWorkspaceOverridesUnrelated,
      dWorkspaceLegacyNoDepsBackup,
      dWorkspaceTransitive,
      dWorkspaceSucceedTs,
      dWorkspaceAlreadyLocalizedTs,
      dWorkspacePnpmSucceed,
      dWorkspacePnpmAlreadyLocalized,
      dWorkspacePnpmLegacy,
      dWorkspacePnpmOverridesUnrelated,
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
            File(p.join(dParseError.path, 'pubspec.yaml'))
                .writeAsStringSync('invalid yaml');

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
        test('overriding a transitive workspace dependency', () async {
          // test1 -> test2 -> test3. Pub reads dependency_overrides from the
          // root package only, so the override test2 declares for test3 is
          // ignored while building test1: without an entry of its own, test1
          // would resolve test3 from pub.dev.
          final dProject1 = Directory(
            p.join(dWorkspaceTransitive.path, 'project1'),
          );

          await ChangeRefsToLocal(ggLog: messages.add)
              .get(directory: dProject1, ggLog: messages.add);

          final overrides = File(
            p.join(dProject1.path, 'pubspec_overrides.yaml'),
          ).readAsStringSync();
          expect(overrides, contains('path: ../project2'));
          expect(overrides, contains('path: ../project3'));

          // The direct dependency keeps overriding only what it reaches.
          final overrides2 = File(
            p.join(
              dWorkspaceTransitive.path,
              'project2',
              'pubspec_overrides.yaml',
            ),
          ).readAsStringSync();
          expect(overrides2, contains('path: ../project3'));
          expect(overrides2, isNot(contains('path: ../project1')));

          // pubspec.yaml declares test3 nowhere - the override is the only
          // place the transitive dependency shows up.
          expect(
            File(p.join(dProject1.path, 'pubspec.yaml')).readAsStringSync(),
            isNot(contains('test3')),
          );
        });

        test('when pubspec is correct', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceed.path, 'project1'),
          );

          final pubspecBefore = File(p.join(dProject1.path, 'pubspec.yaml'))
              .readAsStringSync();

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[0], contains('Running change-refs-to-local in'));
          expect(localMessages[1], contains('Localize refs of test1'));

          // pubspec.yaml keeps its published constraints untouched.
          final resultYaml = File(p.join(dProject1.path, 'pubspec.yaml'))
              .readAsStringSync();
          expect(resultYaml, pubspecBefore);
          expect(resultYaml, isNot(contains('publish_to')));
          expect(resultYaml, isNot(contains('path:')));

          // The local wiring lives in pubspec_overrides.yaml.
          final overrides = File(
            p.join(dProject1.path, 'pubspec_overrides.yaml'),
          );
          expect(overrides.existsSync(), isTrue);
          final overridesContent = overrides.readAsStringSync();
          expect(overridesContent, contains('dependency_overrides:'));
          expect(overridesContent, contains('path: ../project2'));

          // test2 is a dependency AND a dev_dependency, but a YAML map must
          // not carry the same key twice.
          expect(
            RegExp(
              r'^\s+test2:',
              multiLine: true,
            ).allMatches(overridesContent).length,
            1,
          );

          // Localizing needs no dependency backup anymore: pubspec.yaml is
          // still the single source of truth for the remote refs.
          expect(
            File(
              p.join(
                dProject1.path,
                '.gg',
                'gg_localize_refs_backup_dart.json',
              ),
            ).existsSync(),
            isFalse,
          );

          final gitignoreFile = File(p.join(dProject1.path, '.gitignore'));
          expect(gitignoreFile.existsSync(), isTrue);
          final gitignoreContent = gitignoreFile.readAsStringSync();
          expect(gitignoreContent, contains('.gg'));
          expect(gitignoreContent, contains('!.gg/gg.json'));

          // The overrides file has to stay committable: it carries the local
          // wiring of a shared ticket workspace.
          expect(gitignoreContent, isNot(contains('pubspec_overrides.yaml')));
        });

        test(
          'drops a stale pubspec_overrides.yaml entry from .gitignore',
          () async {
            final dProject1 = Directory(
              p.join(dWorkspaceSucceed.path, 'project1'),
            );
            final gitignoreFile = File(p.join(dProject1.path, '.gitignore'))
              ..writeAsStringSync('build/\npubspec_overrides.yaml\n');

            final local = ChangeRefsToLocal(ggLog: messages.add);
            await local.get(directory: dProject1, ggLog: messages.add);

            // Gitignored AND checked in is the one combination that makes
            // dart pub publish fail, so the stale entry must go.
            final content = gitignoreFile.readAsStringSync();
            expect(content, contains('build/'));
            expect(content, isNot(contains('pubspec_overrides.yaml')));
          },
        );

        test('when run twice nothing is changed the second time', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceed.path, 'project1'),
          );

          final local = ChangeRefsToLocal(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          final overrides = File(
            p.join(dProject1.path, 'pubspec_overrides.yaml'),
          );
          final afterFirstRun = overrides.readAsStringSync();

          final secondMessages = <String>[];
          await local.get(directory: dProject1, ggLog: secondMessages.add);

          expect(secondMessages[1], contains('No files were changed.'));
          expect(overrides.readAsStringSync(), afterFirstRun);
        });

        test('carries the dependency_overrides of pubspec.yaml over', () async {
          final workspace = createTempDir('localize_inherited_overrides_ws');
          final project1 = Directory(p.join(workspace.path, 'project1'));
          final project2 = Directory(p.join(workspace.path, 'project2'));
          await createDirs(<Directory>[project1, project2]);

          const pubspec =
              'name: project1\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  project2: ^1.0.0\n'
              'dependency_overrides:\n'
              '  pinned: 1.2.3\n';

          File(p.join(project1.path, 'pubspec.yaml'))
              .writeAsStringSync(pubspec);
          File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
            'name: project2\n'
            'version: 1.0.0\n',
          );

          final local = ChangeRefsToLocal(ggLog: messages.add);
          await local.get(directory: project1, ggLog: messages.add);

          // Pub replaces the section of pubspec.yaml instead of merging it, so
          // the inherited entry has to travel along or it stops applying.
          final overridesContent = File(
            p.join(project1.path, 'pubspec_overrides.yaml'),
          ).readAsStringSync();
          expect(overridesContent, contains('path: ../project2'));
          expect(overridesContent, contains('pinned: 1.2.3'));

          expect(
            File(p.join(project1.path, 'pubspec.yaml')).readAsStringSync(),
            pubspec,
          );

          deleteDirs(<Directory>[workspace]);
        });

        test('does not create an empty .gg directory', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceSucceed.path, 'project1'),
          );

          final local = ChangeRefsToLocal(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          expect(
            Directory(p.join(dProject1.path, '.gg')).existsSync(),
            isFalse,
          );
        });

        test(
          'prunes the override of a dependency that left pubspec.yaml',
          () async {
            final workspace = createTempDir('localize_prune_ws');
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            final project3 = Directory(p.join(workspace.path, 'project3'));
            await createDirs(<Directory>[project1, project2, project3]);

            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );
            File(p.join(project3.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project3\n'
              'version: 1.0.0\n',
            );

            final pubspec1 = File(p.join(project1.path, 'pubspec.yaml'))
              ..writeAsStringSync(
                'name: project1\n'
                'version: 1.0.0\n'
                'dependencies:\n'
                '  project2: ^1.0.0\n'
                '  project3: ^1.0.0\n',
              );

            final local = ChangeRefsToLocal(ggLog: messages.add);
            await local.get(directory: project1, ggLog: messages.add);

            final overrides = File(
              p.join(project1.path, 'pubspec_overrides.yaml'),
            );
            expect(overrides.readAsStringSync(), contains('project3:'));

            // project3 leaves the manifest. Its override has to go too: pub
            // pulls every overridden package into the resolution, declared or
            // not.
            pubspec1.writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  project2: ^1.0.0\n',
            );

            await local.get(directory: project1, ggLog: messages.add);

            final content = overrides.readAsStringSync();
            expect(content, contains('project2:'));
            expect(content, isNot(contains('project3:')));

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'localizes a dependency declared only in dev_dependencies',
          () async {
            final workspace = createTempDir('localize_dev_only_ws');
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            File(p.join(project1.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project1\n'
              'version: 1.0.0\n'
              'dev_dependencies:\n'
              '  project2: ^1.0.0\n',
            );
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );

            final local = ChangeRefsToLocal(ggLog: messages.add);
            await local.get(directory: project1, ggLog: messages.add);

            final overridesContent = File(
              p.join(project1.path, 'pubspec_overrides.yaml'),
            ).readAsStringSync();
            expect(overridesContent, contains('project2:'));
            expect(overridesContent, contains('path: ../project2'));

            deleteDirs(<Directory>[workspace]);
          },
        );

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
          expect(gitignoreContent, contains('!.gg/gg.json'));
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

        test(
          'writes no dependency backup and keeps pubspec.yaml as is',
          () async {
            final workspace = createTempDir('localize_no_backup_ws');
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            const pubspec =
                'name: project1\n'
                'version: 1.0.0\n'
                'dependencies:\n'
                '  project2:\n'
                '    git: git@github.com:ggsuite/testproject_gg_2.git\n'
                '    version: ^1.0.0\n';

            File(p.join(project1.path, 'pubspec.yaml'))
                .writeAsStringSync(pubspec);
            File(p.join(project2.path, 'pubspec.yaml')).writeAsStringSync(
              'name: project2\n'
              'version: 1.0.0\n',
            );

            final local = ChangeRefsToLocal(ggLog: messages.add);
            await local.get(directory: project1, ggLog: messages.add);

            // A git ref carrying a version is a remote ref, so it stays.
            expect(
              File(p.join(project1.path, 'pubspec.yaml')).readAsStringSync(),
              pubspec,
            );

            expect(
              File(
                p.join(
                  project1.path,
                  '.gg',
                  'gg_localize_refs_backup_dart.json',
                ),
              ).existsSync(),
              isFalse,
            );
            expect(
              File(
                p.join(
                  project1.path,
                  '.gg',
                  'gg_localize_refs_backup_dart.yaml',
                ),
              ).existsSync(),
              isFalse,
            );

            expect(
              File(p.join(project1.path, 'pubspec_overrides.yaml'))
                  .readAsStringSync(),
              contains('path: ../project2'),
            );

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'migrates a legacy path ref back into a version constraint',
          () async {
            final workspace = createTempDir('localize_migrate_path_ws');
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
            File(
                p.join(
                  project1.path,
                  '.gg',
                  'gg_localize_refs_backup_dart.json',
                ),
              )
              ..createSync(recursive: true)
              ..writeAsStringSync('{"project2":"^7.0.0"}');

            final localMessages = <String>[];
            final local = ChangeRefsToLocal(ggLog: localMessages.add);
            await local.get(directory: project1, ggLog: localMessages.add);

            expect(
              localMessages.join('\n'),
              contains('Migrate refs of project1 out of pubspec.yaml'),
            );

            final resultYaml = File(p.join(project1.path, 'pubspec.yaml'))
                .readAsStringSync();
            expect(resultYaml, contains('project2: ^7.0.0'));
            expect(resultYaml, isNot(contains('path:')));

            expect(
              File(p.join(project1.path, 'pubspec_overrides.yaml'))
                  .readAsStringSync(),
              contains('path: ../project2'),
            );

            // The backup is left as it was - git feature branch mode owns it.
            final backupJson = File(
              p.join(project1.path, '.gg', 'gg_localize_refs_backup_dart.json'),
            ).readAsStringSync();
            expect(
              (jsonDecode(backupJson) as Map<String, dynamic>)['project2'],
              '^7.0.0',
            );

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'migrates a git feature branch ref back into a version constraint',
          () async {
            final workspace = createTempDir('localize_migrate_git_ws');
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
            File(
                p.join(
                  project1.path,
                  '.gg',
                  'gg_localize_refs_backup_dart.json',
                ),
              )
              ..createSync(recursive: true)
              ..writeAsStringSync('{"project2":"^8.0.0"}');

            final local = ChangeRefsToLocal(ggLog: messages.add);
            await local.get(directory: project1, ggLog: messages.add);

            final resultYaml = File(p.join(project1.path, 'pubspec.yaml'))
                .readAsStringSync();
            expect(resultYaml, contains('project2: ^8.0.0'));
            expect(resultYaml, isNot(contains('git:')));

            expect(
              File(p.join(project1.path, 'pubspec_overrides.yaml'))
                  .readAsStringSync(),
              contains('path: ../project2'),
            );

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'leaves publish_to alone when nothing has to be migrated',
          () async {
            final workspace = createTempDir('localize_publish_to_kept');
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

            final resultYaml = File(p.join(project1.path, 'pubspec.yaml'))
                .readAsStringSync();
            expect(resultYaml, contains('publish_to: none'));
            expect(resultYaml, contains('project2: ^1.2.3'));

            deleteDirs(<Directory>[workspace]);
          },
        );

        test(
          'reverts the injected publish_to when no refs are localized',
          () async {
            final workspace = createTempDir('localize_publish_to_revert');
            final project1 = Directory(p.join(workspace.path, 'project1'));
            final project2 = Directory(p.join(workspace.path, 'project2'));
            await createDirs(<Directory>[project1, project2]);

            // The refs are not localized, only the publish_to was injected.
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

            final backupFile = File(
              p.join(
                project1.path,
                '.gg',
                'gg_localize_refs_publish_to_backup.json',
              ),
            );
            backupFile.parent.createSync(recursive: true);
            backupFile.writeAsStringSync('{"publish_to_original": null}');

            final localMessages = <String>[];
            final local = ChangeRefsToLocal(ggLog: localMessages.add);
            await local.get(directory: project1, ggLog: localMessages.add);

            expect(
              localMessages,
              contains('Revert the injected publish_to of project1'),
            );

            final resultYaml = File(p.join(project1.path, 'pubspec.yaml'))
                .readAsStringSync();
            expect(resultYaml, isNot(contains('publish_to')));
            expect(resultYaml, contains('project2: ^1.2.3'));

            deleteDirs(<Directory>[workspace]);
          },
        );

        test('migrates a legacy workspace and removes the injected '
            'publish_to', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceLegacy.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          final resultYaml = File(p.join(dProject1.path, 'pubspec.yaml'))
              .readAsStringSync();
          expect(resultYaml, contains('test2: ^1.0.0'));
          expect(resultYaml, isNot(contains('path:')));
          expect(resultYaml, isNot(contains('publish_to')));

          // The line based replacement drops the trailing newline. Without the
          // fixup every migration adds a "no newline at end of file" diff.
          expect(resultYaml, endsWith('\n'));

          expect(
            File(p.join(dProject1.path, 'pubspec_overrides.yaml'))
                .readAsStringSync(),
            contains('path: ../project2'),
          );

          // The publish_to backup survives - the git feature branch mode
          // injects publish_to: none again and relies on it.
          expect(
            File(
              p.join(
                dProject1.path,
                '.gg',
                'gg_localize_refs_publish_to_backup.json',
              ),
            ).existsSync(),
            isTrue,
          );
        });

        test('keeps publish_to: none of a package that is private by '
            'intention', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceLegacyPrivate.path, 'project1'),
          );

          final local = ChangeRefsToLocal(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          final resultYaml = File(p.join(dProject1.path, 'pubspec.yaml'))
              .readAsStringSync();
          expect(resultYaml, contains('test2: ^1.0.0'));
          expect(resultYaml, contains('publish_to: none'));
          expect(
            RegExp(
              r'^publish_to:',
              multiLine: true,
            ).allMatches(resultYaml).length,
            1,
          );
        });

        test('keeps publish_to: none and warns when there is no publish_to '
            'backup', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceLegacyNoBackup.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages.join('\n'),
            contains('Kept publish_to: none in'),
          );

          final resultYaml = File(p.join(dProject1.path, 'pubspec.yaml'))
              .readAsStringSync();
          expect(resultYaml, contains('test2: ^1.0.0'));
          expect(resultYaml, contains('publish_to: none'));
        });

        test('warns and localizes anyway when the dependency backup of a '
            'legacy workspace is missing', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceLegacyNoDepsBackup.path, 'project1'),
          );

          final pubspecBefore = File(p.join(dProject1.path, 'pubspec.yaml'))
              .readAsStringSync();

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages.join('\n'),
            contains('cannot be migrated automatically'),
          );

          // pubspec.yaml is left to the user, but the overrides are written.
          expect(
            File(p.join(dProject1.path, 'pubspec.yaml')).readAsStringSync(),
            pubspecBefore,
          );
          expect(
            File(p.join(dProject1.path, 'pubspec_overrides.yaml'))
                .readAsStringSync(),
            contains('path: ../project2'),
          );
        });

        test('merges into a hand written pubspec_overrides.yaml', () async {
          final dProject1 = Directory(
            p.join(dWorkspaceOverridesUnrelated.path, 'project1'),
          );

          final local = ChangeRefsToLocal(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          final overridesContent = File(
            p.join(dProject1.path, 'pubspec_overrides.yaml'),
          ).readAsStringSync();

          expect(overridesContent, contains('# Local experiment - keep me'));
          expect(overridesContent, contains('some_third_party:'));
          expect(
            overridesContent,
            contains('path: ../../vendor/some_third_party'),
          );
          expect(overridesContent, contains('test2:'));
          expect(overridesContent, contains('path: ../project2'));
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

          final resultJson = File(p.join(dProject1.path, 'package.json'))
              .readAsStringSync();
          expect(resultJson, contains('"test2_ts": "link:../project2"'));

          final backupJson = File(
            p.join(dProject1.path, '.gg', 'gg_localize_refs_backup_ts.json'),
          ).readAsStringSync();
          expect(backupJson, contains('^1.0.0'));

          // A TypeScript project never gets a pubspec_overrides.yaml.
          expect(
            File(p.join(dProject1.path, 'pubspec_overrides.yaml')).existsSync(),
            isFalse,
          );
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

            File(p.join(pkgDir.path, 'package.json'))
                .writeAsStringSync('{"name":"nodeps","version":"1.0.0"}');

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
          File(p.join(project2.path, 'package.json'))
              .writeAsStringSync('{"name":"proj2_ts","version":"1.0.0"}');

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: project1, ggLog: localMessages.add);

          final resultJson = File(p.join(project1.path, 'package.json'))
              .readAsStringSync();
          expect(resultJson, contains('"proj2_ts": "link:../project2"'));

          final backupJson = File(
            p.join(project1.path, '.gg', 'gg_localize_refs_backup_ts.json'),
          ).readAsStringSync();
          expect(backupJson, contains('^1.0.0'));

          deleteDirs(<Directory>[workspace]);
        });

        test('TypeScript pnpm: writes overrides into pnpm-workspace.yaml '
            'and leaves package.json untouched', () async {
          final dProject1 = Directory(
            p.join(dWorkspacePnpmSucceed.path, 'project1'),
          );
          final manifestBefore = File(p.join(dProject1.path, 'package.json'))
              .readAsStringSync();

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[1], contains('Localize refs of test1_ts'));

          // The manifest keeps its published constraints.
          final manifestAfter = File(p.join(dProject1.path, 'package.json'))
              .readAsStringSync();
          expect(manifestAfter, manifestBefore);
          expect(manifestAfter, contains('^1.0.0'));

          // The redirection sits in the overrides of pnpm-workspace.yaml.
          final overrides = File(p.join(dProject1.path, 'pnpm-workspace.yaml'))
              .readAsStringSync();
          expect(overrides, startsWith(PnpmWorkspaceIo.headerComment));
          expect(overrides, contains('test2_ts: link:../project2'));

          // Nothing was replaced, so there is nothing to back up.
          expect(
            File(
              p.join(dProject1.path, '.gg', 'gg_localize_refs_backup_ts.json'),
            ).existsSync(),
            isFalse,
          );
        });

        test('TypeScript pnpm: when already localized', () async {
          final dProject1 = Directory(
            p.join(dWorkspacePnpmAlreadyLocalized.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(localMessages[1], contains('No files were changed.'));
        });

        test('TypeScript pnpm: migrates a manifest an earlier version '
            'localized in place', () async {
          final dProject1 = Directory(
            p.join(dWorkspacePnpmLegacy.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages.join('\n'),
            contains('Migrate refs of test1_ts out of package.json'),
          );

          // The backed up constraints are back in the manifest …
          final manifest = File(p.join(dProject1.path, 'package.json'))
              .readAsStringSync();
          expect(manifest, contains('"test2_ts": "^1.0.0"'));
          expect(manifest, isNot(contains('link:')));

          // … and the redirection moved into the overrides.
          final overrides = File(p.join(dProject1.path, 'pnpm-workspace.yaml'))
              .readAsStringSync();
          expect(overrides, contains('test2_ts: link:../project2'));
        });

        test('TypeScript pnpm: warns when the migration backup is missing '
            'but still writes the overrides', () async {
          final dProject1 = Directory(
            p.join(dWorkspacePnpmLegacy.path, 'project1'),
          );
          File(p.join(dProject1.path, '.gg', 'gg_localize_refs_backup_ts.json'))
              .deleteSync();

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          expect(
            localMessages.join('\n'),
            contains('cannot be migrated automatically'),
          );

          // The manifest keeps its localized specs …
          final manifest = File(p.join(dProject1.path, 'package.json'))
              .readAsStringSync();
          expect(manifest, contains('link:../project2'));

          // … but the overrides are written anyway, so the workspace works.
          final overrides = File(p.join(dProject1.path, 'pnpm-workspace.yaml'))
              .readAsStringSync();
          expect(overrides, contains('test2_ts: link:../project2'));
        });

        test('TypeScript pnpm: merges into a hand written '
            'pnpm-workspace.yaml', () async {
          final dProject1 = Directory(
            p.join(dWorkspacePnpmOverridesUnrelated.path, 'project1'),
          );

          final localMessages = <String>[];
          final local = ChangeRefsToLocal(ggLog: localMessages.add);
          await local.get(directory: dProject1, ggLog: localMessages.add);

          final overrides = File(p.join(dProject1.path, 'pnpm-workspace.yaml'))
              .readAsStringSync();

          expect(overrides, contains('# Local experiment - keep me'));
          expect(overrides, contains('allowBuilds'));
          expect(
            overrides,
            contains('some_third_party: link:../../vendor/some_third_party'),
          );
          expect(overrides, contains('test2_ts: link:../project2'));
        });
      });
    });
  });
}
