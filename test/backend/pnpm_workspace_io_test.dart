// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/pnpm_workspace_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  const io = PnpmWorkspaceIo();
  late Directory workspace;
  late Directory project;
  late Directory sibling;

  File workspaceYaml() => File(p.join(project.path, 'pnpm-workspace.yaml'));

  void writeSiblingManifest([String name = 'dep_a']) {
    File(
      p.join(sibling.path, 'package.json'),
    ).writeAsStringSync('{"name":"$name","version":"1.0.0"}');
  }

  setUp(() {
    workspace = createTempDir('pnpm_workspace_io_test');
    project = Directory(p.join(workspace.path, 'project'))
      ..createSync(recursive: true);
    sibling = Directory(p.join(workspace.path, 'dep_a'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    deleteDirs(<Directory>[workspace]);
  });

  group('PnpmWorkspaceIo', () {
    group('isPnpmManaged()', () {
      test('returns true when pnpm-lock.yaml exists', () {
        File(p.join(project.path, 'pnpm-lock.yaml')).writeAsStringSync('');
        expect(PnpmWorkspaceIo.isPnpmManaged(project), isTrue);
      });

      test('returns true when pnpm-workspace.yaml exists', () {
        workspaceYaml().writeAsStringSync('');
        expect(PnpmWorkspaceIo.isPnpmManaged(project), isTrue);
      });

      test('returns true for a pnpm packageManager field', () {
        File(p.join(project.path, 'package.json')).writeAsStringSync(
          '{"name":"x","packageManager":"pnpm@11.10.0+sha512.abc"}',
        );
        expect(PnpmWorkspaceIo.isPnpmManaged(project), isTrue);
      });

      test('returns false for a yarn packageManager field', () {
        File(
          p.join(project.path, 'package.json'),
        ).writeAsStringSync('{"name":"x","packageManager":"yarn@4.0.0"}');
        expect(PnpmWorkspaceIo.isPnpmManaged(project), isFalse);
      });

      test('returns false without any pnpm marker', () {
        File(
          p.join(project.path, 'package.json'),
        ).writeAsStringSync('{"name":"x"}');
        expect(PnpmWorkspaceIo.isPnpmManaged(project), isFalse);
      });

      test('returns false without a package.json', () {
        expect(PnpmWorkspaceIo.isPnpmManaged(project), isFalse);
      });

      test('returns false for an unparsable package.json', () {
        File(
          p.join(project.path, 'package.json'),
        ).writeAsStringSync('not json');
        expect(PnpmWorkspaceIo.isPnpmManaged(project), isFalse);
      });

      test('returns false for a non-map package.json', () {
        File(p.join(project.path, 'package.json')).writeAsStringSync('[]');
        expect(PnpmWorkspaceIo.isPnpmManaged(project), isFalse);
      });
    });

    group('hasLocalizedRefs()', () {
      test('returns false when the file is missing', () {
        expect(PnpmWorkspaceIo.hasLocalizedRefs(project), isFalse);
      });

      test('returns false for an empty file', () {
        workspaceYaml().writeAsStringSync('   \n');
        expect(PnpmWorkspaceIo.hasLocalizedRefs(project), isFalse);
      });

      test('returns true for an unparsable file', () {
        workspaceYaml().writeAsStringSync('overrides: [pnpm');
        expect(PnpmWorkspaceIo.hasLocalizedRefs(project), isTrue);
      });

      test('returns false for a non-map root', () {
        workspaceYaml().writeAsStringSync('- a\n- b\n');
        expect(PnpmWorkspaceIo.hasLocalizedRefs(project), isFalse);
      });

      test('returns false without an overrides section', () {
        workspaceYaml().writeAsStringSync('allowBuilds:\n  esbuild: true\n');
        expect(PnpmWorkspaceIo.hasLocalizedRefs(project), isFalse);
      });

      test('returns false when overrides hold only remote specs', () {
        workspaceYaml().writeAsStringSync(
          'overrides:\n'
          '  dep_a: ^1.0.0\n'
          '  dep_b: git+ssh://git@github.com/user/dep_b.git#main\n',
        );
        expect(PnpmWorkspaceIo.hasLocalizedRefs(project), isFalse);
      });

      test('returns true for a link: override', () {
        workspaceYaml().writeAsStringSync('overrides:\n  dep_a: link:../a\n');
        expect(PnpmWorkspaceIo.hasLocalizedRefs(project), isTrue);
      });

      test('returns true for a file: override', () {
        workspaceYaml().writeAsStringSync('overrides:\n  dep_a: file:../a\n');
        expect(PnpmWorkspaceIo.hasLocalizedRefs(project), isTrue);
      });
    });

    group('addLinkOverrides()', () {
      test('creates the file with the ownership header', () {
        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );

        expect(edit.isUnchanged, isFalse);
        expect(edit.content, startsWith(PnpmWorkspaceIo.headerComment));
        expect(edit.content, contains('dep_a: link:../dep_a'));
      });

      test('returns unchanged for an empty dependency map', () {
        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: const <String, String>{},
        );

        expect(edit.isUnchanged, isTrue);
      });

      test('merges into an existing settings file', () {
        workspaceYaml().writeAsStringSync(
          '# keep me\nallowBuilds:\n  esbuild: true\n',
        );

        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );

        expect(edit.content, contains('# keep me'));
        expect(edit.content, contains('allowBuilds'));
        expect(edit.content, contains('dep_a: link:../dep_a'));
        expect(edit.content, isNot(contains(PnpmWorkspaceIo.headerComment)));
      });

      test('returns unchanged when every override is already there', () {
        workspaceYaml().writeAsStringSync('overrides:\n  dep_a: link:../dep_a');

        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );

        expect(edit.isUnchanged, isTrue);
      });

      test('replaces a git override — the modes are mutually exclusive', () {
        workspaceYaml().writeAsStringSync(
          'overrides:\n  dep_a: git+ssh://git@github.com/u/dep_a.git#feat\n',
        );

        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );

        expect(edit.content, contains('dep_a: link:../dep_a'));
        expect(edit.content, isNot(contains('git+ssh')));
      });

      test('prunes an owned override whose dependency left the set', () {
        writeSiblingManifest();
        workspaceYaml().writeAsStringSync('overrides:\n  dep_a: link:../dep_a');

        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_b': '../dep_b'},
        );

        expect(edit.content, contains('dep_b: link:../dep_b'));
        expect(edit.content, isNot(contains('dep_a')));
      });

      test('prunes a dead link override pointing at a missing sibling', () {
        workspaceYaml().writeAsStringSync('overrides:\n  gone: link:../gone');

        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );

        expect(edit.content, isNot(contains('gone')));
      });

      test('keeps a hand written override for a foreign package', () {
        workspaceYaml().writeAsStringSync(
          'overrides:\n  vendored: link:../../vendor/x\n  pinned: ^2.0.0\n',
        );

        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );

        expect(edit.content, contains('vendored: link:../../vendor/x'));
        expect(edit.content, contains('pinned: ^2.0.0'));
      });

      test('writes the whole section when overrides is a scalar', () {
        workspaceYaml().writeAsStringSync('overrides:\n');

        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );

        expect(edit.content, contains('dep_a: link:../dep_a'));
      });

      test('rebuilds a comment-only file with the header', () {
        workspaceYaml().writeAsStringSync('# only a comment\n');

        final edit = io.addLinkOverrides(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );

        expect(edit.content, startsWith(PnpmWorkspaceIo.headerComment));
      });

      test('throws on an unparsable file', () {
        workspaceYaml().writeAsStringSync('overrides: [pnpm');

        expect(
          () => io.addLinkOverrides(
            projectDir: project,
            pathsByDependency: <String, String>{'dep_a': '../dep_a'},
          ),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('Cannot parse'),
            ),
          ),
        );
      });

      test('throws when the root is not a map', () {
        workspaceYaml().writeAsStringSync('- entry\n');

        expect(
          () => io.addLinkOverrides(
            projectDir: project,
            pathsByDependency: <String, String>{'dep_a': '../dep_a'},
          ),
          throwsA(
            isA<Exception>().having(
              (Object e) => e.toString(),
              'message',
              contains('expected a YAML map'),
            ),
          ),
        );
      });
    });

    group('addGitOverrides()', () {
      test('writes the git specs verbatim', () {
        final edit = io.addGitOverrides(
          projectDir: project,
          gitSpecsByDependency: <String, String>{
            'dep_a': 'git+ssh://git@github.com/u/dep_a.git#feat',
          },
        );

        expect(
          edit.content,
          contains('dep_a: git+ssh://git@github.com/u/dep_a.git#feat'),
        );
      });

      test('replaces a link override — the modes are mutually exclusive', () {
        workspaceYaml().writeAsStringSync('overrides:\n  dep_a: link:../dep_a');

        final edit = io.addGitOverrides(
          projectDir: project,
          gitSpecsByDependency: <String, String>{
            'dep_a': 'git+ssh://git@github.com/u/dep_a.git#feat',
          },
        );

        expect(edit.content, isNot(contains('link:')));
        expect(edit.content, contains('#feat'));
      });
    });

    group('removeOwnedOverrides()', () {
      test('returns unchanged when the file is missing', () {
        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.isUnchanged, isTrue);
      });

      test('deletes a file this package created once it is empty', () {
        workspaceYaml().writeAsStringSync(
          '${PnpmWorkspaceIo.headerComment}overrides:\n'
          '  dep_a: link:../dep_a\n',
        );

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.deleteFile, isTrue);
      });

      test('keeps a user settings file and only drops the section', () {
        workspaceYaml().writeAsStringSync(
          'allowBuilds:\n  esbuild: true\noverrides:\n  dep_a: link:../dep_a\n',
        );

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.deleteFile, isFalse);
        expect(edit.content, contains('allowBuilds'));
        expect(edit.content, isNot(contains('overrides')));
      });

      test('keeps foreign overrides and drops only the owned ones', () {
        writeSiblingManifest();
        workspaceYaml().writeAsStringSync(
          'overrides:\n'
          '  dep_a: link:../dep_a\n'
          '  gone: link:../gone\n'
          '  pinned: ^2.0.0\n'
          '  foreign_git: git+ssh://git@github.com/u/x.git#main\n',
        );

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_b'],
        );

        // dep_a is shape-owned (links the sibling of the same name), gone is
        // dead — both go. The hand written pin and the git ref of a foreign
        // package survive.
        expect(edit.content, isNot(contains('dep_a')));
        expect(edit.content, isNot(contains('gone')));
        expect(edit.content, contains('pinned: ^2.0.0'));
        expect(edit.content, contains('foreign_git'));
      });

      test('removes the git override of a workspace dependency', () {
        workspaceYaml().writeAsStringSync(
          'allowBuilds:\n  esbuild: true\n'
          'overrides:\n'
          '  dep_a: git+ssh://git@github.com/u/dep_a.git#feat\n',
        );

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.content, isNot(contains('git+ssh')));
        expect(edit.content, contains('allowBuilds'));
      });

      test('returns unchanged when nothing is owned', () {
        workspaceYaml().writeAsStringSync('overrides:\n  pinned: ^2.0.0\n');

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.isUnchanged, isTrue);
      });

      test('returns unchanged for a foreign file without overrides', () {
        workspaceYaml().writeAsStringSync('allowBuilds:\n  esbuild: true\n');

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.isUnchanged, isTrue);
      });

      test('deletes an own file whose overrides section is empty', () {
        workspaceYaml().writeAsStringSync(
          '${PnpmWorkspaceIo.headerComment}overrides:\n',
        );

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.deleteFile, isTrue);
      });

      test('keeps an own file while foreign overrides remain', () {
        writeSiblingManifest();
        workspaceYaml().writeAsStringSync(
          '${PnpmWorkspaceIo.headerComment}'
          'overrides:\n'
          '  dep_a: link:../dep_a\n'
          '  pinned: ^2.0.0\n',
        );

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.deleteFile, isFalse);
        expect(edit.content, contains('pinned: ^2.0.0'));
        expect(edit.content, isNot(contains('link:')));
      });

      test('keeps an own file that gained foreign settings', () {
        writeSiblingManifest();
        workspaceYaml().writeAsStringSync(
          '${PnpmWorkspaceIo.headerComment}'
          'allowBuilds:\n  esbuild: true\n'
          'overrides:\n  dep_a: link:../dep_a\n',
        );

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.deleteFile, isFalse);
        expect(edit.content, contains('allowBuilds'));
      });

      test('removes an entry naming a workspace dep with a link spec', () {
        // The link points somewhere else entirely — leaving local mode must
        // still drop it, because it shadows the published constraint.
        workspaceYaml().writeAsStringSync(
          'allowBuilds:\n  esbuild: true\n'
          'overrides:\n  dep_a: link:../../elsewhere/dep_a\n',
        );

        final edit = io.removeOwnedOverrides(
          projectDir: project,
          dependencyNames: const <String>['dep_a'],
        );

        expect(edit.content, isNot(contains('link:')));
      });
    });

    group('isOwnedLinkOverride()', () {
      test('recognizes a link to the sibling of the same package name', () {
        writeSiblingManifest();

        expect(
          io.isOwnedLinkOverride(
            projectDir: project,
            name: 'dep_a',
            value: 'link:../dep_a',
          ),
          isTrue,
        );
      });

      test('rejects a non-string value', () {
        expect(
          io.isOwnedLinkOverride(projectDir: project, name: 'dep_a', value: 1),
          isFalse,
        );
      });

      test('rejects a link whose sibling has another package name', () {
        writeSiblingManifest('other_name');

        expect(
          io.isOwnedLinkOverride(
            projectDir: project,
            name: 'dep_a',
            value: 'link:../dep_a',
          ),
          isFalse,
        );
      });

      test('rejects a link whose sibling has no package.json', () {
        expect(
          io.isOwnedLinkOverride(
            projectDir: project,
            name: 'dep_a',
            value: 'link:../dep_a',
          ),
          isFalse,
        );
      });

      test('rejects a link whose sibling manifest is unparsable', () {
        File(
          p.join(sibling.path, 'package.json'),
        ).writeAsStringSync('not json');

        expect(
          io.isOwnedLinkOverride(
            projectDir: project,
            name: 'dep_a',
            value: 'link:../dep_a',
          ),
          isFalse,
        );
      });

      test('rejects a link reaching beyond the siblings', () {
        expect(
          io.isOwnedLinkOverride(
            projectDir: project,
            name: 'dep_a',
            value: 'link:../../vendor/dep_a',
          ),
          isFalse,
        );
      });
    });
  });
}
