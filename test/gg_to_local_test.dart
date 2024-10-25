// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_to_local/gg_to_local.dart';
import 'package:test/test.dart';
import 'package:gg_args/gg_args.dart';
import 'package:path/path.dart';

void main() {
  final messages = <String>[];

  Directory tempDir = Directory(
    join(
      'test',
      'sample_folder',
      'workspace_GgToLocal_command',
      'GgToLocal_command',
    ),
  );

  setUp(() async {
    messages.clear();

    // create the tempDir
    Directory workspaceDir = await Directory.systemTemp.createTemp();

    tempDir = Directory(join(workspaceDir.path, 'GgToLocal_command_test'));
    await tempDir.create(recursive: true);

    expect(await tempDir.exists(), isTrue);
  });

  tearDown(() {});

  group('GgToLocal()', () {
    // #########################################################################
    group('GgToLocal', () {
      final ggToLocal = GgToLocal(ggLog: messages.add);

      final CommandRunner<void> runner = CommandRunner<void>(
        'ggToLocal',
        'Description goes here.',
      )..addCommand(ggToLocal);

      test('should allow to run the code from command line', () async {
        File(join(tempDir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: test_package\nversion: 1.0.0\ndependencies:',
        );

        await capturePrint(
          ggLog: messages.add,
          code: () async => await runner.run([
            'ggToLocal',
            'localize-refs',
            '--input',
            tempDir.path,
          ]),
        );
        expect(
          messages,
          contains('Running localize-refs in ${tempDir.path}'),
        );
      });

      // .......................................................................
      test('should show all sub commands', () async {
        final (subCommands, errorMessage) = await missingSubCommands(
          directory: Directory('lib/src/commands'),
          command: ggToLocal,
        );

        expect(subCommands, isEmpty, reason: errorMessage);
      });
    });
  });
}
