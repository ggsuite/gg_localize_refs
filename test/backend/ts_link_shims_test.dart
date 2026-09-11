// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/ts_link_shims.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  const shims = TsLinkShims();
  late Directory workspace;
  late Directory project;
  late Directory dep;

  Directory shimDir([String name = 'dep_a']) => shims.shimDir(project, name);
  File shimPackageJson([String name = 'dep_a']) =>
      File(p.join(shimDir(name).path, 'package.json'));
  Link shimSrc([String name = 'dep_a']) =>
      Link(p.join(shimDir(name).path, 'src'));

  void writeDep({String type = 'module', bool withSource = true}) {
    File(p.join(dep.path, 'package.json'))
        .writeAsStringSync('{"name":"dep_a","version":"1.0.0","type":"$type"}');
    if (withSource) {
      File(p.join(dep.path, 'src', 'index.ts'))
        ..createSync(recursive: true)
        ..writeAsStringSync('export const a = 1;\n');
    }
  }

  setUp(() {
    workspace = createTempDir('ts_link_shims_test');
    project = Directory(p.join(workspace.path, 'project'))
      ..createSync(recursive: true);
    dep = Directory(p.join(workspace.path, 'dep_a'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    deleteDirs(<Directory>[workspace]);
  });

  group('TsLinkShims', () {
    test('root(), shimDir() and linkPath() agree on the location', () {
      expect(shims.root(project).path, p.join(project.path, '.gg', 'ts_links'));
      expect(
        shims.shimDir(project, 'dep_a').path,
        p.join(project.path, '.gg', 'ts_links', 'dep_a'),
      );
      // A scoped name becomes a nested folder, the shape pnpm uses too.
      expect(
        shims.shimDir(project, '@scope/pkg').path,
        p.join(project.path, '.gg', 'ts_links', '@scope', 'pkg'),
      );
      expect(TsLinkShims.linkPath('dep_a'), './.gg/ts_links/dep_a');
      expect(TsLinkShims.linkPath('@scope/pkg'), './.gg/ts_links/@scope/pkg');
    });

    test('hasSourceEntry() looks for src/index.ts', () {
      expect(TsLinkShims.hasSourceEntry(dep), isFalse);
      writeDep();
      expect(TsLinkShims.hasSourceEntry(dep), isTrue);
    });

    group('write()', () {
      test('creates the shim with a src link and a package.json', () {
        writeDep();
        final changed = shims.write(
          projectDir: project,
          name: 'dep_a',
          depDir: dep,
        );

        expect(changed, isTrue);
        expect(shimSrc().existsSync(), isTrue);
        expect(
          p.normalize(shimSrc().targetSync()),
          p.normalize(p.join(dep.absolute.path, 'src')),
        );
        // The link resolves to the sibling's source.
        expect(
          File(p.join(shimDir().path, 'src', 'index.ts')).readAsStringSync(),
          'export const a = 1;\n',
        );

        final manifest = jsonDecode(
          shimPackageJson().readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(manifest['name'], 'dep_a');
        expect(manifest['type'], 'module');
        expect(manifest['main'], './src/index.ts');
        expect(manifest['types'], './src/index.ts');
        expect(manifest['private'], isTrue);
        expect(shimPackageJson().readAsStringSync(), endsWith('}\n'));
      });

      test('is a no-op the second time', () {
        writeDep();
        shims.write(projectDir: project, name: 'dep_a', depDir: dep);
        expect(
          shims.write(projectDir: project, name: 'dep_a', depDir: dep),
          isFalse,
        );
      });

      test('copies the module type of the sibling', () {
        writeDep(type: 'commonjs');
        shims.write(projectDir: project, name: 'dep_a', depDir: dep);
        final manifest = jsonDecode(
          shimPackageJson().readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(manifest['type'], 'commonjs');
      });

      test('defaults to ES modules without or with a broken manifest', () {
        File(p.join(dep.path, 'src', 'index.ts'))
          ..createSync(recursive: true)
          ..writeAsStringSync('');
        shims.write(projectDir: project, name: 'dep_a', depDir: dep);
        expect(shimPackageJson().readAsStringSync(), contains('"module"'));

        File(p.join(dep.path, 'package.json')).writeAsStringSync('nope');
        shims.write(projectDir: project, name: 'dep_a', depDir: dep);
        expect(shimPackageJson().readAsStringSync(), contains('"module"'));

        File(p.join(dep.path, 'package.json'))
            .writeAsStringSync('{"name":"dep_a","type":5}');
        shims.write(projectDir: project, name: 'dep_a', depDir: dep);
        expect(shimPackageJson().readAsStringSync(), contains('"module"'));
      });

      test('repoints a src link that leads elsewhere', () {
        writeDep();
        final other = Directory(p.join(workspace.path, 'other', 'src'))
          ..createSync(recursive: true);
        shimDir().createSync(recursive: true);
        shimSrc().createSync(other.path);

        final changed = shims.write(
          projectDir: project,
          name: 'dep_a',
          depDir: dep,
        );

        expect(changed, isTrue);
        expect(
          p.normalize(shimSrc().targetSync()),
          p.normalize(p.join(dep.absolute.path, 'src')),
        );
      });

      test('replaces a folder or file sitting where the link belongs', () {
        writeDep();
        Directory(p.join(shimDir().path, 'src')).createSync(recursive: true);
        expect(
          shims.write(projectDir: project, name: 'dep_a', depDir: dep),
          isTrue,
        );
        expect(shimSrc().existsSync(), isTrue);

        shimSrc().deleteSync();
        File(p.join(shimDir().path, 'src')).writeAsStringSync('x');
        expect(
          shims.write(projectDir: project, name: 'dep_a', depDir: dep),
          isTrue,
        );
        expect(shimSrc().existsSync(), isTrue);
      });

      test('rewrites a package.json whose content differs', () {
        writeDep();
        shims.write(projectDir: project, name: 'dep_a', depDir: dep);
        shimPackageJson().writeAsStringSync('{}');
        expect(
          shims.write(projectDir: project, name: 'dep_a', depDir: dep),
          isTrue,
        );
        expect(
          shimPackageJson().readAsStringSync(),
          contains('./src/index.ts'),
        );
      });

      test('nests a scoped package below its scope folder', () {
        writeDep();
        shims.write(projectDir: project, name: '@scope/dep_a', depDir: dep);
        expect(shimPackageJson('@scope/dep_a').existsSync(), isTrue);
        expect(
          shimPackageJson('@scope/dep_a').readAsStringSync(),
          contains('"@scope/dep_a"'),
        );
      });
    });

    group('remove()', () {
      test('deletes the shim and reports whether it existed', () {
        writeDep();
        shims.write(projectDir: project, name: 'dep_a', depDir: dep);
        expect(shims.remove(projectDir: project, name: 'dep_a'), isTrue);
        expect(shimDir().existsSync(), isFalse);
        expect(shims.remove(projectDir: project, name: 'dep_a'), isFalse);
        // The sibling's source is untouched — only the link went.
        expect(File(p.join(dep.path, 'src', 'index.ts')).existsSync(), isTrue);
      });

      test('removes an emptied scope folder but keeps a shared one', () {
        writeDep();
        shims.write(projectDir: project, name: '@scope/dep_a', depDir: dep);
        shims.write(projectDir: project, name: '@scope/dep_b', depDir: dep);
        final scopeDir = Directory(p.join(shims.root(project).path, '@scope'));

        shims.remove(projectDir: project, name: '@scope/dep_a');
        expect(scopeDir.existsSync(), isTrue);

        shims.remove(projectDir: project, name: '@scope/dep_b');
        expect(scopeDir.existsSync(), isFalse);
        expect(shims.root(project).existsSync(), isTrue);
      });
    });

    group('removeAll()', () {
      test('deletes the whole ts_links folder', () {
        writeDep();
        shims.write(projectDir: project, name: 'dep_a', depDir: dep);
        shims.write(projectDir: project, name: '@scope/dep_b', depDir: dep);
        expect(shims.removeAll(project), isTrue);
        expect(shims.root(project).existsSync(), isFalse);
        expect(Directory(p.join(project.path, '.gg')).existsSync(), isTrue);
        expect(shims.removeAll(project), isFalse);
      });
    });

    group('shimNameOf()', () {
      String target(String relative) =>
          p.normalize(p.join(project.absolute.path, relative));

      test('reads the package name from the folder structure', () {
        expect(
          TsLinkShims.shimNameOf(
            projectDir: project,
            target: target('.gg/ts_links/dep_a'),
          ),
          'dep_a',
        );
        expect(
          TsLinkShims.shimNameOf(
            projectDir: project,
            target: target('.gg/ts_links/@scope/pkg'),
          ),
          '@scope/pkg',
        );
      });

      test('returns null for anything that is no shim folder', () {
        for (final relative in <String>[
          '../dep_a',
          '.gg',
          '.gg/ts_links',
          '.gg/other/dep_a',
          '.gg/ts_links/not_a_scope/pkg',
          '.gg/ts_links/@scope/pkg/src',
        ]) {
          expect(
            TsLinkShims.shimNameOf(
              projectDir: project,
              target: target(relative),
            ),
            isNull,
            reason: relative,
          );
        }
      });
    });
  });
}
