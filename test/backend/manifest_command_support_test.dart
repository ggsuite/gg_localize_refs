// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/manifest_command_support.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../test_helpers.dart';

void main() {
  group('ManifestCommandSupport', () {
    const support = ManifestCommandSupport();
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

    ProjectNode createNode({
      required String name,
      required Directory directory,
      required ProjectLanguage language,
      Map<String, ProjectNode>? dependencies,
    }) {
      final node = ProjectNode(
        name: name,
        directory: directory,
        language: language,
      );
      if (dependencies != null) {
        node.dependencies.addAll(dependencies);
      }
      return node;
    }

    group('ensureDartBackupDir()', () {
      test('creates the .gg backup directory when missing', () {
        final workspace = createWorkspace('manifest_support_backup_dir');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        final backupDir = support.ensureDartBackupDir(projectDir);

        expect(backupDir.existsSync(), isTrue);
        expect(backupDir.path, p.join(projectDir.path, '.gg'));
      });

      test('returns existing .gg backup directory unchanged', () {
        final workspace = createWorkspace(
          'manifest_support_existing_backup_dir',
        );
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final existing = Directory(p.join(projectDir.path, '.gg'))
          ..createSync(recursive: true);

        final backupDir = support.ensureDartBackupDir(projectDir);

        expect(backupDir.existsSync(), isTrue);
        expect(backupDir.path, existing.path);
      });
    });

    group('ensureGitignoreHasDartBackupEntries()', () {
      test('creates .gitignore with required entries when missing', () {
        final workspace = createWorkspace('manifest_support_gitignore_create');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        support.ensureGitignoreHasDartBackupEntries(projectDir);

        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        expect(gitignore.existsSync(), isTrue);
        expect(gitignore.readAsStringSync(), '.gg\n!.gg/.gg.json\n');
      });

      test('appends missing entries to existing .gitignore', () {
        final workspace = createWorkspace('manifest_support_gitignore_append');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync('build/\n');

        support.ensureGitignoreHasDartBackupEntries(projectDir);

        expect(gitignore.readAsStringSync(), 'build/\n.gg\n!.gg/.gg.json\n');
      });

      test(
        'does not duplicate existing entries and normalizes line endings',
        () {
          final workspace = createWorkspace(
            'manifest_support_gitignore_dedupe',
          );
          final projectDir = Directory(p.join(workspace.path, 'project'))
            ..createSync(recursive: true);
          final gitignore = File(p.join(projectDir.path, '.gitignore'));
          gitignore.writeAsStringSync('build/\r\n.gg\r\n!.gg/.gg.json\r\n');

          support.ensureGitignoreHasDartBackupEntries(projectDir);

          expect(gitignore.readAsStringSync(), 'build/\n.gg\n!.gg/.gg.json\n');
        },
      );
    });

    group('writeFileCopy()', () {
      test('copies file content to destination', () async {
        final workspace = createWorkspace('manifest_support_write_copy');
        final source = File(p.join(workspace.path, 'source.txt'));
        final destination = File(p.join(workspace.path, 'copy.txt'));
        source.writeAsStringSync('copied content');

        await support.writeFileCopy(source: source, destination: destination);

        expect(destination.existsSync(), isTrue);
        expect(destination.readAsStringSync(), 'copied content');
      });
    });

    group('saveDependenciesAsJson()', () {
      test('writes dependencies as json', () async {
        final workspace = createWorkspace('manifest_support_save_json');
        final filePath = p.join(workspace.path, 'deps.json');

        await support.saveDependenciesAsJson(<String, dynamic>{
          'a': '^1.0.0',
          'b': '^2.0.0',
        }, filePath);

        final file = File(filePath);
        expect(file.existsSync(), isTrue);
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(data['a'], '^1.0.0');
        expect(data['b'], '^2.0.0');
      });
    });

    group('writeTypeScriptBackup()', () {
      test('writes backup file into project root', () async {
        final workspace = createWorkspace('manifest_support_ts_backup');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        await support.writeTypeScriptBackup(projectDir, <String, dynamic>{
          'dep': '^1.2.3',
        });

        final file = File(
          p.join(projectDir.path, '.gg_localize_refs_backup.json'),
        );
        expect(file.existsSync(), isTrue);
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(data['dep'], '^1.2.3');
      });
    });

    group('referencesFor()', () {
      test('returns references for Dart dependency sections', () {
        final workspace = createWorkspace('manifest_support_refs_dart');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: DartProjectLanguage(),
        );
        final manifest = loadYaml(
          'dependencies:\n'
          '  a: ^1.0.0\n'
          'dev_dependencies:\n'
          '  b: ^2.0.0\n',
        );

        final references = support.referencesFor(node, manifest);

        expect(references.keys, containsAll(<String>['a', 'b']));
        expect(references['a']!.sectionName, 'dependencies');
        expect(references['b']!.sectionName, 'dev_dependencies');
      });

      test('returns references for TypeScript dependency sections', () {
        final workspace = createWorkspace('manifest_support_refs_ts');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: TypeScriptProjectLanguage(),
        );
        final manifest = <String, dynamic>{
          'dependencies': <String, dynamic>{'a': '^1.0.0'},
          'devDependencies': <String, dynamic>{'b': '^2.0.0'},
        };

        final references = support.referencesFor(node, manifest);

        expect(references.keys, containsAll(<String>['a', 'b']));
        expect(references['a']!.sectionName, 'dependencies');
        expect(references['b']!.sectionName, 'devDependencies');
      });
    });

    group('hasNonLocalDartDependencies()', () {
      test('returns false when all workspace dependencies are path refs', () {
        final workspace = createWorkspace('manifest_support_non_local_dart_no');
        final projectDir = Directory(p.join(workspace.path, 'project1'))
          ..createSync(recursive: true);
        final depDir = Directory(p.join(workspace.path, 'project2'))
          ..createSync(recursive: true);
        final depNode = createNode(
          name: 'dep',
          directory: depDir,
          language: DartProjectLanguage(),
        );
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: DartProjectLanguage(),
          dependencies: <String, ProjectNode>{'dep': depNode},
        );
        final references = <String, DependencyReference>{
          'dep': const DependencyReference(
            sectionName: 'dependencies',
            name: 'dep',
            value: <String, dynamic>{'path': '../project2'},
          ),
        };

        final result = support.hasNonLocalDartDependencies(
          node: node,
          references: references,
        );

        expect(result, isFalse);
      });

      test('returns true when a workspace dependency is a version ref', () {
        final workspace = createWorkspace(
          'manifest_support_non_local_dart_yes',
        );
        final projectDir = Directory(p.join(workspace.path, 'project1'))
          ..createSync(recursive: true);
        final depDir = Directory(p.join(workspace.path, 'project2'))
          ..createSync(recursive: true);
        final depNode = createNode(
          name: 'dep',
          directory: depDir,
          language: DartProjectLanguage(),
        );
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: DartProjectLanguage(),
          dependencies: <String, ProjectNode>{'dep': depNode},
        );
        final references = <String, DependencyReference>{
          'dep': const DependencyReference(
            sectionName: 'dependencies',
            name: 'dep',
            value: '^1.0.0',
          ),
        };

        final result = support.hasNonLocalDartDependencies(
          node: node,
          references: references,
        );

        expect(result, isTrue);
      });
    });

    group('hasNonLocalTypeScriptDependencies()', () {
      test('returns false when all workspace dependencies are file refs', () {
        final workspace = createWorkspace('manifest_support_non_local_ts_no');
        final projectDir = Directory(p.join(workspace.path, 'project1'))
          ..createSync(recursive: true);
        final depDir = Directory(p.join(workspace.path, 'project2'))
          ..createSync(recursive: true);
        final depNode = createNode(
          name: 'dep',
          directory: depDir,
          language: TypeScriptProjectLanguage(),
        );
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: TypeScriptProjectLanguage(),
          dependencies: <String, ProjectNode>{'dep': depNode},
        );
        final references = <String, DependencyReference>{
          'dep': const DependencyReference(
            sectionName: 'dependencies',
            name: 'dep',
            value: 'file:../project2',
          ),
        };

        final result = support.hasNonLocalTypeScriptDependencies(
          node: node,
          references: references,
        );

        expect(result, isFalse);
      });

      test('returns true when a workspace dependency is a version ref', () {
        final workspace = createWorkspace('manifest_support_non_local_ts_yes');
        final projectDir = Directory(p.join(workspace.path, 'project1'))
          ..createSync(recursive: true);
        final depDir = Directory(p.join(workspace.path, 'project2'))
          ..createSync(recursive: true);
        final depNode = createNode(
          name: 'dep',
          directory: depDir,
          language: TypeScriptProjectLanguage(),
        );
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: TypeScriptProjectLanguage(),
          dependencies: <String, ProjectNode>{'dep': depNode},
        );
        final references = <String, DependencyReference>{
          'dep': const DependencyReference(
            sectionName: 'dependencies',
            name: 'dep',
            value: '^1.0.0',
          ),
        };

        final result = support.hasNonLocalTypeScriptDependencies(
          node: node,
          references: references,
        );

        expect(result, isTrue);
      });
    });

    group('shouldBackupPublishTo()', () {
      test('returns true for pub.dev dependency versions', () {
        final workspace = createWorkspace(
          'manifest_support_backup_publish_yes',
        );
        final projectDir = Directory(p.join(workspace.path, 'project1'))
          ..createSync(recursive: true);
        final depDir = Directory(p.join(workspace.path, 'project2'))
          ..createSync(recursive: true);
        final depNode = createNode(
          name: 'dep',
          directory: depDir,
          language: DartProjectLanguage(),
        );
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: DartProjectLanguage(),
          dependencies: <String, ProjectNode>{'dep': depNode},
        );
        final references = <String, DependencyReference>{
          'dep': const DependencyReference(
            sectionName: 'dependencies',
            name: 'dep',
            value: '^1.0.0',
          ),
        };

        final result = support.shouldBackupPublishTo(
          node: node,
          references: references,
        );

        expect(result, isTrue);
      });

      test('returns true for git dependency refs with version', () {
        final workspace = createWorkspace(
          'manifest_support_backup_publish_tag',
        );
        final projectDir = Directory(p.join(workspace.path, 'project1'))
          ..createSync(recursive: true);
        final depDir = Directory(p.join(workspace.path, 'project2'))
          ..createSync(recursive: true);
        final depNode = createNode(
          name: 'dep',
          directory: depDir,
          language: DartProjectLanguage(),
        );
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: DartProjectLanguage(),
          dependencies: <String, ProjectNode>{'dep': depNode},
        );
        final references = <String, DependencyReference>{
          'dep': const DependencyReference(
            sectionName: 'dependencies',
            name: 'dep',
            value: <String, dynamic>{
              'git': 'git@github.com:user/dep.git',
              'version': '^2.0.0',
            },
          ),
        };

        final result = support.shouldBackupPublishTo(
          node: node,
          references: references,
        );

        expect(result, isTrue);
      });

      test('returns false for path dependency refs', () {
        final workspace = createWorkspace(
          'manifest_support_backup_publish_path_no',
        );
        final projectDir = Directory(p.join(workspace.path, 'project1'))
          ..createSync(recursive: true);
        final depDir = Directory(p.join(workspace.path, 'project2'))
          ..createSync(recursive: true);
        final depNode = createNode(
          name: 'dep',
          directory: depDir,
          language: DartProjectLanguage(),
        );
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: DartProjectLanguage(),
          dependencies: <String, ProjectNode>{'dep': depNode},
        );
        final references = <String, DependencyReference>{
          'dep': const DependencyReference(
            sectionName: 'dependencies',
            name: 'dep',
            value: <String, dynamic>{'path': '../project2'},
          ),
        };

        final result = support.shouldBackupPublishTo(
          node: node,
          references: references,
        );

        expect(result, isFalse);
      });

      test('returns false for plain git refs without version', () {
        final workspace = createWorkspace(
          'manifest_support_backup_publish_git',
        );
        final projectDir = Directory(p.join(workspace.path, 'project1'))
          ..createSync(recursive: true);
        final depDir = Directory(p.join(workspace.path, 'project2'))
          ..createSync(recursive: true);
        final depNode = createNode(
          name: 'dep',
          directory: depDir,
          language: DartProjectLanguage(),
        );
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: DartProjectLanguage(),
          dependencies: <String, ProjectNode>{'dep': depNode},
        );
        final references = <String, DependencyReference>{
          'dep': const DependencyReference(
            sectionName: 'dependencies',
            name: 'dep',
            value: <String, dynamic>{
              'git': <String, dynamic>{
                'url': 'git@github.com:user/dep.git',
                'ref': 'main',
              },
            },
          ),
        };

        final result = support.shouldBackupPublishTo(
          node: node,
          references: references,
        );

        expect(result, isFalse);
      });
    });

    group('buildUpdatedDartBackupDependencies()', () {
      test(
        'keeps normalized existing backup entries and refreshes selected ones',
        () {
          final workspace = createWorkspace('manifest_support_build_backup');
          final projectDir = Directory(p.join(workspace.path, 'project1'))
            ..createSync(recursive: true);
          final depDir = Directory(p.join(workspace.path, 'project2'))
            ..createSync(recursive: true);
          final backupFile = File(
            p.join(projectDir.path, '.gg', '.gg_localize_refs_backup.json'),
          )..createSync(recursive: true);
          backupFile.writeAsStringSync(
            '{'
            '"keep_scalar":"^1.0.0",'
            '"keep_map":{"version":"^2.0.0"},'
            '"drop_path":"path: ../x", '
            '"publish_to_original":"none"'
            '}',
          );

          final depNode = createNode(
            name: 'dep',
            directory: depDir,
            language: DartProjectLanguage(),
          );
          final node = createNode(
            name: 'pkg',
            directory: projectDir,
            language: DartProjectLanguage(),
            dependencies: <String, ProjectNode>{'dep': depNode},
          );
          final references = <String, DependencyReference>{
            'dep': const DependencyReference(
              sectionName: 'dependencies',
              name: 'dep',
              value: <String, dynamic>{
                'git': 'git@github.com:user/dep.git',
                'version': '^3.0.0',
              },
            ),
          };

          final result = support.buildUpdatedDartBackupDependencies(
            node: node,
            references: references,
            shouldRefreshBackup: (String dependencyYaml) {
              return dependencyYaml.contains('version:');
            },
          );

          expect(result['keep_scalar'], '^1.0.0');
          expect(result['keep_map'], '^2.0.0');
          expect(result['dep'], '^3.0.0');
          expect(result.containsKey('drop_path'), isFalse);
          expect(result.containsKey('publish_to_original'), isFalse);
        },
      );

      test('does not refresh dependency when predicate returns false', () {
        final workspace = createWorkspace('manifest_support_build_backup_skip');
        final projectDir = Directory(p.join(workspace.path, 'project1'))
          ..createSync(recursive: true);
        final depDir = Directory(p.join(workspace.path, 'project2'))
          ..createSync(recursive: true);
        final depNode = createNode(
          name: 'dep',
          directory: depDir,
          language: DartProjectLanguage(),
        );
        final node = createNode(
          name: 'pkg',
          directory: projectDir,
          language: DartProjectLanguage(),
          dependencies: <String, ProjectNode>{'dep': depNode},
        );
        final references = <String, DependencyReference>{
          'dep': const DependencyReference(
            sectionName: 'dependencies',
            name: 'dep',
            value: '^4.0.0',
          ),
        };

        final result = support.buildUpdatedDartBackupDependencies(
          node: node,
          references: references,
          shouldRefreshBackup: (_) => false,
        );

        expect(result.containsKey('dep'), isFalse);
      });
    });

    group('normalizeBackupVersionValue()', () {
      test('returns trimmed string for plain version values', () {
        expect(support.normalizeBackupVersionValue('  ^1.0.0  '), '^1.0.0');
      });

      test('returns null for empty string values', () {
        expect(support.normalizeBackupVersionValue('   '), isNull);
      });

      test('returns null for path string values', () {
        expect(
          support.normalizeBackupVersionValue('path: ../project2'),
          isNull,
        );
      });

      test('returns null for git string values', () {
        expect(
          support.normalizeBackupVersionValue('git:\n  url: repo'),
          isNull,
        );
      });

      test('returns version from top-level map', () {
        final value = support.normalizeBackupVersionValue(<String, dynamic>{
          'version': '^2.0.0',
        });

        expect(value, '^2.0.0');
      });

      test('returns version from nested git map', () {
        final value = support.normalizeBackupVersionValue(<String, dynamic>{
          'git': <String, dynamic>{'version': '^3.0.0'},
        });

        expect(value, '^3.0.0');
      });

      test('returns null for unsupported map values', () {
        final value = support.normalizeBackupVersionValue(<String, dynamic>{
          'git': <String, dynamic>{'url': 'git@github.com:user/repo.git'},
        });

        expect(value, isNull);
      });
    });
  });
}
