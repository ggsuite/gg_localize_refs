// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_localize_refs/src/commands/set_ref_version.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;

  Directory dNoProjectRootError = Directory('');
  Directory dParseError = Directory('');
  Directory dWorkspace = Directory('');

  setUp(() async {
    messages.clear();
    runner = CommandRunner<void>('setref', 'setref desc');
    final cmd = SetRefVersion(ggLog: messages.add);
    runner.addCommand(cmd);

    dNoProjectRootError = createTempDir('setref_no_root', 'project1');
    dParseError = createTempDir('setref_parse_error', 'project1');
    dWorkspace = createTempDir('setref_workspace');
  });

  tearDown(() {
    deleteDirs(<Directory>[dNoProjectRootError, dParseError, dWorkspace]);
  });

  group('SetRefVersion', () {
    test('shows help', () async {
      capturePrint(
        ggLog: messages.add,
        code: () => runner.run(<String>['set-ref-version', '--help']),
      );
      expect(messages.last, contains('Sets the version/spec'));
    });

    group('should throw', () {
      test('when pubspec.yaml was not found', () async {
        await expectLater(
          runner.run(<String>[
            'set-ref-version',
            '--input',
            dNoProjectRootError.path,
            '--ref',
            'x',
            '--version',
            '^1.0.0',
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
        await expectLater(
          runner.run(<String>[
            'set-ref-version',
            '--input',
            dParseError.path,
            '--ref',
            'x',
            '--version',
            '^1.0.0',
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

      test('when dependency not found', () async {
        final d1 = Directory(join(dWorkspace.path, 'a1'));
        final d2 = Directory(join(dWorkspace.path, 'a2'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: a1\nversion: 1.0.0\ndependencies:\n  a2: ^1.0.0',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: a2\nversion: 1.0.0');

        await expectLater(
          runner.run(<String>[
            'set-ref-version',
            '--input',
            d1.path,
            '--ref',
            'does_not_exist',
            '--version',
            '^2.0.0',
          ]),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('Dependency does_not_exist not found.'),
            ),
          ),
        );
      });

      test('when --ref is missing', () async {
        final d = Directory(join(dWorkspace.path, 'missing_ref'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'pubspec.yaml')).writeAsStringSync(
          'name: a\nversion: 1.0.0\ndependencies:\n  b: ^1.0.0',
        );
        await expectLater(
          runner.run(<String>[
            'set-ref-version',
            '--input',
            d.path,
            '--version',
            '^2.0.0',
          ]),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('Please provide a dependency name via --ref.'),
            ),
          ),
        );
      });

      test('when --version is missing', () async {
        final d = Directory(join(dWorkspace.path, 'missing_version'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'pubspec.yaml')).writeAsStringSync(
          'name: a\nversion: 1.0.0\ndependencies:\n  b: ^1.0.0',
        );
        await expectLater(
          runner.run(<String>[
            'set-ref-version',
            '--input',
            d.path,
            '--ref',
            'b',
          ]),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('Please provide the new version via --version.'),
            ),
          ),
        );
      });

      test('when dependency not found in package.json', () async {
        final d = Directory(join(dWorkspace.path, 'ts_missing_dep'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'package.json')).writeAsStringSync(
          '{"name":"ts_missing_dep","dependencies":{"a":"^1.0.0"}}',
        );

        await expectLater(
          runner.run(<String>[
            'set-ref-version',
            '--input',
            d.path,
            '--ref',
            'b',
            '--version',
            '^2.0.0',
          ]),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('Dependency b not found.'),
            ),
          ),
        );
      });

      test('when dependency is unpublished and not in workspace', () async {
        final d1 = Directory(join(dWorkspace.path, 'workspace_root', 'a1'));
        final outside = Directory(join(dWorkspace.path, 'outside_dep'));
        await createDirs(<Directory>[d1, outside]);

        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: a1\nversion: 1.0.0\npublish_to: none\n'
          'dependencies:\n  outside_dep: ^1.0.0',
        );
        File(join(outside.path, 'pubspec.yaml')).writeAsStringSync(
          'name: outside_dep\nversion: 1.0.0\npublish_to: none\n',
        );

        await expectLater(
          runner.run(<String>[
            'set-ref-version',
            '--input',
            d1.path,
            '--ref',
            'outside_dep',
            '--version',
            '^2.0.0',
          ]),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains(
                'Could not find local directory for dependency '
                'outside_dep.',
              ),
            ),
          ),
        );
      });
    });

    group('should succeed', () {
      test(
        'replace scalar with pub.dev scalar when dependency is published',
        () async {
          final d1 = Directory(join(dWorkspace.path, 'b1'));
          final d2 = Directory(join(dWorkspace.path, 'b2'));
          await createDirs(<Directory>[d1, d2]);
          File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: b1\nversion: 1.0.0\ndependencies:\n  b2: ^1.0.0',
          );
          File(
            join(d2.path, 'pubspec.yaml'),
          ).writeAsStringSync('name: b2\nversion: 1.0.0');

          await runner.run(<String>[
            'set-ref-version',
            '--input',
            d1.path,
            '--ref',
            'b2',
            '--version',
            '^2.0.0',
          ]);
          final content = File(
            join(d1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(content, contains('b2: ^2.0.0'));
        },
      );

      test(
        'replace scalar with git version block when dependency is unpublished',
        () async {
          final d1 = Directory(join(dWorkspace.path, 'c1'));
          final d2 = Directory(join(dWorkspace.path, 'c2'));
          await createDirs(<Directory>[d1, d2]);
          File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
            'name: c1\nversion: 1.0.0\ndependencies:\n  c2: ^1.0.0',
          );
          File(
            join(d2.path, 'pubspec.yaml'),
          ).writeAsStringSync('name: c2\nversion: 1.0.0\npublish_to: none\n');

          Process.runSync('git', <String>['init'], workingDirectory: d2.path);
          Process.runSync('git', <String>[
            'remote',
            'add',
            'origin',
            'git@github.com:user/c2.git',
          ], workingDirectory: d2.path);

          await runner.run(<String>[
            'set-ref-version',
            '--input',
            d1.path,
            '--ref',
            'c2',
            '--version',
            '^3.0.0',
          ]);
          final content = File(
            join(d1.path, 'pubspec.yaml'),
          ).readAsStringSync();
          expect(content, contains('c2:'));
          expect(content, contains('git:'));
          expect(content, contains('version: ^3.0.0'));
          expect(content, isNot(contains('tag_pattern:')));
        },
      );

      test('replace git block with scalar', () async {
        final d1 = Directory(join(dWorkspace.path, 'd1'));
        final d2 = Directory(join(dWorkspace.path, 'd2'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: d1\nversion: 1.0.0\ndependencies:\n  d2:\n'
          '    git:\n      url: git@github.com:user/d2.git\n'
          '      ref: main',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: d2\nversion: 1.0.0');

        await runner.run(<String>[
          'set-ref-version',
          '--input',
          d1.path,
          '--ref',
          'd2',
          '--version',
          '^3.0.0',
        ]);
        final content = File(join(d1.path, 'pubspec.yaml')).readAsStringSync();
        expect(content, contains('d2: ^3.0.0'));
        expect(content, isNot(contains('git:')));
      });

      test('replace git version block version only', () async {
        final d1 = Directory(join(dWorkspace.path, 'd1b'));
        final d2 = Directory(join(dWorkspace.path, 'd2b'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: d1b\nversion: 1.0.0\ndependencies:\n'
          '  d2b:\n'
          '    git: git@github.com:user/d2b.git\n'
          '    version: ^1.0.0\n',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: d2b\nversion: 1.0.0\npublish_to: none\n');

        Process.runSync('git', <String>['init'], workingDirectory: d2.path);
        Process.runSync('git', <String>[
          'remote',
          'add',
          'origin',
          'git@github.com:user/d2b.git',
        ], workingDirectory: d2.path);

        await runner.run(<String>[
          'set-ref-version',
          '--input',
          d1.path,
          '--ref',
          'd2b',
          '--version',
          '^3.0.0',
        ]);
        final content = File(join(d1.path, 'pubspec.yaml')).readAsStringSync();
        expect(content, contains('git:'));
        expect(content, contains('version: ^3.0.0'));
        expect(content, isNot(contains('tag_pattern:')));
      });

      test('replace path block with scalar', () async {
        final d1 = Directory(join(dWorkspace.path, 'e1'));
        final d2 = Directory(join(dWorkspace.path, 'e2'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: e1\nversion: 1.0.0\ndependencies:\n  e2:\n    path: ../e2',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: e2\nversion: 1.0.0');

        await runner.run(<String>[
          'set-ref-version',
          '--input',
          d1.path,
          '--ref',
          'e2',
          '--version',
          '^2.1.0',
        ]);
        final content = File(join(d1.path, 'pubspec.yaml')).readAsStringSync();
        expect(content, contains('e2: ^2.1.0'));
        expect(content, isNot(contains('path:')));
      });

      test('updates dev_dependency', () async {
        final d1 = Directory(join(dWorkspace.path, 'f1'));
        final d2 = Directory(join(dWorkspace.path, 'f2'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: f1\nversion: 1.0.0\ndev_dependencies:\n  f2: ^1.0.0',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: f2\nversion: 1.0.0');

        await runner.run(<String>[
          'set-ref-version',
          '--input',
          d1.path,
          '--ref',
          'f2',
          '--version',
          '^1.1.0',
        ]);
        final content = File(join(d1.path, 'pubspec.yaml')).readAsStringSync();
        expect(content, contains('f2: ^1.1.0'));
      });

      test('no change when value is equal (logs and returns)', () async {
        final d1 = Directory(join(dWorkspace.path, 'g1'));
        final d2 = Directory(join(dWorkspace.path, 'g2'));
        await createDirs(<Directory>[d1, d2]);
        File(join(d1.path, 'pubspec.yaml')).writeAsStringSync(
          'name: g1\nversion: 1.0.0\ndependencies:\n  g2: ^1.0.0',
        );
        File(
          join(d2.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: g2\nversion: 1.0.0');
        messages.clear();
        await runner.run(<String>[
          'set-ref-version',
          '--input',
          d1.path,
          '--ref',
          'g2',
          '--version',
          '^1.0.0',
        ]);
        final content = File(join(d1.path, 'pubspec.yaml')).readAsStringSync();
        expect(content, contains('g2: ^1.0.0'));
        expect(messages.join('\n'), contains('No files were changed'));
      });

      test('replace scalar with scalar in package.json', () async {
        final d = Directory(join(dWorkspace.path, 'ts_scalar'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'package.json')).writeAsStringSync(
          '{"name":"ts_scalar","dependencies":{"dep":"^1.0.0"}}',
        );

        await runner.run(<String>[
          'set-ref-version',
          '--input',
          d.path,
          '--ref',
          'dep',
          '--version',
          '^2.0.0',
        ]);
        final content = File(join(d.path, 'package.json')).readAsStringSync();
        expect(content, contains('"dep":"^2.0.0"'));
      });

      test('updates devDependency in package.json', () async {
        final d = Directory(join(dWorkspace.path, 'ts_dev'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'package.json')).writeAsStringSync(
          '{"name":"ts_dev","devDependencies":{"dep":"^1.0.0"}}',
        );

        await runner.run(<String>[
          'set-ref-version',
          '--input',
          d.path,
          '--ref',
          'dep',
          '--version',
          '^1.1.0',
        ]);
        final content = File(join(d.path, 'package.json')).readAsStringSync();
        expect(content, contains('"dep":"^1.1.0"'));
      });

      test('no change when value is equal in '
          'package.json logs and returns', () async {
        final d = Directory(join(dWorkspace.path, 'ts_equal'));
        await createDirs(<Directory>[d]);
        File(join(d.path, 'package.json')).writeAsStringSync(
          '{"name":"ts_equal","dependencies":{"dep":"^1.0.0"}}',
        );
        messages.clear();
        await runner.run(<String>[
          'set-ref-version',
          '--input',
          d.path,
          '--ref',
          'dep',
          '--version',
          '^1.0.0',
        ]);
        final content = File(join(d.path, 'package.json')).readAsStringSync();
        expect(content, contains('"dep":"^1.0.0"'));
        expect(messages.join('\n'), contains('No files were changed'));
      });

      test(
        'throws package.json not found message when no manifest exists',
        () async {
          final d = Directory(join(dWorkspace.path, 'missing_manifest'));
          await createDirs(<Directory>[d]);

          await expectLater(
            runner.run(<String>[
              'set-ref-version',
              '--input',
              d.path,
              '--ref',
              'dep',
              '--version',
              '^1.0.0',
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
