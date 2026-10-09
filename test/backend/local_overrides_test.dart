// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/local_overrides.dart';
import 'package:gg_localize_refs/src/backend/process_dependencies.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  const overrides = LocalOverrides();
  final workspaces = <Directory>[];

  /// Copies the scenario [name] of [folder] and returns the root node of its
  /// `project1`.
  Future<ProjectNode> rootOf(String name, String folder) async {
    final workspace = createTempDir('local_overrides_$name');
    workspaces.add(workspace);
    copyDirectory(
      Directory(p.join('test', folder, 'localize_refs', name)),
      workspace,
    );
    final graphs = await buildRootGraphs(
      directory: Directory(p.join(workspace.path, 'project1')),
      ggLog: (_) {},
    );
    return graphs.single.rootNode;
  }

  tearDown(() {
    deleteDirs(workspaces);
    workspaces.clear();
  });

  group('LocalOverrides', () {
    group('dartPaths()', () {
      test('returns a relative path per transitive dependency', () async {
        final node = await rootOf('transitive', 'sample_folder');

        expect(overrides.dartPaths(node), <String, String>{
          'test2': '../project2',
          'test3': '../project3',
        });
      });
    });

    group('pnpmLinkPaths()', () {
      test('links a sibling without sources directly', () async {
        final node = await rootOf('pnpm_succeed', 'sample_folder_ts');

        expect(overrides.pnpmLinkPaths(node), <String, String>{
          'test2_ts': '../project2',
        });
      });

      test('links a sibling with sources through its shim, '
          'without writing the shim', () async {
        final node = await rootOf('pnpm_with_sources', 'sample_folder_ts');

        expect(overrides.pnpmLinkPaths(node), <String, String>{
          'test2_ts': './.gg/ts_links/test2_ts',
        });
        expect(
          Directory(p.join(node.directory.path, '.gg')).existsSync(),
          isFalse,
        );
      });
    });

    group('npmLinkSpecs()', () {
      test('returns a link per direct dependency', () async {
        final node = await rootOf('succeed', 'sample_folder_ts');

        expect(overrides.npmLinkSpecs(node), <String, String>{
          'test2_ts': 'link:../project2',
        });
      });
    });

    group('unlinkedNpmDependencies()', () {
      /// Returns the unlinked dependencies of [node] after writing [spec]
      /// as its `test2_ts` dependency.
      Future<List<String>> unlinkedWith(ProjectNode node, String spec) async {
        File(p.join(node.directory.path, 'package.json')).writeAsStringSync(
          '{"name":"test1_ts","version":"1.0.0",'
          '"dependencies":{"test2_ts":"$spec"}}',
        );
        final manifest = await node.language.readManifest(node.directory);
        return overrides.unlinkedNpmDependencies(
          node: node,
          references: node.language.listDependencyReferences(manifest.parsed),
        );
      }

      test('names a registry spec and a link to another folder', () async {
        final node = await rootOf('succeed', 'sample_folder_ts');

        expect(await unlinkedWith(node, '^1.0.0'), <String>['test2_ts']);
        expect(await unlinkedWith(node, 'link:../moved/project2'), <String>[
          'test2_ts',
        ]);
      });

      test('accepts a link: or file: to the sibling', () async {
        final node = await rootOf('succeed', 'sample_folder_ts');

        expect(await unlinkedWith(node, 'link:../project2'), isEmpty);
        expect(await unlinkedWith(node, 'file:../project2/'), isEmpty);
      });

      test('ignores a dependency the manifest does not name', () async {
        final node = await rootOf('succeed', 'sample_folder_ts');

        expect(
          overrides.unlinkedNpmDependencies(
            node: node,
            references: const <String, DependencyReference>{},
          ),
          isEmpty,
        );
      });
    });
  });
}
