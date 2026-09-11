// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/backend/tsconfig_workspace_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  const io = TsconfigWorkspaceIo();
  late Directory workspace;
  late Directory project;
  late Directory sibling;

  File tsconfig() => File(p.join(project.path, 'tsconfig.json'));
  File workspaceJson() => File(p.join(project.path, 'tsconfig.workspace.json'));

  void writeExtendingTsconfig() {
    tsconfig().writeAsStringSync(
      '{\n'
      '  "extends": "./tsconfig.workspace.json",\n'
      '  "compilerOptions": {\n'
      '    /* Distribution */\n'
      '    "rootDir": "../..", // sibling checkouts may join the program\n'
      '    "outDir": "dist/",\n'
      '  },\n'
      '  "include": ["./src/"],\n'
      '}\n',
    );
  }

  void writeSibling({String name = 'dep_a', bool withSource = true}) {
    File(p.join(sibling.path, 'package.json'))
        .writeAsStringSync('{"name":"$name","version":"1.0.0"}');
    if (withSource) {
      File(p.join(sibling.path, 'src', 'index.ts'))
        ..createSync(recursive: true)
        ..writeAsStringSync('export const a = 1;\n');
    }
  }

  Map<String, dynamic> readWorkspaceJson() =>
      jsonDecode(workspaceJson().readAsStringSync()) as Map<String, dynamic>;

  setUp(() {
    workspace = createTempDir('tsconfig_workspace_io_test');
    project = Directory(p.join(workspace.path, 'project'))
      ..createSync(recursive: true);
    sibling = Directory(p.join(workspace.path, 'dep_a'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    deleteDirs(<Directory>[workspace]);
  });

  group('parseJsonc()', () {
    test('parses plain JSON', () {
      expect(parseJsonc('{"a": [1, 2]}'), <String, dynamic>{
        'a': <dynamic>[1, 2],
      });
    });

    test('drops line and block comments and trailing commas', () {
      final parsed = parseJsonc(
        '{\n'
        '  // a line comment\n'
        '  "a": 1, /* a block\n comment */\n'
        '  "b": [1, 2,],\n'
        '}\n',
      );
      expect(parsed, <String, dynamic>{
        'a': 1,
        'b': <dynamic>[1, 2],
      });
    });

    test('keeps comment markers and escapes inside strings', () {
      final parsed = parseJsonc(r'{"url": "https://x.y/*z", "q": "a\"//b"}');
      expect(parsed, <String, dynamic>{'url': 'https://x.y/*z', 'q': 'a"//b'});
    });

    test('tolerates an unterminated block comment and string', () {
      expect(parseJsonc('{"a": 1} /* open'), <String, dynamic>{'a': 1});
      expect(() => parseJsonc('{"a": "open'), throwsFormatException);
    });

    test('throws on broken JSON underneath', () {
      expect(() => parseJsonc('{"a": }'), throwsFormatException);
    });
  });

  group('TsconfigWorkspaceIo', () {
    group('file()', () {
      test('returns the tsconfig.workspace.json of the project', () {
        expect(io.file(project).path, workspaceJson().path);
      });
    });

    group('isExtended()', () {
      test('returns false without a tsconfig.json', () {
        expect(TsconfigWorkspaceIo.isExtended(project), isFalse);
      });

      test('returns false for an unparsable tsconfig.json', () {
        tsconfig().writeAsStringSync('{"extends": ');
        expect(TsconfigWorkspaceIo.isExtended(project), isFalse);
      });

      test('returns false for a non-object tsconfig.json', () {
        tsconfig().writeAsStringSync('[]');
        expect(TsconfigWorkspaceIo.isExtended(project), isFalse);
      });

      test('returns false without an extends field', () {
        tsconfig().writeAsStringSync('{"compilerOptions": {}}');
        expect(TsconfigWorkspaceIo.isExtended(project), isFalse);
      });

      test('returns false when another config is extended', () {
        tsconfig().writeAsStringSync('{"extends": "./tsconfig.base.json"}');
        expect(TsconfigWorkspaceIo.isExtended(project), isFalse);
      });

      test('returns true for the single form, comments included', () {
        writeExtendingTsconfig();
        expect(TsconfigWorkspaceIo.isExtended(project), isTrue);
      });

      test('returns true for the array form', () {
        tsconfig().writeAsStringSync(
          '{"extends": ["./tsconfig.base.json", "tsconfig.workspace.json"]}',
        );
        expect(TsconfigWorkspaceIo.isExtended(project), isTrue);
      });
    });

    group('hasLocalizedRefs()', () {
      test('returns false when the file is missing', () {
        expect(TsconfigWorkspaceIo.hasLocalizedRefs(project), isFalse);
      });

      test('returns true for an unparsable file', () {
        workspaceJson().writeAsStringSync('{"compilerOptions": ');
        expect(TsconfigWorkspaceIo.hasLocalizedRefs(project), isTrue);
      });

      test('returns false without paths', () {
        workspaceJson().writeAsStringSync('{"compilerOptions": {}}');
        expect(TsconfigWorkspaceIo.hasLocalizedRefs(project), isFalse);
        workspaceJson().writeAsStringSync('[]');
        expect(TsconfigWorkspaceIo.hasLocalizedRefs(project), isFalse);
        workspaceJson().writeAsStringSync('{"compilerOptions": []}');
        expect(TsconfigWorkspaceIo.hasLocalizedRefs(project), isFalse);
      });

      test('returns false for hand written mappings only', () {
        workspaceJson().writeAsStringSync(
          '{"compilerOptions": {"paths": {"@app/*": ["./src/app/*"]}}}',
        );
        expect(TsconfigWorkspaceIo.hasLocalizedRefs(project), isFalse);
      });

      test('returns true for a mapping to a sibling source', () {
        writeSibling();
        workspaceJson().writeAsStringSync(
          '{"compilerOptions": {"paths": {"dep_a": ["../dep_a/src/index.ts"]}}}',
        );
        expect(TsconfigWorkspaceIo.hasLocalizedRefs(project), isTrue);
      });

      test('returns true for a mapping to a sibling that is gone', () {
        workspaceJson().writeAsStringSync(
          '{"compilerOptions": {"paths": {"gone": ["../gone/src/index.ts"]}}}',
        );
        expect(TsconfigWorkspaceIo.hasLocalizedRefs(project), isTrue);
      });
    });

    group('isOwnedPath()', () {
      test('recognizes a sibling source mapping with a matching name', () {
        writeSibling();
        expect(
          io.isOwnedPath(
            projectDir: project,
            name: 'dep_a',
            value: <String>['../dep_a/src/index.ts'],
          ),
          isTrue,
        );
      });

      test('rejects a mapping whose sibling has another name', () {
        writeSibling(name: 'other');
        expect(
          io.isOwnedPath(
            projectDir: project,
            name: 'dep_a',
            value: <String>['../dep_a/src/index.ts'],
          ),
          isFalse,
        );
      });

      test('rejects a sibling without or with a broken package.json', () {
        expect(
          io.isOwnedPath(
            projectDir: project,
            name: 'dep_a',
            value: <String>['../dep_a/src/index.ts'],
          ),
          isFalse,
        );
        File(p.join(sibling.path, 'package.json')).writeAsStringSync('nope');
        expect(
          io.isOwnedPath(
            projectDir: project,
            name: 'dep_a',
            value: <String>['../dep_a/src/index.ts'],
          ),
          isFalse,
        );
      });

      test('rejects shapes this package does not write', () {
        writeSibling();
        for (final value in <dynamic>[
          '../dep_a/src/index.ts',
          <String>[],
          <String>['../dep_a/src/index.ts', '../dep_a/src/other.ts'],
          <dynamic>[1],
          <String>['../dep_a/dist/index.d.ts'],
          <String>['../../vendor/dep_a/src/index.ts'],
          <String>['./src/index.ts'],
        ]) {
          expect(
            io.isOwnedPath(projectDir: project, name: 'dep_a', value: value),
            isFalse,
            reason: '$value',
          );
        }
      });
    });

    group('addSourcePaths()', () {
      test('leaves a project alone whose tsconfig.json does not extend '
          'the file', () {
        tsconfig().writeAsStringSync('{"compilerOptions": {}}');
        writeSibling();
        final edit = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        expect(edit.isUnchanged, isTrue);
        expect(workspaceJson().existsSync(), isFalse);
      });

      test('creates the file with the mapping', () {
        writeExtendingTsconfig();
        writeSibling();
        final edit = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        expect(edit.content, isNotNull);
        workspaceJson().writeAsStringSync(edit.content!);
        expect(readWorkspaceJson(), <String, dynamic>{
          'compilerOptions': <String, dynamic>{
            'paths': <String, dynamic>{
              'dep_a': <String>['../dep_a/src/index.ts'],
            },
          },
        });
        expect(edit.content, endsWith('}\n'));
        expect(edit.content, contains('  "compilerOptions": {\n'));
      });

      test('skips a sibling without a src/index.ts', () {
        writeExtendingTsconfig();
        writeSibling(withSource: false);
        workspaceJson().writeAsStringSync('{"compilerOptions":{"paths":{}}}\n');
        final edit = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        expect(edit.isUnchanged, isTrue);
      });

      test('merges into the template file and keeps foreign settings', () {
        writeExtendingTsconfig();
        writeSibling();
        workspaceJson().writeAsStringSync(
          '{\n'
          '  // written by the template\n'
          '  "compilerOptions": {\n'
          '    "baseUrl": ".",\n'
          '    "paths": {\n'
          '      "@app/*": ["./src/app/*"]\n'
          '    }\n'
          '  },\n'
          '  "exclude": ["dist"]\n'
          '}\n',
        );
        final edit = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        workspaceJson().writeAsStringSync(edit.content!);
        expect(readWorkspaceJson(), <String, dynamic>{
          'compilerOptions': <String, dynamic>{
            'baseUrl': '.',
            'paths': <String, dynamic>{
              '@app/*': <String>['./src/app/*'],
              'dep_a': <String>['../dep_a/src/index.ts'],
            },
          },
          'exclude': <String>['dist'],
        });
      });

      test('is a no-op when the mapping is already there', () {
        writeExtendingTsconfig();
        writeSibling();
        workspaceJson().writeAsStringSync(
          '{"compilerOptions":{"paths":{"dep_a":["../dep_a/src/index.ts"]}}}',
        );
        final edit = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        expect(edit.isUnchanged, isTrue);
      });

      test('is a no-op when the file already has the exact content', () {
        writeExtendingTsconfig();
        writeSibling();
        final first = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        workspaceJson().writeAsStringSync(first.content!);
        // A second mapping that will not be written (no source) keeps the
        // content byte-identical.
        final again = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        expect(again.isUnchanged, isTrue);
      });

      test('rewrites a mapping that points elsewhere', () {
        writeExtendingTsconfig();
        writeSibling();
        workspaceJson().writeAsStringSync(
          '{"compilerOptions":{"paths":{"dep_a":["../old/src/index.ts"]}}}',
        );
        final edit = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        workspaceJson().writeAsStringSync(edit.content!);
        expect(
          (readWorkspaceJson()['compilerOptions']
              as Map<String, dynamic>)['paths'],
          <String, dynamic>{
            'dep_a': <String>['../dep_a/src/index.ts'],
          },
        );
      });

      test('prunes owned and dead mappings of dependencies that left', () {
        writeExtendingTsconfig();
        writeSibling();
        final other = Directory(p.join(workspace.path, 'dep_b'))
          ..createSync(recursive: true);
        File(p.join(other.path, 'package.json'))
            .writeAsStringSync('{"name":"dep_b"}');
        workspaceJson().writeAsStringSync(
          '{"compilerOptions":{"paths":{'
          '"dep_b":["../dep_b/src/index.ts"],'
          '"gone":["../gone/src/index.ts"],'
          '"@app/*":["./src/app/*"]'
          '}}}',
        );
        final edit = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        workspaceJson().writeAsStringSync(edit.content!);
        expect(
          (readWorkspaceJson()['compilerOptions']
              as Map<String, dynamic>)['paths'],
          <String, dynamic>{
            '@app/*': <String>['./src/app/*'],
            'dep_a': <String>['../dep_a/src/index.ts'],
          },
        );
      });

      test('replaces non-map sections instead of failing on them', () {
        writeExtendingTsconfig();
        writeSibling();
        workspaceJson().writeAsStringSync(
          '{"compilerOptions": {"paths": "x"}}',
        );
        final edit = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        workspaceJson().writeAsStringSync(edit.content!);
        expect(readWorkspaceJson(), <String, dynamic>{
          'compilerOptions': <String, dynamic>{
            'paths': <String, dynamic>{
              'dep_a': <String>['../dep_a/src/index.ts'],
            },
          },
        });

        workspaceJson().writeAsStringSync('{"compilerOptions": 5}');
        final edit2 = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        expect(edit2.content, contains('../dep_a/src/index.ts'));
      });

      test('treats an empty file as an empty object', () {
        writeExtendingTsconfig();
        writeSibling();
        workspaceJson().writeAsStringSync('  \n');
        final edit = io.addSourcePaths(
          projectDir: project,
          pathsByDependency: <String, String>{'dep_a': '../dep_a'},
        );
        expect(edit.content, contains('../dep_a/src/index.ts'));
      });

      test('throws a readable exception on an unparsable or non-object '
          'file', () {
        writeExtendingTsconfig();
        writeSibling();
        workspaceJson().writeAsStringSync('{"compilerOptions": ');
        expect(
          () => io.addSourcePaths(
            projectDir: project,
            pathsByDependency: <String, String>{'dep_a': '../dep_a'},
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Cannot parse ${workspaceJson().path}'),
            ),
          ),
        );

        workspaceJson().writeAsStringSync('[1, 2]');
        expect(
          () => io.addSourcePaths(
            projectDir: project,
            pathsByDependency: <String, String>{'dep_a': '../dep_a'},
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('expected a JSON object'),
            ),
          ),
        );
      });
    });

    group('removeOwnedPaths()', () {
      test('is a no-op without a file', () {
        expect(
          io
              .removeOwnedPaths(projectDir: project, dependencyNames: ['dep_a'])
              .isUnchanged,
          isTrue,
        );
      });

      test('empties the paths but keeps the extended file', () {
        writeExtendingTsconfig();
        writeSibling();
        workspaceJson().writeAsStringSync(
          '{"compilerOptions":{"paths":{"dep_a":["../dep_a/src/index.ts"]}}}',
        );
        final edit = io.removeOwnedPaths(
          projectDir: project,
          dependencyNames: <String>['dep_a'],
        );
        expect(edit.deleteFile, isFalse);
        expect(
          edit.content,
          '{\n  "compilerOptions": {\n    "paths": {}\n  }\n}\n',
        );
      });

      test('keeps hand written mappings and other options', () {
        writeExtendingTsconfig();
        writeSibling();
        workspaceJson().writeAsStringSync(
          '{"compilerOptions":{"baseUrl":".","paths":{'
          '"dep_a":["../dep_a/src/index.ts"],'
          '"@app/*":["./src/app/*"]}}}',
        );
        final edit = io.removeOwnedPaths(
          projectDir: project,
          dependencyNames: <String>['dep_a'],
        );
        workspaceJson().writeAsStringSync(edit.content!);
        expect(readWorkspaceJson(), <String, dynamic>{
          'compilerOptions': <String, dynamic>{
            'baseUrl': '.',
            'paths': <String, dynamic>{
              '@app/*': <String>['./src/app/*'],
            },
          },
        });
      });

      test('sweeps other owned and dead mappings unless restricted', () {
        writeExtendingTsconfig();
        writeSibling();
        workspaceJson().writeAsStringSync(
          '{"compilerOptions":{"paths":{'
          '"dep_a":["../dep_a/src/index.ts"],'
          '"gone":["../gone/src/index.ts"]}}}',
        );
        final swept = io.removeOwnedPaths(
          projectDir: project,
          dependencyNames: <String>['unrelated'],
        );
        expect(swept.content, isNot(contains('dep_a')));
        expect(swept.content, isNot(contains('gone')));

        final restricted = io.removeOwnedPaths(
          projectDir: project,
          dependencyNames: <String>['gone'],
          restrictToNames: true,
        );
        expect(restricted.content, contains('dep_a'));
        expect(restricted.content, isNot(contains('gone')));
      });

      test('leaves a hand written mapping of a named dependency alone', () {
        writeExtendingTsconfig();
        workspaceJson().writeAsStringSync(
          '{"compilerOptions":{"paths":{"dep_a":["./stubs/dep_a.ts"]}}}',
        );
        final edit = io.removeOwnedPaths(
          projectDir: project,
          dependencyNames: <String>['dep_a'],
        );
        expect(edit.isUnchanged, isTrue);
      });

      test('deletes a file nobody extends once nothing is left', () {
        writeSibling();
        workspaceJson().writeAsStringSync(
          '{"compilerOptions":{"paths":{"dep_a":["../dep_a/src/index.ts"]}}}',
        );
        final edit = io.removeOwnedPaths(
          projectDir: project,
          dependencyNames: <String>['dep_a'],
        );
        expect(edit.deleteFile, isTrue);

        workspaceJson().writeAsStringSync('{}');
        expect(
          io
              .removeOwnedPaths(projectDir: project, dependencyNames: ['x'])
              .deleteFile,
          isTrue,
        );
        workspaceJson().writeAsStringSync('{"compilerOptions": {}}');
        expect(
          io
              .removeOwnedPaths(projectDir: project, dependencyNames: ['x'])
              .deleteFile,
          isTrue,
        );
        workspaceJson().writeAsStringSync(
          '{"compilerOptions": {"paths": null}}',
        );
        expect(
          io
              .removeOwnedPaths(projectDir: project, dependencyNames: ['x'])
              .deleteFile,
          isTrue,
        );
      });

      test('keeps a file nobody extends when it carries more', () {
        for (final content in <String>[
          '{"exclude": ["dist"]}',
          '{"compilerOptions": {"baseUrl": "."}}',
          '{"compilerOptions": {"paths": {}, "baseUrl": "."}}',
          '{"compilerOptions": {"paths": {"@app/*": ["./src/app/*"]}}}',
          '{"compilerOptions": "x"}',
        ]) {
          workspaceJson().writeAsStringSync(content);
          expect(
            io
                .removeOwnedPaths(projectDir: project, dependencyNames: ['x'])
                .isUnchanged,
            isTrue,
            reason: content,
          );
        }
      });

      test('keeps an extended file even when nothing is left', () {
        writeExtendingTsconfig();
        workspaceJson().writeAsStringSync('{"compilerOptions":{"paths":{}}}');
        expect(
          io
              .removeOwnedPaths(projectDir: project, dependencyNames: ['x'])
              .isUnchanged,
          isTrue,
        );
      });
    });
  });
}
