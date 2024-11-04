// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import '../../bin/gg_localize_refs.dart';
import '../test_helpers.dart';

void main() {
  Directory tempDir = Directory('');

  Directory tempDir2 = Directory('');

  setUp(() async {
    tempDir = createTempDir('executable_command_test');
    tempDir2 = createTempDir('executable_command_test2');
  });

  tearDown(() {
    deleteDirs(
      [
        tempDir,
        tempDir2,
      ],
    );
  });

  group('bin/gg_localize_refs.dart', () {
    // #########################################################################

    test('should be executable', () async {
      // Execute bin/gg_localize_refs.dart and check if it prints help
      final result = await Process.run(
        'dart',
        [
          './bin/gg_localize_refs.dart',
          'localize-refs',
          '--input',
          tempDir.path,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(result.stdout, contains('No project root found'));
    });
  });

  // ###########################################################################
  group('run(args, log)', () {
    group('with args=[--param, value]', () {
      test('should print "value"', () async {
        // Execute bin/gg_localize_refs.dart and check if it prints "value"
        final messages = <String>[];
        await run(
          args: ['localize-refs', '--input', tempDir2.path],
          ggLog: messages.add,
        );

        expect(messages, isNotEmpty);
        expect(messages.last, contains('No project root found'));
      });
    });
  });
}
