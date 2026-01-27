import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_localize_refs/src/commands/unlocalize_refs.dart';
import 'package:gg_localize_refs/src/backend/file_changes_buffer.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
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
  Directory dWorkspaceSucceedGit = Directory('');

  setUp(() async {
    messages.clear();
    runner = CommandRunner<void>(
      'unlocalize',
      'Description of unlocalize command.',
    );
    final myCommand = UnlocalizeRefs(ggLog: messages.add);
    runner.addCommand(myCommand);

    dNoProjectRootError = createTempDir(
      'unlocalize_no_project_root_error',
      'project1',
    );
    dParseError = createTempDir('unlocalize_parse_error', 'project1');
    dNoDependencies = createTempDir('unlocalize_no_dependencies', 'project1');
    dNodeNotFound = createTempDir('unlocalize_node_not_found', 'project1');
    dJsonNotFound = createTempDir('unlocalize_json_not_found');
    dWorkspaceSucceed = createTempDir('unlocalize_succeed');
    dWorkspaceSucceedGit = createTempDir('unlocalize_succeed_git');
    dWorkspaceAlreadyUnlocalized = createTempDir(
      'unlocalize_already_unlocalized',
    );

    copyDirectory(
      Directory(
        join('test', 'sample_folder', 'unlocalize_refs', 'path_succeed'),
      ),
      dWorkspaceSucceed,
    );
    copyDirectory(
      Directory(
        join('test', 'sample_folder', 'unlocalize_refs', 'git_succeed'),
      ),
      dWorkspaceSucceedGit,
    );
    copyDirectory(
      Directory(
        join('test', 'sample_folder', 'unlocalize_refs', 'already_unlocalized'),
      ),
      dWorkspaceAlreadyUnlocalized,
    );
    copyDirectory(
      Directory(
        join('test', 'sample_folder', 'unlocalize_refs', 'json_not_found'),
      ),
      dJsonNotFound,
    );
  });

  tearDown(() {
    deleteDirs([
      dNoProjectRootError,
      dParseError,
      dNoDependencies,
      dNodeNotFound,
      dJsonNotFound,
      dWorkspaceSucceed,
      dWorkspaceSucceedGit,
      dWorkspaceAlreadyUnlocalized,
    ]);
  });

  group('UnlocalizeRefs Command', () {
    group('run()', () {
      // .......................................................................
      group('should print a usage description', () {
        test('when called args=[--help]', () async {
          capturePrint(
            ggLog: messages.add,
            code: () => runner.run(['unlocalize-refs', '--help']),
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
            runner.run([
              'unlocalize-refs',
              '--input',
              dNoProjectRootError.path,
            ]),
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
            File(
              join(dParseError.path, 'pubspec.yaml'),
            ).writeAsStringSync('invalid yaml');

            await expectLater(
              runner.run(['unlocalize-refs', '--input', dParseError.path]),
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

          final unlocal = UnlocalizeRefs(ggLog: messages.add);

          await expectLater(
            processNode(
              dNodeNotFound,
              {},
              {},
              unlocal.modifyYaml,
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

      // .......................................................................

      group('should succeed', () {
        test('when pubspec is correct', () async {
          final dProject1 = Directory(join(dWorkspaceSucceed.path, 'project1'));

          final messages = <String>[];
          final unlocal = UnlocalizeRefs(ggLog: messages.add);
          await unlocal.get(directory: dProject1, ggLog: messages.add);

          expect(messages[0], contains('Running unlocalize-refs in'));
          expect(messages[1], contains('Unlocalize refs of test1'));

          // Check if publish_to: none was removed
          final resultYaml = File(
            join(dProject1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(resultYaml, isNot(contains('publish_to: none')));
        });

        test('when pubspec is correct and has git refs', () async {
          final dProject1 = Directory(
            join(dWorkspaceSucceedGit.path, 'project1'),
          );

          final messages = <String>[];
          final unlocal = UnlocalizeRefs(ggLog: messages.add);
          await unlocal.get(directory: dProject1, ggLog: messages.add);

          expect(messages[0], contains('Running unlocalize-refs in'));
          expect(messages[1], contains('Unlocalize refs of test1'));
        });

        test('when already localized', () async {
          final dProject1 = Directory(
            join(dWorkspaceAlreadyUnlocalized.path, 'project1'),
          );

          final messages = <String>[];
          final local = UnlocalizeRefs(ggLog: messages.add);
          await local.get(directory: dProject1, ggLog: messages.add);

          expect(messages[0], contains('Running unlocalize-refs in'));
          expect(messages[1], contains('No files were changed'));
        });

        test('when .gg_localize_refs_backup.json does not exist', () async {
          final messages = <String>[];

          final dProject1 = Directory(join(dJsonNotFound.path, 'project1'));

          final unlocal = UnlocalizeRefs(ggLog: messages.add);

          await unlocal.get(directory: dProject1, ggLog: messages.add);

          // The json file .. with old dependencies does not exist.

          expect(messages[0], contains('Running unlocalize-refs in'));
          expect(messages[1], contains('Unlocalize refs of test1'));
          expect(
            messages[2],
            contains(
              'The automatic change of dependencies could not be performed',
            ),
          );
        });
      });
    });
  });

  group('readDependenciesFromJson', () {
    test('should throw an exception when the json file does not exist', () {
      const nonExistentFilePath = 'non_existent_file.json';

      expect(
        () => readDependenciesFromJson(nonExistentFilePath),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'The json file $nonExistentFilePath with old '
              'dependencies does not exist.',
            ),
          ),
        ),
      );
    });
  });
}
