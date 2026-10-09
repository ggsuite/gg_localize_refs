// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_localize_refs/src/commands/change_refs_to_local.dart';
import 'package:gg_localize_refs/src/commands/unlocalized_refs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  final messages = <String>[];
  final workspaces = <Directory>[];

  /// Copies the scenario [name] of [folder] into a fresh temp workspace and
  /// returns its `project1`.
  Directory scenario(String name, {String folder = 'sample_folder'}) {
    final workspace = createTempDir('unlocalized_refs_$name');
    workspaces.add(workspace);
    copyDirectory(
      Directory(p.join('test', folder, 'localize_refs', name)),
      workspace,
    );
    return Directory(p.join(workspace.path, 'project1'));
  }

  /// Returns the refs of [project] as their `toString` lines.
  Future<List<String>> refsOf(Directory project) async {
    final refs = await UnlocalizedRefs(ggLog: messages.add)
        .get(directory: project, ggLog: messages.add);
    return refs.map((ref) => ref.toString()).toList();
  }

  /// Runs `change-refs-to-local` on [project].
  Future<void> localize(Directory project) =>
      ChangeRefsToLocal(ggLog: (_) {}).get(directory: project, ggLog: (_) {});

  setUp(messages.clear);

  tearDown(() {
    deleteDirs(workspaces);
    workspaces.clear();
  });

  group('UnlocalizedRef', () {
    test('toString() explains both kinds', () {
      const missing = UnlocalizedRef(
        project: 'a',
        dependency: 'b',
        kind: UnlocalizedRefKind.missing,
      );
      const stale = UnlocalizedRef(
        project: 'a',
        dependency: 'b',
        kind: UnlocalizedRefKind.stale,
      );

      expect(
        missing.toString(),
        'a uses the published b instead of its checkout',
      );
      expect(stale.toString(), 'a still overrides b, which it no longer needs');
    });
  });

  group('UnlocalizedRefs', () {
    group('get()', () {
      group('Dart', () {
        test('reports a dependency without override, '
            'nothing after change-refs-to-local', () async {
          final project = scenario('succeed');

          expect(await refsOf(project), <String>[
            'test1 uses the published test2 instead of its checkout',
          ]);

          await localize(project);
          expect(await refsOf(project), isEmpty);
        });

        test('reports a transitive dependency too', () async {
          final project = scenario('transitive');

          expect(await refsOf(project), <String>[
            'test1 uses the published test2 instead of its checkout',
            'test1 uses the published test3 instead of its checkout',
          ]);

          await localize(project);
          expect(await refsOf(project), isEmpty);
        });

        test('reports an override with another value as missing', () async {
          final project = scenario('already_localized');
          File(p.join(project.path, 'pubspec_overrides.yaml'))
              .writeAsStringSync(
                'dependency_overrides:\n'
                '  test2:\n'
                '    git:\n'
                '      url: git@github.com:user/test2.git\n'
                '      ref: feature123\n',
              );

          expect(await refsOf(project), <String>[
            'test1 uses the published test2 instead of its checkout',
          ]);
        });

        test('reports nothing for a localized project', () async {
          expect(await refsOf(scenario('already_localized')), isEmpty);
        });

        test('reports an override of a dropped dependency as stale, '
            'nothing after change-refs-to-local', () async {
          final project = scenario('stale_override');

          expect(await refsOf(project), <String>[
            'test1 still overrides test2, which it no longer needs',
          ]);

          await localize(project);
          expect(await refsOf(project), isEmpty);
        });

        test('keeps hand written and inherited overrides out', () async {
          final project = scenario('overrides_unrelated');
          await localize(project);

          expect(await refsOf(project), isEmpty);
        });

        test('reports nothing for a project without dependencies', () async {
          final project = scenario('stale_override');
          File(p.join(project.path, 'pubspec.yaml'))
              .writeAsStringSync('name: test1\nversion: 1.0.0\n');

          expect(await refsOf(project), isEmpty);
        });

        test('does not write anything', () async {
          final project = scenario('succeed');
          final before = _snapshot(project.parent);

          await refsOf(project);

          expect(_snapshot(project.parent), before);
        });
      });

      group('TypeScript pnpm', () {
        test('reports a dependency without override, '
            'nothing after change-refs-to-local', () async {
          final project = scenario('pnpm_succeed', folder: 'sample_folder_ts');

          expect(await refsOf(project), <String>[
            'test1_ts uses the published test2_ts instead of its checkout',
          ]);

          await localize(project);
          expect(await refsOf(project), isEmpty);
        });

        test('expects the shim link for a sibling with sources', () async {
          final project = scenario(
            'pnpm_with_sources',
            folder: 'sample_folder_ts',
          );

          // The direct link is not what change-refs-to-local writes here.
          File(p.join(project.path, 'pnpm-workspace.yaml'))
              .writeAsStringSync('overrides:\n  test2_ts: link:../project2\n');
          expect(await refsOf(project), hasLength(1));
          expect(
            Directory(p.join(project.path, '.gg', 'ts_links')).existsSync(),
            isFalse,
          );

          await localize(project);
          expect(await refsOf(project), isEmpty);
        });

        test('reports a missing shim, '
            'nothing after change-refs-to-local', () async {
          final project = scenario(
            'pnpm_with_sources',
            folder: 'sample_folder_ts',
          );
          await localize(project);
          final shims = Directory(p.join(project.path, '.gg', 'ts_links'));

          // A fresh clone or `git clean` drops the gitignored shims.
          shims.deleteSync(recursive: true);
          expect(await refsOf(project), <String>[
            'test1_ts uses the published test2_ts instead of its checkout',
          ]);

          await localize(project);
          expect(await refsOf(project), isEmpty);
        });

        test('reports an override of a dropped dependency as stale, '
            'nothing after change-refs-to-local', () async {
          final project = scenario(
            'pnpm_stale_override',
            folder: 'sample_folder_ts',
          );

          expect(await refsOf(project), <String>[
            'test1_ts still overrides test2_ts, which it no longer needs',
          ]);

          await localize(project);
          expect(await refsOf(project), isEmpty);
        });
      });

      group('TypeScript legacy npm', () {
        test('reports a dependency whose spec is no link, '
            'nothing after change-refs-to-local', () async {
          final project = scenario('succeed', folder: 'sample_folder_ts');

          expect(await refsOf(project), <String>[
            'test1_ts uses the published test2_ts instead of its checkout',
          ]);

          await localize(project);
          expect(await refsOf(project), isEmpty);
        });

        test('accepts a file: link to the sibling', () async {
          final project = scenario(
            'already_localized',
            folder: 'sample_folder_ts',
          );

          expect(await refsOf(project), isEmpty);
        });

        test('reports a link to a moved folder, '
            'nothing after change-refs-to-local', () async {
          final project = scenario(
            'legacy_moved_link',
            folder: 'sample_folder_ts',
          );

          expect(await refsOf(project), <String>[
            'test1_ts uses the published test2_ts instead of its checkout',
            'test1_ts uses the published test3_ts instead of its checkout',
          ]);

          await localize(project);
          expect(await refsOf(project), isEmpty);
        });
      });

      test('throws when there is no project root', () async {
        final dir = createTempDir('unlocalized_refs_no_root');
        workspaces.add(dir);

        await expectLater(
          refsOf(dir),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('No project root found'),
            ),
          ),
        );
      });
    });

    group('exec()', () {
      late CommandRunner<void> runner;

      setUp(() {
        runner = CommandRunner<void>('test', 'test')
          ..addCommand(UnlocalizedRefs(ggLog: messages.add));
      });

      test('logs one line per ref and throws', () async {
        final project = scenario('transitive');

        await expectLater(
          runner.run(<String>['unlocalized-refs', '-i', project.path]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('2 workspace ref(s) are not localized'),
            ),
          ),
        );
        expect(messages, <String>[
          'test1 uses the published test2 instead of its checkout',
          'test1 uses the published test3 instead of its checkout',
        ]);
      });

      test('logs success when everything is localized', () async {
        final project = scenario('already_localized');

        await runner.run(<String>['unlocalized-refs', '-i', project.path]);

        expect(messages, <String>['All workspace refs are localized.']);
      });
    });
  });
}

/// Returns path → content of every file below [dir].
Map<String, String> _snapshot(Directory dir) => <String, String>{
  for (final file in dir.listSync(recursive: true).whereType<File>())
    file.path: file.readAsStringSync(),
};
