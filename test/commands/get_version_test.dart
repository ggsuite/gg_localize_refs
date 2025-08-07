// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_localize_refs/src/commands/get_version.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;

  Directory dNoPubspec = Directory('');
  Directory dParseError = Directory('');
  Directory dWorkspace = Directory('');

  setUp(() async {
    messages.clear();
    runner = CommandRunner<void>('getversion', 'getversion desc');
    final cmd = GetVersion(ggLog: messages.add);
    runner.addCommand(cmd);

    dNoPubspec = createTempDir('getversion_no_pubspec', 'project1');
    dParseError = createTempDir('getversion_parse_error', 'project1');
    dWorkspace = createTempDir('getversion_workspace');
  });

  tearDown(() {
    deleteDirs([
      dNoPubspec,
      dParseError,
      dWorkspace,
    ]);
  });

  group('GetVersion', () {
    test('shows help', () async {
      capturePrint(
        ggLog: messages.add,
        code: () => runner.run(['get-version', '--help']),
      );
      expect(messages.last, contains('Reads the current package version'));
    });

    group('should throw', () {
      test('when pubspec.yaml was not found', () async {
        await expectLater(
          runner.run([
            'get-version',
            '--input',
            dNoPubspec.path,
          ]),
          throwsA(
            isA<Exception>()
                .having(
                  (e) => e.toString(),
                  'message',
                  contains('pubspec.yaml'),
                )
                .having(
                  (e) => e.toString(),
                  'message',
                  contains('not found'),
                ),
          ),
        );
      });

      test('when pubspec.yaml cannot be parsed', () async {
        File(join(dParseError.path, 'pubspec.yaml')).writeAsStringSync(
          'invalid yaml',
        );
        await expectLater(
          runner.run([
            'get-version',
            '--input',
            dParseError.path,
          ]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('An error occurred'),
            ),
          ),
        );
      });
    });

    group('should succeed', () {
      test('reads version', () async {
        final d1 = Directory(join(dWorkspace.path, 'v1'));
        final d2 = Directory(join(dWorkspace.path, 'v2'));
        createDirs([d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: v1\nversion: 1.2.3',
        );
        File(join(d2.path, 'pubspec.yaml')).writeAsStringSync(
          'name: v2\nversion: 1.0.0',
        );
        messages.clear();
        await runner.run([
          'get-version',
          '--input',
          d1.path,
        ]);
        expect(messages.first, contains('Running get-version in'));
        expect(messages.last.trim(), '1.2.3');
      });

      test('logs warning when version missing', () async {
        final d = Directory(join(dWorkspace.path, 'v3'));
        createDirs([d]);
        File(join(d.path, 'pubspec.yaml')).writeAsStringSync(
          'name: v3',
        );
        messages.clear();
        await runner.run([
          'get-version',
          '--input',
          d.path,
        ]);
        expect(messages.last, contains('No version found'));
      });
    });
  });
}
