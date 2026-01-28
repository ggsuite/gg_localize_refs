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
import 'package:path/path.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('MultiLanguageGraph', () {
    group('buildGraph', () {
      test('throws when a circular dependency exists in the workspace', () async {
        final workspace = createTempDir('mlg_circular_ws');
        final projectA = Directory(join(workspace.path, 'a'));
        final projectB = Directory(join(workspace.path, 'b'));
        createDirs(<Directory>[projectA, projectB]);

        File(join(projectA.path, 'pubspec.yaml')).writeAsStringSync(
          'name: a\n'
          'version: 1.0.0\n'
          'dependencies:\n'
          '  b: ^1.0.0\n',
        );
        File(join(projectB.path, 'pubspec.yaml')).writeAsStringSync(
          'name: b\n'
          'version: 1.0.0\n'
          'dependencies:\n'
          '  a: ^1.0.0\n',
        );

        final graph = MultiLanguageGraph(
          languages: <ProjectLanguage>[
            DartProjectLanguage(),
            TypeScriptProjectLanguage(),
          ],
        );

        await expectLater(
          graph.buildGraph(directory: projectA),
          throwsA(
            isA<Exception>()
                .having(
                  (Object e) => e.toString(),
                  'message',
                  contains('circular dependency'),
                )
                .having(
                  (Object e) => e.toString(),
                  'message',
                  contains('a -> b -> a'),
                ),
          ),
        );

        deleteDirs(<Directory>[workspace]);
      });

      test('throws when duplicate package names are found in the workspace', () async {
        final workspace = createTempDir('mlg_duplicate_ws');
        final project1 = Directory(join(workspace.path, 'p1'));
        final project2 = Directory(join(workspace.path, 'p2'));
        createDirs(<Directory>[project1, project2]);

        File(join(project1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: dup\nversion: 1.0.0\n',
        );
        File(join(project2.path, 'pubspec.yaml')).writeAsStringSync(
          'name: dup\nversion: 1.0.0\n',
        );

        final graph = MultiLanguageGraph(
          languages: <ProjectLanguage>[
            DartProjectLanguage(),
            TypeScriptProjectLanguage(),
          ],
        );

        await expectLater(
          graph.buildGraph(directory: project1),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('Duplicate package name: dup'),
            ),
          ),
        );

        deleteDirs(<Directory>[workspace]);
      });
    });
  });
}
