import 'dart:io';

import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/multi_language_graph.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  Directory dWorkspaceSucceed = Directory('');

  setUp(() async {
    dWorkspaceSucceed = createTempDir('pd_succeed');
    final source = Directory(
      join('test', 'sample_folder', 'process_dependencies', 'succeed'),
    );
    copyDirectory(source, dWorkspaceSucceed);
  });

  tearDown(() {
    deleteDirs(<Directory>[dWorkspaceSucceed]);
  });

  group('Process dependencies', () {
    group('processProject()', () {
      group('should throw', () {
        test('when project root was not found', () async {
          final dNoProjectRootError = Directory(
            join(dWorkspaceSucceed.path, 'no_project_root_error'),
          );

          createDirs(<Directory>[dNoProjectRootError]);

          final messages = <String>[];

          await expectLater(
            processProject(
              directory: dNoProjectRootError,
              modifyFunction:
                  (
                    ProjectNode node,
                    File manifestFile,
                    String manifestContent,
                    dynamic manifestMap,
                    FileChangesBuffer fileChangesBuffer,
                  ) async {},
              fileChangesBuffer: FileChangesBuffer(),
              ggLog: messages.add,
            ),
            throwsA(
              isA<Exception>().having(
                (Object e) => e.toString(),
                'message',
                contains('No project root found'),
              ),
            ),
          );
        });

        test('when node not found', () async {
          final dNodeNotFound = Directory(
            join(dWorkspaceSucceed.path, 'node_not_found'),
          );

          createDirs(<Directory>[dNodeNotFound]);

          File(join(dNodeNotFound.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test_package\nversion: 1.0.0\ndependencies:',
          );

          final language = DartProjectLanguage();
          final node = await language.createNode(dNodeNotFound);

          await expectLater(
            processNode(
              node,
              <String, ProjectNode>{},
              <String>{},
              (
                ProjectNode node,
                File manifestFile,
                String manifestContent,
                dynamic manifestMap,
                FileChangesBuffer fileChangesBuffer,
              ) async {},
              FileChangesBuffer(),
            ),
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

      test('succeeds', () async {
        final dProject1 = Directory(join(dWorkspaceSucceed.path, 'project1'));

        final messages = <String>[];

        await processProject(
          directory: dProject1,
          modifyFunction:
              (
                ProjectNode node,
                File manifestFile,
                String manifestContent,
                dynamic manifestMap,
                FileChangesBuffer fileChangesBuffer,
              ) async {
                expect(node.name, 'test1');
                expect(manifestFile.path, endsWith('pubspec.yaml'));
                expect(
                  manifestContent,
                  'name: test1\nversion: 1.0.0\n'
                  'dependencies:\n  test2: ^1.0.0',
                );
                expect(manifestMap, <dynamic, dynamic>{
                  'name': 'test1',
                  'version': '1.0.0',
                  'dependencies': <dynamic, dynamic>{'test2': '^1.0.0'},
                });
              },
          fileChangesBuffer: FileChangesBuffer(),
          ggLog: messages.add,
        );
      });
    });

    group('Helper methods', () {
      group('correctDir()', () {
        test('succeeds', () {
          expect(correctDir(Directory('test/')).path, 'test');
          expect(correctDir(Directory('test/.')).path, 'test');
        });
      });

      group('getPackageName()', () {
        group('should throw', () {
          test('when pubspec.yaml cannot be parsed', () async {
            expect(
              () => getPackageName('invalid yaml'),
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
      });

      group('findNode()', () {
        test('returns null when nodes is empty', () {
          final result = findNode(
            packageName: 'x',
            nodes: <String, ProjectNode>{},
          );
          expect(result, isNull);
        });

        test('finds dependency via recursive search', () async {
          final ws = createTempDir('pd_findnode_ws');
          final p1 = Directory(join(ws.path, 'p1'));
          final p2 = Directory(join(ws.path, 'p2'));
          createDirs(<Directory>[p1, p2]);

          File(join(p1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: p1\nversion: 1.0.0\n'
            'dependencies:\n  p2: ^1.0.0',
          );
          File(
            join(p2.path, 'pubspec.yaml'),
          ).writeAsStringSync('name: p2\nversion: 1.0.0');

          final graph = MultiLanguageGraph(
            languages: <ProjectLanguage>[DartProjectLanguage()],
          );
          final result = await graph.buildGraph(directory: p1);
          final top = <String, ProjectNode>{'p1': result.allNodes['p1']!};

          final found = findNode(packageName: 'p2', nodes: top);
          expect(found, isNotNull);
          expect(found!.name, 'p2');

          deleteDirs(<Directory>[ws]);
        });

        test('returns null when not found recursively', () async {
          final ws = createTempDir('pd_findnode_ws2');
          final p1 = Directory(join(ws.path, 'p1'));
          final p2 = Directory(join(ws.path, 'p2'));
          createDirs(<Directory>[p1, p2]);

          File(join(p1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: p1\nversion: 1.0.0\n'
            'dependencies:\n  p2: ^1.0.0',
          );
          File(
            join(p2.path, 'pubspec.yaml'),
          ).writeAsStringSync('name: p2\nversion: 1.0.0');

          final graph = MultiLanguageGraph(
            languages: <ProjectLanguage>[DartProjectLanguage()],
          );
          final result = await graph.buildGraph(directory: p1);
          final top = <String, ProjectNode>{'p1': result.allNodes['p1']!};

          final found = findNode(packageName: 'unknown', nodes: top);
          expect(found, isNull);

          deleteDirs(<Directory>[ws]);
        });
      });
    });
  });
}
