// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('Utils', () {
    late List<Directory> tempDirs;

    setUp(() {
      tempDirs = <Directory>[];
    });

    tearDown(() {
      deleteDirs(tempDirs);
    });

    Directory createWorkspace(String suffix) {
      final directory = createTempDir(suffix, 'workspace');
      tempDirs.add(directory);
      return directory;
    }

    group('findLanguage()', () {
      test('returns DartProjectLanguage when pubspec.yaml exists', () {
        final workspace = createWorkspace('utils_find_language_dart');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);
        File(
          p.join(project.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test_pkg\nversion: 1.0.0\n');

        final language = Utils.findLanguage(project);

        expect(language, isA<DartProjectLanguage>());
        expect(language.id, ProjectLanguageId.dart);
      });

      test('returns TypeScriptProjectLanguage when package.json exists', () {
        final workspace = createWorkspace('utils_find_language_ts');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);
        File(
          p.join(project.path, 'package.json'),
        ).writeAsStringSync('{"name":"test_pkg","version":"1.0.0"}');

        final language = Utils.findLanguage(project);

        expect(language, isA<TypeScriptProjectLanguage>());
        expect(language.id, ProjectLanguageId.typescript);
      });

      test('prefers pubspec.yaml when both manifest files exist', () {
        final workspace = createWorkspace('utils_find_language_both');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);
        File(
          p.join(project.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test_pkg\nversion: 1.0.0\n');
        File(
          p.join(project.path, 'package.json'),
        ).writeAsStringSync('{"name":"test_pkg","version":"1.0.0"}');

        final language = Utils.findLanguage(project);

        expect(language, isA<DartProjectLanguage>());
      });

      test('throws when no supported manifest file exists', () {
        final workspace = createWorkspace('utils_find_language_missing');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);

        expect(
          () => Utils.findLanguage(project),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('pubspec.yaml not found'),
            ),
          ),
        );
      });
    });

    group('backup path helpers', () {
      test('typeScriptBackupFile returns the _ts backup json in .gg', () {
        final workspace = createWorkspace('utils_ts_backup_file');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);

        final file = Utils.typeScriptBackupFile(project);

        expect(
          file.path,
          p.join(project.path, '.gg', 'gg_localize_refs_backup_ts.json'),
        );
      });

      test('typeScriptBackupFile moves the legacy root backup into .gg', () {
        final workspace = createWorkspace('utils_ts_backup_migrate');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);
        final legacy = File(
          p.join(project.path, '.gg_localize_refs_backup.json'),
        )..writeAsStringSync('{"a": "^1.0.0"}');

        final file = Utils.typeScriptBackupFile(project);

        expect(legacy.existsSync(), isFalse);
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), '{"a": "^1.0.0"}');
      });

      test('dartBackupDir returns .gg directory in project root', () {
        final workspace = createWorkspace('utils_dart_backup_dir');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);

        final directory = Utils.dartBackupDir(project);

        expect(directory.path, p.join(project.path, '.gg'));
      });

      test('dartBackupFile returns the _dart backup json in .gg', () {
        final workspace = createWorkspace('utils_dart_backup_file');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);

        final file = Utils.dartBackupFile(project);

        expect(
          file.path,
          p.join(project.path, '.gg', 'gg_localize_refs_backup_dart.json'),
        );
      });

      test(
        'dartPublishToBackupFile returns backup json inside .gg directory',
        () {
          final workspace = createWorkspace('utils_dart_publish_to_file');
          final project = Directory(p.join(workspace.path, 'project'));
          project.createSync(recursive: true);

          final file = Utils.dartPublishToBackupFile(project);

          expect(
            file.path,
            p.join(
              project.path,
              '.gg',
              'gg_localize_refs_publish_to_backup.json',
            ),
          );
        },
      );

      test('renames the hidden backup files an earlier version wrote', () {
        final workspace = createWorkspace('utils_dart_backup_legacy');
        final project = Directory(p.join(workspace.path, 'project'));
        final backupDir = Directory(p.join(project.path, '.gg'))
          ..createSync(recursive: true);
        File(
          p.join(backupDir.path, '.gg_localize_refs_backup.json'),
        ).writeAsStringSync('{"a":"^1.0.0"}');
        File(
          p.join(backupDir.path, '.gg_localize_refs_publish_to_backup.json'),
        ).writeAsStringSync('{"publish_to":"none"}');

        expect(
          Utils.dartBackupFile(project).readAsStringSync(),
          '{"a":"^1.0.0"}',
        );
        expect(
          Utils.dartPublishToBackupFile(project).readAsStringSync(),
          '{"publish_to":"none"}',
        );

        expect(
          backupDir.listSync().map((e) => p.basename(e.path)).toSet(),
          <String>{
            'gg_localize_refs_backup_dart.json',
            'gg_localize_refs_publish_to_backup.json',
          },
        );
      });

      test('prefers the newer legacy name when both legacies exist', () {
        // Two renames happened: hidden -> unhidden, then unhidden -> _dart.
        // A checkout that stopped at the middle step carries both, and the
        // newer one is the backup that was actually in use.
        final workspace = createWorkspace('utils_dart_backup_both');
        final project = Directory(p.join(workspace.path, 'project'));
        final backupDir = Directory(p.join(project.path, '.gg'))
          ..createSync(recursive: true);
        File(
          p.join(backupDir.path, '.gg_localize_refs_backup.json'),
        ).writeAsStringSync('{"oldest":true}');
        File(
          p.join(backupDir.path, 'gg_localize_refs_backup.json'),
        ).writeAsStringSync('{"newer":true}');

        expect(
          Utils.dartBackupFile(project).readAsStringSync(),
          '{"newer":true}',
        );
        expect(
          File(
            p.join(backupDir.path, '.gg_localize_refs_backup.json'),
          ).existsSync(),
          isTrue,
        );
      });

      test('keeps the current backup file when a legacy one also exists', () {
        // Only a leftover may be renamed - never a backup that is in use.
        final workspace = createWorkspace('utils_dart_backup_current');
        final project = Directory(p.join(workspace.path, 'project'));
        final backupDir = Directory(p.join(project.path, '.gg'))
          ..createSync(recursive: true);
        File(
          p.join(backupDir.path, 'gg_localize_refs_backup.json'),
        ).writeAsStringSync('{"legacy":true}');
        File(
          p.join(backupDir.path, 'gg_localize_refs_backup_dart.json'),
        ).writeAsStringSync('{"current":true}');

        expect(
          Utils.dartBackupFile(project).readAsStringSync(),
          '{"current":true}',
        );
        expect(
          File(
            p.join(backupDir.path, 'gg_localize_refs_backup.json'),
          ).existsSync(),
          isTrue,
        );
      });
    });

    group('readDependenciesFromJson()', () {
      test('reads and returns dependencies from json file', () {
        final workspace = createWorkspace('utils_read_json_success');
        final file = File(p.join(workspace.path, 'deps.json'));
        file.writeAsStringSync('{"a":"^1.0.0","b":{"version":"^2.0.0"}}');

        final result = Utils.readDependenciesFromJson(file.path);

        expect(result['a'], '^1.0.0');
        expect(result['b'], isA<Map<String, dynamic>>());
        expect((result['b'] as Map<String, dynamic>)['version'], '^2.0.0');
      });

      test('throws when json file does not exist', () {
        final workspace = createWorkspace('utils_read_json_missing');
        final filePath = p.join(workspace.path, 'missing.json');

        expect(
          () => Utils.readDependenciesFromJson(filePath),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains(
                'The json file $filePath with old dependencies does not exist.',
              ),
            ),
          ),
        );
      });
    });

    group('getGitRemoteUrl()', () {
      test('returns origin url for git repository', () async {
        final workspace = createWorkspace('utils_git_remote_success');
        final project = Directory(p.join(workspace.path, 'project'));
        await createDirs(<Directory>[project]);

        Process.runSync('git', <String>[
          'remote',
          'remove',
          'origin',
        ], workingDirectory: project.path);
        Process.runSync('git', <String>[
          'remote',
          'add',
          'origin',
          'git@github.com:user/test_repo.git',
        ], workingDirectory: project.path);

        final remoteUrl = await Utils.getGitRemoteUrl(project, 'test_repo');

        expect(remoteUrl, 'git@github.com:user/test_repo.git');
      });

      test('throws when origin remote is missing', () async {
        final workspace = createWorkspace('utils_git_remote_missing');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);
        Process.runSync('git', <String>[
          'init',
        ], workingDirectory: project.path);

        await expectLater(
          Utils.getGitRemoteUrl(project, 'missing_dep'),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('Cannot get git remote url for dependency missing_dep'),
            ),
          ),
        );
      });
    });
  });
}
