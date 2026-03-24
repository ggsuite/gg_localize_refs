// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
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
      test('typeScriptBackupFile returns backup file in project root', () {
        final workspace = createWorkspace('utils_ts_backup_file');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);

        final file = Utils.typeScriptBackupFile(project);

        expect(
          file.path,
          p.join(project.path, '.gg_localize_refs_backup.json'),
        );
      });

      test('dartBackupDir returns .gg directory in project root', () {
        final workspace = createWorkspace('utils_dart_backup_dir');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);

        final directory = Utils.dartBackupDir(project);

        expect(directory.path, p.join(project.path, '.gg'));
      });

      test('dartBackupFile returns backup json inside .gg directory', () {
        final workspace = createWorkspace('utils_dart_backup_file');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);

        final file = Utils.dartBackupFile(project);

        expect(
          file.path,
          p.join(project.path, '.gg', '.gg_localize_refs_backup.json'),
        );
      });

      test('dartBackupYamlFile returns backup yaml inside .gg directory', () {
        final workspace = createWorkspace('utils_dart_backup_yaml_file');
        final project = Directory(p.join(workspace.path, 'project'));
        project.createSync(recursive: true);

        final file = Utils.dartBackupYamlFile(project);

        expect(
          file.path,
          p.join(project.path, '.gg', '.gg_localize_refs_backup.yaml'),
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
