// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart';
import '../../bin/gg_to_local.dart';

void main() {
  Directory tempDir =
      Directory(join('test', 'sample_folder', 'executable_command_test'));

  Directory tempDir2 =
      Directory(join('test', 'sample_folder', 'executable_command_test2'));

  setUp(() async {
    // create the tempDir
    createDirs(
      [
        tempDir,
        tempDir2,
      ],
    );
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
        ['./bin/gg_to_local.dart', 'localize-refs', '--input', tempDir.path],
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
        // Execute bin/gg_to_local.dart and check if it prints "value"
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

void createDirs(List<Directory> dirs) {
  for (final dir in dirs) {
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    expect(dir.existsSync(), isTrue);
  }
}

void deleteDirs(List<Directory> dirs) {
  for (final dir in dirs) {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    expect(dir.existsSync(), isFalse);
  }
}
