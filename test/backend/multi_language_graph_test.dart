// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/multi_language_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('MultiLanguageGraph', () {
    late List<Directory> tempDirs;

    setUp(() {
      tempDirs = <Directory>[];
    });

    tearDown(() {
      deleteDirs(tempDirs);
    });

    Directory createWorkspace(String suffix) {
      final dir = createTempDir(suffix, 'workspace');
      tempDirs.add(dir);
      return dir;
    }

    test('throws when no project root was found', () async {
      final workspace = createWorkspace('mlg_no_root');

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[
          DartProjectLanguage(),
          TypeScriptProjectLanguage(),
        ],
      );

      await expectLater(
        graph.buildGraph(directory: workspace),
        throwsA(
          isA<Exception>().having(
            (Object e) => e.toString(),
            'message',
            contains('No project root found'),
          ),
        ),
      );
    });

    test('builds dependency graph for a Dart workspace', () async {
      final workspace = createWorkspace('mlg_dart_ws');
      final source = Directory(
        p.join('test', 'sample_folder', 'process_dependencies', 'succeed'),
      );
      copyDirectory(source, workspace);

      final project1 = Directory(p.join(workspace.path, 'project1'));

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[DartProjectLanguage()],
      );

      final result = await graph.buildGraph(directory: project1);
      final root = result.rootNode;
      final all = result.allNodes;

      expect(root.name, 'test1');
      expect(root.directory.path, project1.path);
      expect(all.keys, containsAll(<String>['test1', 'test2']));

      final node1 = all['test1']!;
      final node2 = all['test2']!;

      expect(node1.dependencies['test2'], same(node2));
      expect(node2.dependents['test1'], same(node1));
    });

    test(
      'builds dependency graph when starting directory ends with dot',
      () async {
        final workspace = createWorkspace('mlg_dart_ws_with_dot');
        final source = Directory(
          p.join('test', 'sample_folder', 'process_dependencies', 'succeed'),
        );
        copyDirectory(source, workspace);

        final project1 = Directory(p.join(workspace.path, 'project1'));
        final startDir = Directory(p.join(project1.path, '.'));

        final graph = MultiLanguageGraph(
          languages: <ProjectLanguage>[DartProjectLanguage()],
        );

        final result = await graph.buildGraph(directory: startDir);
        final root = result.rootNode;

        expect(root.name, 'test1');
        expect(root.directory.path, project1.path);
      },
    );

    test(
      'builds dependency graph when starting directory ends with slash',
      () async {
        final workspace = createWorkspace('mlg_dart_ws_with_slash');
        final source = Directory(
          p.join('test', 'sample_folder', 'process_dependencies', 'succeed'),
        );
        copyDirectory(source, workspace);

        final project1 = Directory(p.join(workspace.path, 'project1'));
        final startDir = Directory('${project1.path}${Platform.pathSeparator}');

        final graph = MultiLanguageGraph(
          languages: <ProjectLanguage>[DartProjectLanguage()],
        );

        final result = await graph.buildGraph(directory: startDir);
        final root = result.rootNode;

        expect(root.name, 'test1');
        expect(root.directory.path, project1.path);
      },
    );

    test('builds dependency graph for a TypeScript workspace', () async {
      final workspace = createWorkspace('mlg_ts_ws');
      final source = Directory(
        p.join('test', 'sample_folder_ts', 'localize_refs', 'succeed'),
      );
      copyDirectory(source, workspace);

      final project1 = Directory(p.join(workspace.path, 'project1'));

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[TypeScriptProjectLanguage()],
      );

      final result = await graph.buildGraph(directory: project1);
      final root = result.rootNode;
      final all = result.allNodes;

      expect(root.name, 'test1_ts');
      expect(root.directory.path, project1.path);
      expect(all.keys, containsAll(<String>['test1_ts', 'test2_ts']));

      final node1 = all['test1_ts']!;
      final node2 = all['test2_ts']!;

      expect(node1.dependencies['test2_ts'], same(node2));
      expect(node2.dependents['test1_ts'], same(node1));
    });

    test('throws when circular dependencies are detected', () async {
      final workspace = createWorkspace('mlg_circular');
      final p1 = Directory(p.join(workspace.path, 'p1'));
      final p2 = Directory(p.join(workspace.path, 'p2'));
      await createDirs(<Directory>[p1, p2]);

      File(p.join(p1.path, 'pubspec.yaml')).writeAsStringSync(
        'name: p1\n'
        'version: 1.0.0\n'
        'dependencies:\n'
        '  p2: ^1.0.0\n',
      );
      File(p.join(p2.path, 'pubspec.yaml')).writeAsStringSync(
        'name: p2\n'
        'version: 1.0.0\n'
        'dependencies:\n'
        '  p1: ^1.0.0\n',
      );

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[DartProjectLanguage()],
      );

      await expectLater(
        graph.buildGraph(directory: p1),
        throwsA(
          isA<Exception>().having(
            (Object e) => e.toString(),
            'message',
            allOf(
              contains('Please remove circular dependency'),
              contains('p1 -> p2 -> p1'),
            ),
          ),
        ),
      );
    });

    test('throws when duplicate package names exist in workspace', () async {
      final workspace = createWorkspace('mlg_duplicate');
      final p1 = Directory(p.join(workspace.path, 'pkg1'));
      final p2 = Directory(p.join(workspace.path, 'pkg2'));
      await createDirs(<Directory>[p1, p2]);

      File(
        p.join(p1.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: shared\nversion: 1.0.0\n');
      File(
        p.join(p2.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: shared\nversion: 2.0.0\n');

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[DartProjectLanguage()],
      );

      await expectLater(
        graph.buildGraph(directory: p1),
        throwsA(
          isA<Exception>().having(
            (Object e) => e.toString(),
            'message',
            contains('Duplicate package name: shared'),
          ),
        ),
      );
    });

    test('throws when root node directory is not found among nodes', () async {
      final workspace = createWorkspace('mlg_root_not_found');
      final rootProject = Directory(p.join(workspace.path, 'root_project'));
      await createDirs(<Directory>[rootProject]);

      final manifestFile = File(p.join(rootProject.path, 'fake.yaml'));
      manifestFile.writeAsStringSync('name: root\n');

      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[_FakeLanguageMissingRootNode()],
      );

      await expectLater(
        graph.buildGraph(directory: rootProject),
        throwsA(
          isA<Exception>().having(
            (Object e) => e.toString(),
            'message',
            allOf(
              contains('The node for the package'),
              contains('was not found'),
            ),
          ),
        ),
      );
    });

    MultiLanguageGraph dualGraph() => MultiLanguageGraph(
      languages: <ProjectLanguage>[
        DartProjectLanguage(),
        TypeScriptProjectLanguage(),
      ],
    );

    Directory createBridge(String suffix) {
      final workspace = createWorkspace(suffix);
      final bridge = Directory(p.join(workspace.path, 'bridge'));
      bridge.createSync(recursive: true);
      File(
        p.join(bridge.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: bridge_dart\nversion: 1.0.0\n');
      File(
        p.join(bridge.path, 'package.json'),
      ).writeAsStringSync('{"name":"bridge","version":"1.0.0"}');
      File(p.join(bridge.path, 'tsconfig.json')).writeAsStringSync('{}');
      return bridge;
    }

    group('findRootAndLanguages', () {
      test('returns both languages for a cross-language bridge', () async {
        final bridge = createBridge('mlg_bridge_root');

        final root = await dualGraph().findRootAndLanguages(bridge);

        expect(root, isNotNull);
        expect(root!.$1.path, bridge.path);
        expect(
          root.$2.map((ProjectLanguage l) => l.id),
          containsAll(<ProjectLanguageId>[
            ProjectLanguageId.dart,
            ProjectLanguageId.typescript,
          ]),
        );
      });

      test('returns a single language for a pure Dart project', () async {
        final workspace = createWorkspace('mlg_dart_root');
        final project = Directory(p.join(workspace.path, 'project'));
        await createDirs(<Directory>[project]);
        File(
          p.join(project.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: only_dart\nversion: 1.0.0\n');

        final root = await dualGraph().findRootAndLanguages(project);

        expect(root, isNotNull);
        expect(root!.$2.map((ProjectLanguage l) => l.id), <ProjectLanguageId>[
          ProjectLanguageId.dart,
        ]);
      });

      test('returns null when no project root is found', () async {
        final workspace = createWorkspace('mlg_no_root2');

        final root = await dualGraph().findRootAndLanguages(workspace);

        expect(root, isNull);
      });
    });

    test('builds the graph for an explicit language (forLanguage)', () async {
      final bridge = createBridge('mlg_for_language');

      // Pin TypeScript even though Dart would win auto-detection.
      final result = await dualGraph().buildGraph(
        directory: bridge,
        forLanguage: TypeScriptProjectLanguage(),
      );

      expect(result.rootNode.name, 'bridge');
      expect(result.rootNode.language.id, ProjectLanguageId.typescript);
    });

    group('organization folders', () {
      // Builds `<workspace>/<org>/<project>` for every entry of [byOrg] and
      // returns the workspace. [marker] is the file that identifies the
      // workspace root ('ticket.json'), or null for a plain folder.
      Directory createOrgWorkspace(
        String suffix,
        Map<String, List<String>> byOrg, {
        String? marker,
      }) {
        final workspace = createWorkspace(suffix);
        if (marker != null) {
          File(p.join(workspace.path, marker)).writeAsStringSync('{}');
        }
        for (final org in byOrg.entries) {
          for (final project in org.value) {
            final dir = Directory(p.join(workspace.path, org.key, project));
            dir.createSync(recursive: true);
            copyDirectory(
              Directory(
                p.join(
                  'test',
                  'sample_folder',
                  'process_dependencies',
                  'succeed',
                  project,
                ),
              ),
              dir,
            );
          }
        }
        return workspace;
      }

      test('finds the siblings of the same organization', () async {
        final workspace = createOrgWorkspace(
          'mlg_orgs_same',
          <String, List<String>>{
            'org_a': <String>['project1', 'project2'],
          },
          marker: 'ticket.json',
        );
        final project1 = Directory(p.join(workspace.path, 'org_a', 'project1'));

        final result = await MultiLanguageGraph(
          languages: <ProjectLanguage>[DartProjectLanguage()],
        ).buildGraph(directory: project1);

        expect(result.rootNode.name, 'test1');
        expect(result.allNodes.keys, containsAll(<String>['test1', 'test2']));
      });

      test('links projects across organization folders', () async {
        final workspace = createOrgWorkspace(
          'mlg_orgs_cross',
          <String, List<String>>{
            'org_a': <String>['project1'],
            'org_b': <String>['project2'],
          },
          marker: 'ticket.json',
        );
        final project1 = Directory(p.join(workspace.path, 'org_a', 'project1'));

        final result = await MultiLanguageGraph(
          languages: <ProjectLanguage>[DartProjectLanguage()],
        ).buildGraph(directory: project1);

        final node1 = result.allNodes['test1']!;
        final node2 = result.allNodes['test2']!;
        expect(node1.dependencies['test2'], same(node2));
        expect(node2.dependents['test1'], same(node1));
        expect(
          node2.directory.path,
          p.join(workspace.path, 'org_b', 'project2'),
        );
      });

      test('recognizes the ocean by its folder name', () async {
        final parent = createWorkspace('mlg_orgs_ocean');
        final ocean = Directory(p.join(parent.path, '.ocean'))..createSync();
        for (final entry in <String, String>{
          'org_a': 'project1',
          'org_b': 'project2',
        }.entries) {
          final dir = Directory(p.join(ocean.path, entry.key, entry.value))
            ..createSync(recursive: true);
          copyDirectory(
            Directory(
              p.join(
                'test',
                'sample_folder',
                'process_dependencies',
                'succeed',
                entry.value,
              ),
            ),
            dir,
          );
        }

        final result =
            await MultiLanguageGraph(
              languages: <ProjectLanguage>[DartProjectLanguage()],
            ).buildGraph(
              directory: Directory(p.join(ocean.path, 'org_a', 'project1')),
            );

        expect(result.allNodes.keys, containsAll(<String>['test1', 'test2']));
      });

      test(
        'recognizes a legacy ».master« workspace by its folder name',
        () async {
          final parent = createWorkspace('mlg_orgs_legacy_master');
          final legacy = Directory(p.join(parent.path, '.master'))
            ..createSync();
          for (final entry in <String, String>{
            'org_a': 'project1',
            'org_b': 'project2',
          }.entries) {
            final dir = Directory(p.join(legacy.path, entry.key, entry.value))
              ..createSync(recursive: true);
            copyDirectory(
              Directory(
                p.join(
                  'test',
                  'sample_folder',
                  'process_dependencies',
                  'succeed',
                  entry.value,
                ),
              ),
              dir,
            );
          }

          final result =
              await MultiLanguageGraph(
                languages: <ProjectLanguage>[DartProjectLanguage()],
              ).buildGraph(
                directory: Directory(p.join(legacy.path, 'org_a', 'project1')),
              );

          expect(result.allNodes.keys, containsAll(<String>['test1', 'test2']));
        },
      );

      test('keeps a plain folder of siblings scoped to its parent', () async {
        // Without a workspace marker the parent stays the workspace root, so
        // a project next to the parent is not pulled in.
        final workspace = createOrgWorkspace(
          'mlg_orgs_unmarked',
          <String, List<String>>{
            'org_a': <String>['project1'],
            'org_b': <String>['project2'],
          },
        );
        final project1 = Directory(p.join(workspace.path, 'org_a', 'project1'));

        final result = await MultiLanguageGraph(
          languages: <ProjectLanguage>[DartProjectLanguage()],
        ).buildGraph(directory: project1);

        expect(result.allNodes.keys, <String>['test1']);
      });

      test('does not descend into a project', () async {
        final workspace = createOrgWorkspace(
          'mlg_orgs_nested',
          <String, List<String>>{
            'org_a': <String>['project1', 'project2'],
          },
          marker: 'ticket.json',
        );
        // A package inside a project must not become a workspace sibling.
        final example = Directory(
          p.join(workspace.path, 'org_a', 'project2', 'example'),
        )..createSync(recursive: true);
        File(
          p.join(example.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test2_example\nversion: 1.0.0\n');

        final result =
            await MultiLanguageGraph(
              languages: <ProjectLanguage>[DartProjectLanguage()],
            ).buildGraph(
              directory: Directory(p.join(workspace.path, 'org_a', 'project1')),
            );

        expect(result.allNodes.keys, isNot(contains('test2_example')));
      });
    });
  });
}

/// Fake language that returns nodes with a directory different from
/// the one passed into [createNode]. This allows testing the error
/// path where the root node cannot be found by directory.
class _FakeLanguageMissingRootNode extends ProjectLanguage {
  @override
  ProjectLanguageId get id => ProjectLanguageId.dart;

  @override
  String get manifestFileName => 'fake.yaml';

  @override
  bool isProjectRoot(Directory directory) {
    final file = File('${directory.path}/$manifestFileName');
    return file.existsSync();
  }

  @override
  Future<ProjectNode> createNode(Directory directory) async {
    final wrongDir = Directory('${directory.path}_other');
    return ProjectNode(
      name: 'fake_${directory.path.split(Platform.pathSeparator).last}',
      directory: wrongDir,
      language: this,
    );
  }

  @override
  Future<Map<String, String>> readDeclaredDependencies(ProjectNode node) async {
    return <String, String>{};
  }

  @override
  dynamic parseManifestContent(String content) {
    return <String, dynamic>{};
  }

  @override
  bool hasAnyDependencies(dynamic manifest) {
    return false;
  }

  @override
  bool hasAnyDependencyEntries(dynamic manifest) {
    return false;
  }

  @override
  DependencyReference? findDependency(dynamic manifest, String dependencyName) {
    return null;
  }

  @override
  Map<String, DependencyReference> listDependencyReferences(dynamic manifest) {
    return <String, DependencyReference>{};
  }

  @override
  String? readPackageVersion(dynamic manifest) {
    return null;
  }

  @override
  String stringifyDependencyForReading(dynamic dependencyValue) {
    return dependencyValue.toString();
  }

  @override
  String replaceDependencyInContent({
    required String manifestContent,
    required DependencyReference reference,
    required String newValue,
  }) {
    return manifestContent;
  }

  @override
  String stringifyManifest(dynamic manifest) {
    return '';
  }
}
