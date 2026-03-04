// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/multi_language_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('MultiLanguageGraph', () {
    late List<Directory> tempDirs;

    setUp(() {
      tempDirs = <Directory>[];
    });

    tearDown(() {
      deleteDirs(tempDirs);
    });

    Directory createWorkspace(String suffix) {
      final dir = createTempDir(suffix, 'workspace');
      tempDirs.add(dir);
      return dir;
    }

    test('throws when no project root was found', () async {
      final workspace = createWorkspace('mlg_no_root');

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[
          DartProjectLanguage(),
          TypeScriptProjectLanguage(),
        ],
      );

      await expectLater(
        graph.buildGraph(directory: workspace),
        throwsA(
          isA<Exception>().having(
            (Object e) => e.toString(),
            'message',
            contains('No project root found'),
          ),
        ),
      );
    });

    test('builds dependency graph for a Dart workspace', () async {
      final workspace = createWorkspace('mlg_dart_ws');
      final source = Directory(
        p.join('test', 'sample_folder', 'process_dependencies', 'succeed'),
      );
      copyDirectory(source, workspace);

      final project1 = Directory(p.join(workspace.path, 'project1'));

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[DartProjectLanguage()],
      );

      final result = await graph.buildGraph(directory: project1);
      final root = result.rootNode;
      final all = result.allNodes;

      expect(root.name, 'test1');
      expect(root.directory.path, project1.path);
      expect(all.keys, containsAll(<String>['test1', 'test2']));

      final node1 = all['test1']!;
      final node2 = all['test2']!;

      expect(node1.dependencies['test2'], same(node2));
      expect(node2.dependents['test1'], same(node1));
    });

    test('builds dependency graph for a TypeScript workspace', () async {
      final workspace = createWorkspace('mlg_ts_ws');
      final source = Directory(
        p.join('test', 'sample_folder_ts', 'localize_refs', 'succeed'),
      );
      copyDirectory(source, workspace);

      final project1 = Directory(p.join(workspace.path, 'project1'));

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[TypeScriptProjectLanguage()],
      );

      final result = await graph.buildGraph(directory: project1);
      final root = result.rootNode;
      final all = result.allNodes;

      expect(root.name, 'test1_ts');
      expect(root.directory.path, project1.path);
      expect(all.keys, containsAll(<String>['test1_ts', 'test2_ts']));

      final node1 = all['test1_ts']!;
      final node2 = all['test2_ts']!;

      expect(node1.dependencies['test2_ts'], same(node2));
      expect(node2.dependents['test1_ts'], same(node1));
    });

    test('throws when circular dependencies are detected', () async {
      final workspace = createWorkspace('mlg_circular');
      final p1 = Directory(p.join(workspace.path, 'p1'));
      final p2 = Directory(p.join(workspace.path, 'p2'));
      createDirs(<Directory>[p1, p2]);

      File(p.join(p1.path, 'pubspec.yaml')).writeAsStringSync(
        'name: p1\n'
        'version: 1.0.0\n'
        'dependencies:\n'
        '  p2: ^1.0.0\n',
      );
      File(p.join(p2.path, 'pubspec.yaml')).writeAsStringSync(
        'name: p2\n'
        'version: 1.0.0\n'
        'dependencies:\n'
        '  p1: ^1.0.0\n',
      );

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[DartProjectLanguage()],
      );

      await expectLater(
        graph.buildGraph(directory: p1),
        throwsA(
          isA<Exception>().having(
            (Object e) => e.toString(),
            'message',
            allOf(
              contains('Please remove circular dependency'),
              contains('p1 -> p2 -> p1'),
            ),
          ),
        ),
      );
    });

    test('throws when duplicate package names exist in workspace', () async {
      final workspace = createWorkspace('mlg_duplicate');
      final p1 = Directory(p.join(workspace.path, 'pkg1'));
      final p2 = Directory(p.join(workspace.path, 'pkg2'));
      createDirs(<Directory>[p1, p2]);

      File(
        p.join(p1.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: shared\nversion: 1.0.0\n');
      File(
        p.join(p2.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: shared\nversion: 2.0.0\n');

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[DartProjectLanguage()],
      );

      await expectLater(
        graph.buildGraph(directory: p1),
        throwsA(
          isA<Exception>().having(
            (Object e) => e.toString(),
            'message',
            contains('Duplicate package name: shared'),
          ),
        ),
      );
    });
  });
}
