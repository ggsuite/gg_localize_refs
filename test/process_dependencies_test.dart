import 'dart:io';

import 'package:gg_localize_refs/src/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/process_dependencies.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';

import 'test_helpers.dart';

void main() {
  Directory dWorkspaceSucceed = Directory('');

  setUp(() async {
    dWorkspaceSucceed = createTempDir('pd_succeed');
  });

  tearDown(() {
    deleteDirs([dWorkspaceSucceed]);
  });

  group('Process dependencies', () {
    group('processProject()', () {
      group('should throw', () {
        test('when project root was not found', () async {
          Directory dNoProjectRootError = Directory(
            join(dWorkspaceSucceed.path, 'no_project_root_error'),
          );

          createDirs([dNoProjectRootError]);

          List<String> messages = [];

          await expectLater(
            processProject(
              dNoProjectRootError,
              (
                packageName,
                pubspec,
                pubspecContent,
                yamlMap,
                node,
                projectDir,
                fileChangesBuffer,
              ) async {},
              FileChangesBuffer(),
              messages.add,
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('No project root found'),
              ),
            ),
          );
        });

        test('when node not found', () async {
          Directory dNodeNotFound = Directory(
            join(dWorkspaceSucceed.path, 'node_not_found'),
          );

          createDirs([dNodeNotFound]);

          // Create a pubspec.yaml with invalid content in tempDir
          File(join(dNodeNotFound.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test_package\nversion: 1.0.0\ndependencies:',
          );

          await expectLater(
            processNode(
              dNodeNotFound,
              {},
              {},
              (
                packageName,
                pubspec,
                pubspecContent,
                yamlMap,
                node,
                projectDir,
                fileChangesBuffer,
              ) async {},
              FileChangesBuffer(),
            ),
            throwsA(
              isA<Exception>()
                  .having(
                    (e) => e.toString(),
                    'message',
                    contains('node for the package'),
                  )
                  .having(
                    (e) => e.toString(),
                    'message',
                    contains('not found'),
                  ),
            ),
          );
        });
      });

      test('succeeds', () async {
        Directory dProject1 = Directory(
          join(dWorkspaceSucceed.path, 'project1'),
        );
        Directory dProject2 = Directory(
          join(dWorkspaceSucceed.path, 'project2'),
        );

        createDirs([dProject1, dProject2]);

        File(join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
          '''name: test1
version: 1.0.0
dependencies:
  test2: ^1.0.0''',
        );

        File(join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
          '''name: test2
version: 1.0.0''',
        );

        List<String> messages = [];

        await processProject(
          dProject1,
          (
            packageName,
            pubspec,
            pubspecContent,
            yamlMap,
            node,
            projectDir,
            fileChangesBuffer,
          ) async {
            expect(packageName, 'test1');
            expect(pubspec.path, endsWith('pubspec.yaml'));
            expect(pubspecContent, '''name: test1
version: 1.0.0
dependencies:
  test2: ^1.0.0''');
            expect(yamlMap, {
              'name': 'test1',
              'version': '1.0.0',
              'dependencies': {'test2': '^1.0.0'},
            });
            expect(node.name, 'test1');
            expect(projectDir.path, endsWith('project1'));
          },
          FileChangesBuffer(),
          messages.add,
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
                  (e) => e.toString(),
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
          final result = findNode(packageName: 'x', nodes: {});
          expect(result, isNull);
        });

        test('finds dependency via recursive search', () async {
          final ws = createTempDir('pd_findnode_ws');
          final p1 = Directory(join(ws.path, 'p1'));
          final p2 = Directory(join(ws.path, 'p2'));
          createDirs([p1, p2]);

          File(join(p1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: p1\nversion: 1.0.0\n'
            'dependencies:\n  p2: ^1.0.0',
          );
          File(
            join(p2.path, 'pubspec.yaml'),
          ).writeAsStringSync('name: p2\nversion: 1.0.0');

          // Build graph and use only the root node in the top map so that
          // findNode needs to recurse into dependencies.
          final graph = Graph(ggLog: (_) {});
          final nodes = await graph.get(directory: ws, ggLog: (_) {});
          final top = <String, Node>{'p1': nodes['p1']!};

          final found = findNode(packageName: 'p2', nodes: top);
          expect(found, isNotNull);
          expect(found!.name, 'p2');

          deleteDirs([ws]);
        });

        test('returns null when not found recursively', () async {
          final ws = createTempDir('pd_findnode_ws2');
          final p1 = Directory(join(ws.path, 'p1'));
          final p2 = Directory(join(ws.path, 'p2'));
          createDirs([p1, p2]);

          File(join(p1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: p1\nversion: 1.0.0\n'
            'dependencies:\n  p2: ^1.0.0',
          );
          File(
            join(p2.path, 'pubspec.yaml'),
          ).writeAsStringSync('name: p2\nversion: 1.0.0');

          final graph = Graph(ggLog: (_) {});
          final nodes = await graph.get(directory: ws, ggLog: (_) {});
          final top = <String, Node>{'p1': nodes['p1']!};

          final found = findNode(packageName: 'unknown', nodes: top);
          expect(found, isNull);

          deleteDirs([ws]);
        });
      });
    });
  });
}
