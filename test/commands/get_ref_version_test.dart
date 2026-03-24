// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_localize_refs/src/commands/get_ref_version.dart';
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
    runner = CommandRunner<void>('getref', 'getref desc');
    final cmd = GetRefVersion(ggLog: messages.add);
    runner.addCommand(cmd);

    dNoPubspec = createTempDir('getref_no_pubspec', 'project1');
    dParseError = createTempDir('getref_parse_error', 'project1');
    dWorkspace = createTempDir('getref_workspace');
  });

  tearDown(() {
    deleteDirs(<Directory>[dNoPubspec, dParseError, dWorkspace]);
  });

  group('GetRefVersion', () {
    test('shows help', () async {
      capturePrint(
        ggLog: messages.add,
        code: () => runner.run(<String>['get-ref-version', '--help']),
      );
      expect(messages.last, contains('Reads the current version/spec'));
    });

    group('should throw', () {
      test('when pubspec.yaml was not found', () async {
        await expectLater(
          runner.run(<String>[
            'get-ref-version',
            '--input',
            dNoPubspec.path,
            '--ref',
            'x',
          ]),
          throwsA(
            isA<Exception>()
                .having(
                  (Object e) => e.toString(),
                  'message',
                  contains('pubspec.yaml'),
                )
                .having(
                  (Object e) => e.toString(),
                  'message',
                  contains('not found'),
                ),
          ),
        );
      });

      test('when pubspec.yaml cannot be parsed', () async {
        File(
          join(dParseError.path, 'pubspec.yaml'),
        ).writeAsStringSync('invalid yaml');
        await initGit(dParseError);
        await expectLater(
          runner.run(<String>[
            'get-ref-version',
            '--input',
            dParseError.path,
            '--ref',
            'x',
          ]),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('An error occurred'),
            ),
          ),
        );
      });

      test('when --ref is missing', () async {
        final d = Directory(join(dWorkspace.path, 'missing_ref'));
        await createDirs(<Directory>[d]);
        File(
          join(d.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: a\nversion: 1.0.0');
        await expectLater(
          runner.run(<String>['get-ref-version', '--input', d.path]),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('Please provide a dependency name via --ref.'),
            ),
          ),
        );
      });
    });

    group('should succeed', () {
      test('reads scalar from dependencies', () async {
        final d1 = Directory(join(dWorkspace.path, 'p1'));
        final d2 = Directory(join(dWorkspace.path, 'p2'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: p1\nversion: 1.0.0\n'
          'dependencies:\n  p2: ^1.2.3',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: p2\nversion: 1.0.0');
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d1.path,
          '--ref',
          'p2',
        ]);
        expect(messages.first, contains('Running get-ref-version in'));
        expect(messages.last.trim(), '^1.2.3');
      });

      test('reads from dev_dependencies when not in dependencies', () async {
        final d1 = Directory(join(dWorkspace.path, 'p3'));
        final d2 = Directory(join(dWorkspace.path, 'p4'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: p3\nversion: 1.0.0\n'
          'dev_dependencies:\n  p4: ^2.0.0',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: p4\nversion: 1.0.0');
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d1.path,
          '--ref',
          'p4',
        ]);
        expect(messages.last.trim(), '^2.0.0');
      });

      test('reads git block', () async {
        final d1 = Directory(join(dWorkspace.path, 'p5'));
        final d2 = Directory(join(dWorkspace.path, 'p6'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: p5\nversion: 1.0.0\ndependencies:\n'
          '  p6:\n    git:\n      url: git@github.com:user/p6.git\n'
          '      ref: main',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: p6\nversion: 1.0.0');
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d1.path,
          '--ref',
          'p6',
        ]);
        final out = messages.last;
        expect(out, contains('git:'));
        expect(out, contains('url: git@github.com:user/p6.git'));
        expect(out, contains('ref: main'));
      });

      test('reads version from git tag_pattern block', () async {
        final d1 = Directory(join(dWorkspace.path, 'p5b'));
        final d2 = Directory(join(dWorkspace.path, 'p6b'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: p5b\nversion: 1.0.0\ndependencies:\n'
          '  p6b:\n'
          '    git:\n'
          '      url: git@github.com:user/p6b.git\n'
          '      tag_pattern: {{version}}\n'
          '    version: ^2.0.1\n',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: p6b\nversion: 1.0.0');
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d1.path,
          '--ref',
          'p6b',
        ]);
        expect(messages.last.trim(), '^2.0.1');
      });

      test('reads path block', () async {
        final d1 = Directory(join(dWorkspace.path, 'p7'));
        final d2 = Directory(join(dWorkspace.path, 'p8'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: p7\nversion: 1.0.0\n'
          'dependencies:\n  p8:\n    path: ../p8',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: p8\nversion: 1.0.0');
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d1.path,
          '--ref',
          'p8',
        ]);
        final out = messages.last;
        expect(out, contains('path: ../p8'));
      });

      test('logs warning when dependency not found', () async {
        final d1 = Directory(join(dWorkspace.path, 'p9'));
        await createDirs(<Directory>[d1]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: p9\nversion: 1.0.0\n'
          'dependencies: {}',
        );
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d1.path,
          '--ref',
          'does_not_exist',
        ]);
        expect(messages.last, contains('not found'));
      });

      test('reads scalar from dependencies in package.json', () async {
        final d = Directory(join(dWorkspace.path, 'ts1'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'package.json')).writeAsStringSync(
          '{"name":"ts1","version":"1.0.0","dependencies":'
          '{"dep":"^1.2.3"}}',
        );
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d.path,
          '--ref',
          'dep',
        ]);
        expect(messages.last.trim(), '^1.2.3');
      });

      test('reads from devDependencies when not in dependencies '
          'in package.json', () async {
        final d = Directory(join(dWorkspace.path, 'ts2'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'package.json')).writeAsStringSync(
          '{"name":"ts2","version":"1.0.0","devDependencies":'
          '{"dep":"^2.0.0"}}',
        );
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d.path,
          '--ref',
          'dep',
        ]);
        expect(messages.last.trim(), '^2.0.0');
      });

      test('logs warning when dependency not found in package.json', () async {
        final d = Directory(join(dWorkspace.path, 'ts3'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'package.json')).writeAsStringSync(
          '{"name":"ts3","version":"1.0.0","dependencies":{}}',
        );
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d.path,
          '--ref',
          'does_not_exist',
        ]);
        expect(messages.last, contains('not found'));
      });

      test('tries both devDependencies casts when key is missing', () async {
        final d = Directory(join(dWorkspace.path, 'ts4'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'package.json')).writeAsStringSync(
          '{"name":"ts4","version":"1.0.0","devDependencies":'
          '{"other":"^1.0.0"}}',
        );
        messages.clear();
        await runner.run(<String>[
          'get-ref-version',
          '--input',
          d.path,
          '--ref',
          'missing',
        ]);
        expect(messages.last, contains('not found'));
      });

      test(
        'throws package.json not found message when no manifest exists',
        () async {
          final d = Directory(join(dWorkspace.path, 'missing_manifest'));
          await createDirs(<Directory>[d]);

          await expectLater(
            runner.run(<String>[
              'get-ref-version',
              '--input',
              d.path,
              '--ref',
              'dep',
            ]),
            throwsA(
              isA<Exception>().having(
                (Object e) => e.toString(),
                'message',
                contains('pubspec.yaml not found'),
              ),
            ),
          );
        },
      );
    });
  });
}
