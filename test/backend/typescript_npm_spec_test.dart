// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_localize_refs/src/backend/typescript_npm_spec.dart';
import 'package:test/test.dart';

void main() {
  group('TypeScriptNpmSpec', () {
    group('isGitSpec', () {
      test('detects git+https/git+ssh/git:// URLs', () {
        expect(
          TypeScriptNpmSpec.isGitSpec('git+https://github.com/u/r.git'),
          isTrue,
        );
        expect(
          TypeScriptNpmSpec.isGitSpec('git+ssh://git@github.com:u/r.git'),
          isTrue,
        );
        expect(TypeScriptNpmSpec.isGitSpec('git://github.com/u/r.git'), isTrue);
      });

      test('detects github:/gitlab:/bitbucket: shorthands', () {
        expect(TypeScriptNpmSpec.isGitSpec('github:user/repo'), isTrue);
        expect(TypeScriptNpmSpec.isGitSpec('gitlab:user/repo'), isTrue);
        expect(TypeScriptNpmSpec.isGitSpec('bitbucket:user/repo'), isTrue);
      });

      test('rejects ranges, tags, and localized specs', () {
        expect(TypeScriptNpmSpec.isGitSpec('^1.2.3'), isFalse);
        expect(TypeScriptNpmSpec.isGitSpec('1.2.3'), isFalse);
        expect(TypeScriptNpmSpec.isGitSpec('latest'), isFalse);
        expect(TypeScriptNpmSpec.isGitSpec('file:../proj2'), isFalse);
        expect(TypeScriptNpmSpec.isGitSpec('link:../proj2'), isFalse);
        expect(TypeScriptNpmSpec.isGitSpec(''), isFalse);
      });

      test('tolerates surrounding whitespace', () {
        expect(
          TypeScriptNpmSpec.isGitSpec('  git+https://example.com/r.git  '),
          isTrue,
        );
      });
    });

    group('isLocalizedSpec', () {
      test('detects file: and link:', () {
        expect(TypeScriptNpmSpec.isLocalizedSpec('file:../a'), isTrue);
        expect(TypeScriptNpmSpec.isLocalizedSpec('link:../a'), isTrue);
      });

      test('rejects everything else', () {
        expect(TypeScriptNpmSpec.isLocalizedSpec('^1.2.3'), isFalse);
        expect(
          TypeScriptNpmSpec.isLocalizedSpec('git+https://x/y.git'),
          isFalse,
        );
        expect(TypeScriptNpmSpec.isLocalizedSpec(''), isFalse);
      });
    });

    group('hasUrlFragment', () {
      test('true when a git URL carries any "#…" fragment', () {
        expect(
          TypeScriptNpmSpec.hasUrlFragment(
            'git+https://github.com/u/r.git#v1.2.3',
          ),
          isTrue,
        );
        expect(
          TypeScriptNpmSpec.hasUrlFragment(
            'git+https://github.com/u/r.git#semver:^1',
          ),
          isTrue,
        );
        expect(TypeScriptNpmSpec.hasUrlFragment('github:u/r#main'), isTrue);
      });

      test('false for bare git URLs', () {
        expect(
          TypeScriptNpmSpec.hasUrlFragment('git+https://github.com/u/r.git'),
          isFalse,
        );
      });

      test('false for non-git specs even if they contain "#"', () {
        // We never want to treat a registry range as fragment-bearing —
        // callers use this as a guard before appending `#semver:`.
        expect(TypeScriptNpmSpec.hasUrlFragment('^1.2.3'), isFalse);
        expect(TypeScriptNpmSpec.hasUrlFragment('latest'), isFalse);
        expect(TypeScriptNpmSpec.hasUrlFragment(''), isFalse);
      });
    });

    group('toSemverRange', () {
      test('passes caret and tilde ranges through', () {
        expect(TypeScriptNpmSpec.toSemverRange('^1.2.3'), '^1.2.3');
        expect(TypeScriptNpmSpec.toSemverRange('~1.2.3'), '~1.2.3');
      });

      test('passes comparator-based ranges through', () {
        expect(
          TypeScriptNpmSpec.toSemverRange('>=1.2.3 <2.0.0'),
          '>=1.2.3 <2.0.0',
        );
        expect(TypeScriptNpmSpec.toSemverRange('>1'), '>1');
        expect(TypeScriptNpmSpec.toSemverRange('=1.2.3'), '=1.2.3');
      });

      test('passes wildcard ranges through', () {
        expect(TypeScriptNpmSpec.toSemverRange('1.x'), '1.x');
        expect(TypeScriptNpmSpec.toSemverRange('1.2.x'), '1.2.x');
        expect(TypeScriptNpmSpec.toSemverRange('*'), '*');
      });

      test('wraps a bare SemVer with caret', () {
        expect(TypeScriptNpmSpec.toSemverRange('1.2.3'), '^1.2.3');
        expect(
          TypeScriptNpmSpec.toSemverRange('1.2.3-beta.4'),
          '^1.2.3-beta.4',
        );
      });

      test('returns null for non-version inputs', () {
        expect(TypeScriptNpmSpec.toSemverRange(''), isNull);
        expect(TypeScriptNpmSpec.toSemverRange('   '), isNull);
        expect(TypeScriptNpmSpec.toSemverRange('latest'), isNull);
        expect(TypeScriptNpmSpec.toSemverRange('next'), isNull);
      });

      test('trims whitespace before deciding', () {
        expect(TypeScriptNpmSpec.toSemverRange('  ^1.0.0  '), '^1.0.0');
        expect(TypeScriptNpmSpec.toSemverRange('  1.0.0  '), '^1.0.0');
      });
    });

    group('stripFragment', () {
      test('removes everything from the first "#" on', () {
        expect(
          TypeScriptNpmSpec.stripFragment('git+https://x/y.git#v1'),
          'git+https://x/y.git',
        );
        expect(
          TypeScriptNpmSpec.stripFragment('git+https://x/y.git#semver:^1'),
          'git+https://x/y.git',
        );
      });

      test('is a no-op when there is no fragment', () {
        expect(
          TypeScriptNpmSpec.stripFragment('git+https://x/y.git'),
          'git+https://x/y.git',
        );
      });
    });

    group('toNpmGitBase', () {
      test('keeps an already-accepted git+https URL as-is', () {
        expect(
          TypeScriptNpmSpec.toNpmGitBase('git+https://github.com/u/r.git'),
          'git+https://github.com/u/r.git',
        );
      });

      test('keeps an already-accepted git+ssh URL as-is', () {
        expect(
          TypeScriptNpmSpec.toNpmGitBase('git+ssh://git@github.com/u/r.git'),
          'git+ssh://git@github.com/u/r.git',
        );
      });

      test('keeps github:/gitlab:/bitbucket: shorthands as-is', () {
        expect(
          TypeScriptNpmSpec.toNpmGitBase('github:user/repo'),
          'github:user/repo',
        );
        expect(
          TypeScriptNpmSpec.toNpmGitBase('gitlab:user/repo'),
          'gitlab:user/repo',
        );
      });

      test('prefixes bare https/http/ssh/git URLs with git+', () {
        expect(
          TypeScriptNpmSpec.toNpmGitBase('https://github.com/u/r.git'),
          'git+https://github.com/u/r.git',
        );
        expect(
          TypeScriptNpmSpec.toNpmGitBase('http://example.com/r.git'),
          'git+http://example.com/r.git',
        );
        expect(
          TypeScriptNpmSpec.toNpmGitBase('ssh://git@github.com/u/r.git'),
          'git+ssh://git@github.com/u/r.git',
        );
      });

      test('rewrites SCP-style URLs to git+ssh:// with a path slash', () {
        // This is the actual production bug we are fixing — pnpm 11 rejects
        // `git@host:path` and `git+git@host:path` with
        // ERR_PNPM_SPEC_NOT_SUPPORTED_BY_ANY_RESOLVER.
        expect(
          TypeScriptNpmSpec.toNpmGitBase(
            'git@github.com:tssuite/ts_testproject_3.git',
          ),
          'git+ssh://git@github.com/tssuite/ts_testproject_3.git',
        );
      });

      test('rewrites a `git+<scp>` form that historically slipped through', () {
        expect(
          TypeScriptNpmSpec.toNpmGitBase(
            'git+git@github.com:tssuite/ts_testproject_3.git',
          ),
          'git+ssh://git@github.com/tssuite/ts_testproject_3.git',
        );
      });

      test('falls back to a bare `git+` prefix for unrecognized inputs '
          '(local filesystem paths used by tests, future schemes, …)', () {
        // Preserves the historical behavior of the call sites in
        // change_refs_to_git_feature_branch / change_refs_to_pub_dev so
        // tests that wire `Process.run('git init')` against a temp dir
        // and expect a `git+<path>` spec keep working.
        expect(
          TypeScriptNpmSpec.toNpmGitBase('weird:input'),
          'git+weird:input',
        );
        expect(TypeScriptNpmSpec.toNpmGitBase(''), 'git+');
      });
    });

    group('withSemverFragment', () {
      test('appends `#semver:<range>` to a bare URL', () {
        expect(
          TypeScriptNpmSpec.withSemverFragment('git+https://x/y.git', '^1.2.3'),
          'git+https://x/y.git#semver:^1.2.3',
        );
      });

      test('replaces an existing fragment', () {
        // Idempotency lets `change-refs-to-pub-dev` re-run safely.
        expect(
          TypeScriptNpmSpec.withSemverFragment(
            'git+https://x/y.git#v1.0.0',
            '^2.0.0',
          ),
          'git+https://x/y.git#semver:^2.0.0',
        );
        expect(
          TypeScriptNpmSpec.withSemverFragment(
            'git+https://x/y.git#semver:^1.0.0',
            '^2.0.0',
          ),
          'git+https://x/y.git#semver:^2.0.0',
        );
      });
    });
  });
}
