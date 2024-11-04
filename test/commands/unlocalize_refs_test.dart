import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_localize_refs/src/commands/unlocalize_refs.dart';
import 'package:gg_localize_refs/src/process_dependencies.dart';
import 'package:test/test.dart';
import 'package:path/path.dart';

import '../test_helpers.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;

  Directory dNoProjectRootError = Directory('');
  Directory dParseError = Directory('');
  Directory dNoDependencies = Directory('');
  Directory dNodeNotFound = Directory('');
  Directory dJsonNotFound = Directory('');
  Directory dWorkspaceAlreadyUnlocalized = Directory('');
  Directory dWorkspaceSucceed = Directory('');

  setUp(() async {
    messages.clear();
    runner =
        CommandRunner<void>('unlocalize', 'Description of unlocalize command.');
    final myCommand = UnlocalizeRefs(ggLog: messages.add);
    runner.addCommand(myCommand);

    dNoProjectRootError =
        createTempDir('unlocalize_no_project_root_error', 'project1');
    dParseError = createTempDir('unlocalize_parse_error', 'project1');
    dNoDependencies = createTempDir('unlocalize_no_dependencies', 'project1');
    dNodeNotFound = createTempDir('unlocalize_node_not_found', 'project1');
    dJsonNotFound = createTempDir('unlocalize_json_not_found', 'project1');
    dWorkspaceSucceed = createTempDir('unlocalize_succeed');
    dWorkspaceAlreadyUnlocalized =
        createTempDir('unlocalize_already_unlocalized');
  });

  tearDown(() {
    deleteDirs(
      [
        dNoProjectRootError,
        dParseError,
        dNoDependencies,
        dNodeNotFound,
        dJsonNotFound,
        dWorkspaceSucceed,
        dWorkspaceAlreadyUnlocalized,
      ],
    );
  });

  group('UnlocalizeRefs Command', () {
    group('run()', () {
      // .......................................................................
      group('should print a usage description', () {
        test('when called args=[--help]', () async {
          capturePrint(
            ggLog: messages.add,
            code: () => runner.run(
              ['unlocalize-refs', '--help'],
            ),
          );

          expect(
            messages.last,
            contains('Changes dependencies to remote dependencies.'),
          );
        });
      });

      // .......................................................................
      group('should throw', () {
        test('when project root was not found', () async {
          await expectLater(
            runner.run(
              ['unlocalize-refs', '--input', dNoProjectRootError.path],
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

        group('when pubspec.yaml cannot be parsed', () {
          test('when calling command', () async {
            // Create a pubspec.yaml with invalid content in tempDir
            File(join(dParseError.path, 'pubspec.yaml'))
                .writeAsStringSync('invalid yaml');

            await expectLater(
              runner.run(
                ['unlocalize-refs', '--input', dParseError.path],
              ),
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

        test('when node not found', () async {
          final messages = <String>[];

          // Create a pubspec.yaml with invalid content in tempDir
          File(join(dNodeNotFound.path, 'pubspec.yaml')).writeAsStringSync(
            'name: test_package\nversion: 1.0.0\ndependencies: {}',
          );

          UnlocalizeRefs unlocal = UnlocalizeRefs(ggLog: messages.add);

          await expectLater(
            processNode(dNodeNotFound, {}, {}, unlocal.modifyYaml),
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

        test('when .gg_localize_refs_backup.json does not exist', () async {
          final messages = <String>[];

          Directory dProject1 = Directory(join(dJsonNotFound.path, 'project1'));
          Directory dProject2 = Directory(join(dJsonNotFound.path, 'project2'));

          createDirs([dProject1, dProject2]);

          File(join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test1
version: 1.0.0
dependencies:
  test2:
    path: ../project2''',
          );

          File(join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test2
version: 1.0.0''',
          );

          UnlocalizeRefs unlocal = UnlocalizeRefs(ggLog: messages.add);

          await expectLater(
            unlocal.get(directory: dProject1, ggLog: messages.add),
            throwsA(
              isA<Exception>()
                  .having(
                    (e) => e.toString(),
                    'message',
                    contains('The json file'),
                  )
                  .having(
                    (e) => e.toString(),
                    'message',
                    contains('with old dependencies does not exist.'),
                  ),
            ),
          );
        });
      });

      // .......................................................................

      group('should succeed', () {
        test('when pubspec is correct', () async {
          Directory dProject1 =
              Directory(join(dWorkspaceSucceed.path, 'project1'));
          Directory dProject2 =
              Directory(join(dWorkspaceSucceed.path, 'project2'));

          createDirs([dProject1, dProject2]);

          File(join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test1
version: 1.0.0
dependencies:
  test2:
    path: ../project2''',
          );

          File(join(dProject1.path, '.gg_localize_refs_backup.json'))
              .writeAsStringSync('{"test2":"^2.0.4"}');

          File(join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test2
version: 1.0.0''',
          );

          final messages = <String>[];
          UnlocalizeRefs unlocal = UnlocalizeRefs(ggLog: messages.add);
          await unlocal.get(directory: dProject1, ggLog: messages.add);

          expect(messages[0], contains('Running unlocalize-refs in'));
          expect(
            messages[1],
            contains('Processing dependencies of package test1'),
          );
          expect(messages[2], contains('test2'));
        });

        test('when already localized', () async {
          Directory dProject1 =
              Directory(join(dWorkspaceAlreadyUnlocalized.path, 'project1'));
          Directory dProject2 =
              Directory(join(dWorkspaceAlreadyUnlocalized.path, 'project2'));

          createDirs([dProject1, dProject2]);

          File(join(dProject1.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test1
version: 1.0.0
dependencies:
  test2: ^1.0.0''',
          );

          File(join(dProject1.path, '.gg_localize_refs_backup.json'))
              .writeAsStringSync('{"test2":"^2.0.4"}');

          File(join(dProject2.path, 'pubspec.yaml')).writeAsStringSync(
            '''name: test2
version: 1.0.0''',
          );

          final messages = <String>[];
          UnlocalizeRefs local = UnlocalizeRefs(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          expect(messages[0], contains('Running unlocalize-refs in'));
          expect(
            messages[1],
            contains('Processing dependencies of package test1'),
          );
          expect(
            messages[2],
            contains('Dependencies already unlocalized.'),
          );
        });
      });
    });
  });
}
