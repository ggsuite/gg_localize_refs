// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_capture_print/gg_capture_print.dart';

import 'package:test/test.dart';
import 'package:path/path.dart';
import '../../bin/gg_to_local.dart';

void main() {
  Directory tempDir =
      Directory(join('test', 'sample_folder', 'executable_command_test'));

  setUp(() async {
    // create the tempDir
    Directory workspaceDir = await Directory.systemTemp.createTemp();

    tempDir = Directory(join(workspaceDir.path, 'executable_command_test'));
    await tempDir.create(recursive: true);

    expect(await tempDir.exists(), isTrue);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('bin/gg_to_local.dart', () {
    // #########################################################################

    test('should be executable', () async {
      // Execute bin/gg_to_local.dart and check if it prints help
      final result = await Process.run(
        'dart',
        ['./bin/gg_to_local.dart', 'local', '--input', tempDir.path],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(result.stdout, contains('No root found'));
    });
  });

  // ###########################################################################
  group('run(args, log)', () {
    group('with args=[--param, value]', () {
      test('should print "value"', () async {
        // Execute bin/gg_to_local.dart and check if it prints "value"
        final messages = <String>[];
        await run(args: ['local', '--input', '5'], ggLog: messages.add);

        final expectedMessages = ['Running local in 5'];

        for (final msg in expectedMessages) {
          expect(hasLog(messages, msg), isTrue);
        }
      });
    });
  });
}
