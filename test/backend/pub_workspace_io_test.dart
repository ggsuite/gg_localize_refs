// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/pub_workspace_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../test_helpers.dart';

void main() {
  const io = PubWorkspaceIo();

  Directory projectDir = Directory('');

  setUp(() {
    projectDir = createTempDir('pub_workspace_io', 'project1');
  });

  tearDown(() {
    deleteDirs(<Directory>[projectDir.parent]);
  });

  /// Writes [content] to [relative] below [projectDir] and returns the file.
  File write(String relative, String content) {
    return File(p.joinAll(<String>[projectDir.path, ...relative.split('/')]))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// The pubspec of a root package with the SDK constraint [sdk].
  String rootPubspec({String sdk = '^3.6.0', String extra = ''}) =>
      'name: test1\n'
      'version: 1.0.0\n'
      'environment:\n'
      '  sdk: $sdk\n'
      'dependencies:\n'
      '  test2: ^1.0.0\n'
      '$extra';

  /// The pubspec of an embedded package that depends on the root through
  /// `path: ..`.
  String memberPubspec({String sdk = '^3.6.0', String extra = ''}) =>
      'name: test1_example\n'
      'publish_to: none\n'
      'environment:\n'
      '  sdk: $sdk\n'
      'dependencies:\n'
      '  test1:\n'
      '    path: ..\n'
      '$extra';

  /// Joins the embedded packages of [projectDir] into the workspace of the
  /// root pubspec [root].
  PubWorkspaceJoin join(
    String root, {
    Iterable<String> overriddenNames = const <String>[],
  }) {
    return io.join(
      projectDir: projectDir,
      pubspecContent: root,
      overriddenNames: overriddenNames,
    );
  }

  group('PubWorkspaceIo', () {
    group('embeddedPackages()', () {
      test('finds packages that depend on the project through a path', () {
        write('example/pubspec.yaml', memberPubspec());
        write(
          'tool/bench/pubspec.yaml',
          'name: bench\n'
              'dev_dependencies:\n'
              '  test1:\n'
              '    path: ../..\n',
        );

        expect(
          io.embeddedPackages(projectDir).map((d) => d.directory.path),
          <String>[
            p.join(projectDir.path, 'example'),
            p.join(projectDir.path, 'tool', 'bench'),
          ]..sort(),
        );
      });

      test('ignores packages that do not point back at the project', () {
        // A test fixture with a path dependency of its own.
        write(
          'tool/sample/pubspec.yaml',
          'name: fixture\n'
              'dependencies:\n'
              '  other:\n'
              '    path: ../other\n'
              '  hosted: ^1.0.0\n'
              'dev_dependencies: none\n',
        );
        // Not a map, unparsable and without any pubspec at all.
        write('tool/list/pubspec.yaml', '- a\n- b\n');
        write('tool/broken/pubspec.yaml', 'name: [\n');
        Directory(p.join(projectDir.path, 'lib')).createSync();
        write('README.md', '# test1\n');

        expect(io.embeddedPackages(projectDir), isEmpty);
      });

      test('does not search hidden directories, build, node_modules and '
          'test', () {
        for (final dir in <String>[
          '.dart_tool',
          'build',
          'node_modules',
          'test',
        ]) {
          write('$dir/example/pubspec.yaml', memberPubspec());
        }

        expect(io.embeddedPackages(projectDir), isEmpty);
      });
    });

    group('join()', () {
      test('is unchanged without embedded packages', () {
        final result = join(rootPubspec());

        expect(result.joined, isEmpty);
        expect(result.rootContent, isNull);
        expect(result.memberContents, isEmpty);
        expect(result.skipped, isEmpty);
      });

      test('adds the member to a new workspace list and sets its '
          'resolution', () {
        final member = write('example/pubspec.yaml', memberPubspec());

        final result = join(rootPubspec());

        expect(result.joined, <String>['example']);
        expect(result.skipped, isEmpty);

        final root = loadYaml(result.rootContent!) as Map;
        expect(root['workspace'], <String>['example']);
        expect(root['dependencies'], <String, String>{'test2': '^1.0.0'});
        expect(result.rootContent, endsWith('\n'));

        final memberContent = result.memberContents[member.path]!;
        expect((loadYaml(memberContent) as Map)['resolution'], 'workspace');
        expect(memberContent, startsWith(memberPubspec()));
      });

      test('appends to an existing workspace list', () {
        write('example/pubspec.yaml', memberPubspec());
        Directory(p.join(projectDir.path, 'packages', 'a'))
            .createSync(recursive: true);

        final result = join(
          rootPubspec(extra: 'workspace:\n  - packages/a\n  - 42\n'),
        );

        final root = loadYaml(result.rootContent!) as Map;
        expect(root['workspace'], <Object>['packages/a', 42, 'example']);
      });

      test('recognizes a member a glob of the workspace list covers', () {
        write(
          'packages/app/pubspec.yaml',
          memberPubspec().replaceFirst('path: ..', 'path: ../..'),
        );
        write('example/pubspec.yaml', memberPubspec());

        final result = join(rootPubspec(extra: 'workspace:\n  - packages/*\n'));

        expect(result.joined, <String>['example', 'packages/app']);
        expect((loadYaml(result.rootContent!) as Map)['workspace'], <String>[
          'packages/*',
          'example',
        ]);
      });

      test('adds a trailing newline to content that has none', () {
        final member = write(
          'example/pubspec.yaml',
          memberPubspec().trimRight(),
        );

        final result = join(rootPubspec().trimRight());

        expect(result.rootContent, endsWith('\n'));
        expect(result.memberContents[member.path], endsWith('\n'));
      });

      test('leaves a member alone that is already joined', () {
        write(
          'example/pubspec.yaml',
          memberPubspec(extra: 'resolution: workspace\n'),
        );

        final result = join(rootPubspec(extra: 'workspace:\n  - ./example/\n'));

        expect(result.joined, isEmpty);
        expect(result.rootContent, isNull);
        expect(result.memberContents, isEmpty);
      });

      test('only lists a member that already declares its resolution', () {
        write(
          'example/pubspec.yaml',
          memberPubspec(extra: 'resolution: workspace\n'),
        );

        final result = join(rootPubspec());

        expect(result.joined, <String>['example']);
        expect(result.memberContents, isEmpty);
        expect((loadYaml(result.rootContent!) as Map)['workspace'], <String>[
          'example',
        ]);
      });

      test('only sets the resolution of a member that is listed already', () {
        final member = write('example/pubspec.yaml', memberPubspec());

        final result = join(rootPubspec(extra: 'workspace:\n  - example\n'));

        expect(result.joined, <String>['example']);
        expect(result.rootContent, isNull);
        expect(result.memberContents.keys, <String>[member.path]);
      });

      group('skips a member', () {
        void expectSkipped(PubWorkspaceJoin result, String reason) {
          expect(result.joined, isEmpty);
          expect(result.rootContent, isNull);
          expect(result.memberContents, isEmpty);
          expect(result.skipped.single, contains('Cannot make example'));
          expect(result.skipped.single, contains(reason));
        }

        test('with a resolution other than workspace', () {
          write(
            'example/pubspec.yaml',
            memberPubspec(extra: 'resolution: external\n'),
          );

          expectSkipped(join(rootPubspec()), 'resolution: external');
        });

        test('when the root allows Dart below 3.6', () {
          write('example/pubspec.yaml', memberPubspec());

          expectSkipped(
            join(rootPubspec(sdk: "'>=3.0.0 <4.0.0'")),
            'SDK constraint of pubspec.yaml allows Dart below 3.6.0',
          );
        });

        test('when the root declares no or an unparsable SDK', () {
          write('example/pubspec.yaml', memberPubspec());

          expectSkipped(
            join('name: test1\nversion: 1.0.0\n'),
            'SDK constraint of pubspec.yaml',
          );
          expectSkipped(
            join(rootPubspec(sdk: 'not-a-version')),
            'SDK constraint of pubspec.yaml',
          );
        });

        test('when the member allows Dart below 3.6', () {
          write('example/pubspec.yaml', memberPubspec(sdk: '^3.5.0'));

          expectSkipped(
            join(rootPubspec()),
            'SDK constraint of example/pubspec.yaml allows Dart below',
          );
        });

        test('that needs Flutter in a package that does not', () {
          write(
            'example/pubspec.yaml',
            memberPubspec(extra: '  flutter:\n    sdk: flutter\n'),
          );

          expectSkipped(join(rootPubspec()), 'it needs Flutter');
        });

        test('whose version constraints contradict the root', () {
          write(
            'example/pubspec.yaml',
            memberPubspec(extra: '  test2: ^2.0.0\n'),
          );

          expectSkipped(
            join(rootPubspec(extra: 'dev_dependencies:\n  lints: ^6.0.0\n')),
            'its version constraints of test2 contradict those of pubspec.yaml',
          );
        });

        test('that overrides a dependency the root overrides too', () {
          write(
            'example/pubspec.yaml',
            memberPubspec(
              extra:
                  'dependency_overrides:\n'
                  '  test2:\n'
                  '    path: ../../project2\n',
            ),
          );
          write(
            'example/pubspec_overrides.yaml',
            'dependency_overrides:\n'
                '  pinned: 1.0.0\n',
          );
          write(
            'pubspec_overrides.yaml',
            'dependency_overrides:\n'
                '  pinned: 1.0.1\n',
          );

          expectSkipped(
            join(rootPubspec(), overriddenNames: <String>['test2']),
            'it overrides pinned, test2 itself',
          );
        });
      });

      test('joins a Flutter member of a Flutter package', () {
        write(
          'example/pubspec.yaml',
          memberPubspec(extra: '  flutter:\n    sdk: flutter\n'),
        );

        final result = join(
          rootPubspec(extra: '  flutter:\n    sdk: flutter\n'),
        );

        expect(result.joined, <String>['example']);
      });

      test('joins a member whose version constraints fit the root', () {
        write(
          'example/pubspec.yaml',
          memberPubspec(
            extra:
                '  test2:\n'
                '    version: ">=1.2.0 <2.0.0"\n'
                '  broken: not-a-version\n'
                '  local:\n'
                '    path: ../local\n'
                'dev_dependencies: none\n',
          ),
        );

        final result = join(rootPubspec());

        expect(result.joined, <String>['example']);
        expect(result.skipped, isEmpty);
      });

      test('joins a member whose overrides do not collide', () {
        write(
          'example/pubspec.yaml',
          memberPubspec(extra: 'dependency_overrides: null\n'),
        );
        write(
          'example/pubspec_overrides.yaml',
          'dependency_overrides:\n'
              '  pinned: 1.0.0\n',
        );

        final result = join(rootPubspec(), overriddenNames: <String>['test2']);

        expect(result.joined, <String>['example']);
        expect(result.skipped, isEmpty);
      });
    });
  });
}
