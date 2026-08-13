// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/manifest_command_support.dart';
import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
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
        expect(gitignore.readAsStringSync(), '.gg/*\n!.gg/gg.json\n');
      });

      test('appends missing entries to existing .gitignore', () {
        final workspace = createWorkspace('manifest_support_gitignore_append');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync('build/\n');

        support.ensureGitignoreHasDartBackupEntries(projectDir);

        expect(gitignore.readAsStringSync(), 'build/\n.gg/*\n!.gg/gg.json\n');
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
          gitignore.writeAsStringSync('build/\r\n.gg/*\r\n!.gg/gg.json\r\n');

          support.ensureGitignoreHasDartBackupEntries(projectDir);

          expect(gitignore.readAsStringSync(), 'build/\n.gg/*\n!.gg/gg.json\n');
        },
      );

      test('replaces a stale bare .gg where it stands, keeping re-includes '
          'below it effective', () {
        final workspace = createWorkspace('manifest_support_gitignore_stale');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync('.gg\n!.gg/gg.json\n!.gg/.ticket.json\n');

        support.ensureGitignoreHasDartBackupEntries(projectDir);

        expect(
          gitignore.readAsStringSync(),
          '.gg/*\n!.gg/gg.json\n!.gg/.ticket.json\n',
        );
      });

      test('replaces the stale !.gg/.gg.json re-include where it stands', () {
        final workspace = createWorkspace('manifest_support_gitignore_hidden');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync('.gg/*\n!.gg/.gg.json\nbuild/\n');

        support.ensureGitignoreHasDartBackupEntries(projectDir);

        expect(gitignore.readAsStringSync(), '.gg/*\n!.gg/gg.json\nbuild/\n');
      });

      test('drops the stale !.gg/.gg.json when the new entry is present', () {
        final workspace = createWorkspace('manifest_support_gitignore_dup');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync('.gg/*\n!.gg/gg.json\n!.gg/.gg.json\n');

        support.ensureGitignoreHasDartBackupEntries(projectDir);

        expect(gitignore.readAsStringSync(), '.gg/*\n!.gg/gg.json\n');
      });

      test('drops a stale bare .gg when .gg/* is already present', () {
        // The replacement must not be inserted twice - a second `.gg/*` after
        // the `!` re-includes would silence them again.
        final workspace = createWorkspace('manifest_support_gitignore_both');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync(
          '.gg/*\n!.gg/gg.json\n!.gg/.ticket.json\n.gg\n',
        );

        support.ensureGitignoreHasDartBackupEntries(projectDir);

        expect(
          gitignore.readAsStringSync(),
          '.gg/*\n!.gg/gg.json\n!.gg/.ticket.json\n',
        );
      });
    });

    group('ensureGitignoreAllowsPubspecOverrides()', () {
      test('does not create a .gitignore when there is none', () {
        final workspace = createWorkspace('manifest_support_overrides_none');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        support.ensureGitignoreAllowsPubspecOverrides(projectDir);

        expect(
          File(p.join(projectDir.path, '.gitignore')).existsSync(),
          isFalse,
        );
      });

      test('removes an anchored entry an earlier version wrote', () {
        final workspace = createWorkspace('manifest_support_overrides_drop');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync('build/\n/pubspec_overrides.yaml\n');

        support.ensureGitignoreAllowsPubspecOverrides(projectDir);

        expect(gitignore.readAsStringSync(), 'build/\n');
      });

      test('removes the unanchored entry other repos carry by hand', () {
        final workspace = createWorkspace('manifest_support_overrides_bare');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync('pubspec_overrides.yaml\r\nbuild/\r\n');

        support.ensureGitignoreAllowsPubspecOverrides(projectDir);

        expect(gitignore.readAsStringSync(), 'build/\n');
      });

      test('leaves a .gitignore without the entry untouched', () {
        final workspace = createWorkspace('manifest_support_overrides_keep');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync('build/\n.gg/*\n!.gg/gg.json\n');
        final before = gitignore.lastModifiedSync();

        support.ensureGitignoreAllowsPubspecOverrides(projectDir);

        expect(gitignore.readAsStringSync(), 'build/\n.gg/*\n!.gg/gg.json\n');
        expect(gitignore.lastModifiedSync(), before);
      });

      test('empties a .gitignore that held nothing else', () {
        final workspace = createWorkspace('manifest_support_overrides_only');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final gitignore = File(p.join(projectDir.path, '.gitignore'));
        gitignore.writeAsStringSync('/pubspec_overrides.yaml\n');

        support.ensureGitignoreAllowsPubspecOverrides(projectDir);

        expect(gitignore.readAsStringSync(), isEmpty);
      });
    });

    group('bufferPubspecOverridesEdit()', () {
      test('queues a write edit as a content change', () {
        final workspace = createWorkspace('manifest_support_overrides_write');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        final buffer = FileChangesBuffer();
        support.bufferPubspecOverridesEdit(
          projectDir: projectDir,
          edit: const PubspecOverridesEdit.write('dependency_overrides:\n'),
          fileChangesBuffer: buffer,
        );

        expect(buffer.deletions, isEmpty);
        expect(buffer.files, hasLength(1));
        expect(
          buffer.files.single.file.path,
          p.join(projectDir.path, 'pubspec_overrides.yaml'),
        );
        expect(buffer.files.single.content, 'dependency_overrides:\n');
      });

      test('queues nothing for an unchanged edit', () {
        final workspace = createWorkspace('manifest_support_overrides_noop');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        final buffer = FileChangesBuffer();
        support.bufferPubspecOverridesEdit(
          projectDir: projectDir,
          edit: const PubspecOverridesEdit.unchanged(),
          fileChangesBuffer: buffer,
        );

        expect(buffer.isEmpty, isTrue);
      });
    });

    group('bufferPnpmWorkspaceEdit()', () {
      test('queues a write edit as a content change', () {
        final workspace = createWorkspace('manifest_support_pnpm_write');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        final buffer = FileChangesBuffer();
        support.bufferPnpmWorkspaceEdit(
          projectDir: projectDir,
          edit: const PubspecOverridesEdit.write('overrides:\n'),
          fileChangesBuffer: buffer,
        );

        expect(buffer.deletions, isEmpty);
        expect(buffer.files, hasLength(1));
        expect(
          buffer.files.single.file.path,
          p.join(projectDir.path, 'pnpm-workspace.yaml'),
        );
        expect(buffer.files.single.content, 'overrides:\n');
      });

      test('queues a delete edit as a deletion', () {
        final workspace = createWorkspace('manifest_support_pnpm_delete');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        final buffer = FileChangesBuffer();
        support.bufferPnpmWorkspaceEdit(
          projectDir: projectDir,
          edit: const PubspecOverridesEdit.delete(),
          fileChangesBuffer: buffer,
        );

        expect(buffer.files, isEmpty);
        expect(buffer.deletions, hasLength(1));
        expect(
          buffer.deletions.single.path,
          p.join(projectDir.path, 'pnpm-workspace.yaml'),
        );
      });

      test('queues nothing for an unchanged edit', () {
        final workspace = createWorkspace('manifest_support_pnpm_noop');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        final buffer = FileChangesBuffer();
        support.bufferPnpmWorkspaceEdit(
          projectDir: projectDir,
          edit: const PubspecOverridesEdit.unchanged(),
          fileChangesBuffer: buffer,
        );

        expect(buffer.isEmpty, isTrue);
      });
    });

    group('bufferPubspecOverridesRemoval()', () {
      test('queues the deletion for a dependency of the node', () {
        final workspace = createWorkspace('manifest_support_remove_overrides');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);
        final dependencyDir = Directory(p.join(workspace.path, 'dep'))
          ..createSync(recursive: true);

        File(
          p.join(projectDir.path, 'pubspec_overrides.yaml'),
        ).writeAsStringSync(
          'dependency_overrides:\n'
          '  dep:\n'
          '    path: ../dep\n',
        );

        final language = DartProjectLanguage();
        final node = createNode(
          name: 'project',
          directory: projectDir,
          language: language,
          dependencies: <String, ProjectNode>{
            'dep': createNode(
              name: 'dep',
              directory: dependencyDir,
              language: language,
            ),
          },
        );

        final buffer = FileChangesBuffer();
        support.bufferPubspecOverridesRemoval(
          node: node,
          fileChangesBuffer: buffer,
        );

        expect(buffer.files, isEmpty);
        expect(buffer.deletions, hasLength(1));
        expect(
          buffer.deletions.single.path,
          p.join(projectDir.path, 'pubspec_overrides.yaml'),
        );
      });

      test('queues nothing when there is no overrides file', () {
        final workspace = createWorkspace('manifest_support_remove_none');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        final buffer = FileChangesBuffer();
        support.bufferPubspecOverridesRemoval(
          node: createNode(
            name: 'project',
            directory: projectDir,
            language: DartProjectLanguage(),
          ),
          fileChangesBuffer: buffer,
        );

        expect(buffer.isEmpty, isTrue);
      });
    });

    group('writeTypeScriptBackup()', () {
      test('writes backup file into the .gg directory', () async {
        final workspace = createWorkspace('manifest_support_ts_backup');
        final projectDir = Directory(p.join(workspace.path, 'project'))
          ..createSync(recursive: true);

        await support.writeTypeScriptBackup(projectDir, <String, dynamic>{
          'dep': '^1.2.3',
        });

        final file = File(
          p.join(projectDir.path, '.gg', 'gg_localize_refs_backup_ts.json'),
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

    group('dependencyOverridesOf()', () {
      test('returns the dependency_overrides of the manifest', () {
        final result = support.dependencyOverridesOf(<dynamic, dynamic>{
          'dependency_overrides': <dynamic, dynamic>{'dep': '^1.0.0'},
        });

        expect(result, <String, dynamic>{'dep': '^1.0.0'});
      });

      test('returns an empty map when the manifest is no map', () {
        expect(support.dependencyOverridesOf('not a map'), isEmpty);
      });

      test('returns an empty map when there is no section', () {
        expect(
          support.dependencyOverridesOf(<dynamic, dynamic>{'name': 'pkg'}),
          isEmpty,
        );
      });
    });
  });
}
