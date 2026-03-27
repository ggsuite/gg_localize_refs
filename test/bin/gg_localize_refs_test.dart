// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
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
  Directory tempDirGit = Directory('');

  setUp(() async {
    tempDir = createTempDir('executable_command_test');
    tempDir2 = createTempDir('executable_command_test2');
    tempDirGit = createTempDir('executable_command_git');
  });

  tearDown(() {
    deleteDirs([tempDir, tempDir2, tempDirGit]);
  });

  group('bin/gg_localize_refs.dart', () {
    test('should be executable', () async {
      final result = await Process.run(
        'dart',
        [
          './bin/gg_localize_refs.dart',
          'change-refs-to-local',
          '--input',
          tempDir.path,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      expect(result.stdout, contains('No project root found'));
    });

    test('should be executable with git feature branch command', () async {
      final result = await Process.run(
        'dart',
        [
          './bin/gg_localize_refs.dart',
          'change-refs-to-git-feature-branch',
          '--git-ref',
          'feature/test',
          '--input',
          tempDirGit.path,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(
        result.stdout.toString() + result.stderr.toString(),
        contains('No project root found'),
      );
    });
  });

  group('run(args, log)', () {
    group('with args=[--param, value]', () {
      test('should print "value"', () async {
        final messages = <String>[];
        await run(
          args: ['change-refs-to-local', '--input', tempDir2.path],
          ggLog: messages.add,
        );

        expect(messages, isNotEmpty);
        expect(messages.last, contains('No project root found'));
      });

      test('should also run git feature branch command', () async {
        final messages = <String>[];
        await run(
          args: [
            'change-refs-to-git-feature-branch',
            '--git-ref',
            'feature/test',
            '--input',
            tempDirGit.path,
          ],
          ggLog: messages.add,
        );
        expect(messages, isNotEmpty);
        expect(messages.join('\n'), contains('No project root found'));
      });
    });
  });
}
