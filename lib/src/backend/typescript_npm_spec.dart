// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// Pure helpers for the small grammar of npm dependency-spec strings —
/// classification, SemVer-range coercion, and URL/fragment manipulation.
/// I/O-free so commands can reuse them and tests stay trivial.
class TypeScriptNpmSpec {
  TypeScriptNpmSpec._(); // coverage:ignore-line

  // ...........................................................................
  /// Whether [spec] is an npm git URL or git-shorthand form.
  static bool isGitSpec(String spec) {
    final t = spec.trim();
    return t.startsWith('git+') ||
        t.startsWith('git://') ||
        t.startsWith('github:') ||
        t.startsWith('gitlab:') ||
        t.startsWith('bitbucket:');
  }

  // ...........................................................................
  /// Whether [spec] is a localized `file:`/`link:` reference.
  static bool isLocalizedSpec(String spec) {
    final t = spec.trim();
    return t.startsWith('file:') || t.startsWith('link:');
  }

  // ...........................................................................
  /// Whether [spec] is a git URL that already carries a `#…` fragment.
  /// `false` for non-git specs so callers can skip the [isGitSpec] check.
  static bool hasUrlFragment(String spec) {
    final t = spec.trim();
    if (!isGitSpec(t)) return false;
    return t.contains('#');
  }

  // ...........................................................................
  /// Coerces a version-ish string into a SemVer **range** for `#semver:` or
  /// `dependencies`. Existing ranges pass through; a bare SemVer gets caret-
  /// wrapped; non-versions like `latest`/`next` return `null`.
  static String? toSemverRange(String spec) {
    final t = spec.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('^') || t.startsWith('~')) return t;
    if (t.startsWith('<') || t.startsWith('>') || t.startsWith('=')) return t;
    if (t == '*' || t.contains('.x')) return t;
    final firstChar = t.codeUnitAt(0);
    if (firstChar >= 0x30 && firstChar <= 0x39) return '^$t';
    return null;
  }

  // ...........................................................................
  /// Normalizes a raw git remote URL into an npm-compatible base. SCP-style
  /// `git@host:path` (which pnpm 11 rejects with ERR_PNPM_SPEC_NOT_SUPPORTED_
  /// BY_ANY_RESOLVER) becomes `git+ssh://git@host/path`.
  static String toNpmGitBase(String remoteUrl) {
    final t = remoteUrl.trim();

    if (t.startsWith('git+')) {
      final body = t.substring(4);
      if (_isAcceptedUrlScheme(body)) return t;
      return _scpToGitPlusSsh(body) ?? t;
    }

    if (t.startsWith('git://') ||
        t.startsWith('github:') ||
        t.startsWith('gitlab:') ||
        t.startsWith('bitbucket:')) {
      return t;
    }

    if (_isAcceptedUrlScheme(t)) return 'git+$t';

    final ssh = _scpToGitPlusSsh(t);
    if (ssh != null) return ssh;

    // Filesystem paths / unknown schemes — historical `git+` fallback.
    return 'git+$t';
  }

  /// True for URL-scheme prefixes the npm/pnpm git resolver accepts.
  static bool _isAcceptedUrlScheme(String s) {
    return s.startsWith('https://') ||
        s.startsWith('http://') ||
        s.startsWith('ssh://') ||
        s.startsWith('git://');
  }

  /// Rewrites `<user>@<host>:<path>` → `git+ssh://<user>@<host>/<path>`,
  /// or `null` if [s] is not SCP-shaped.
  static String? _scpToGitPlusSsh(String s) {
    final m = RegExp(r'^([A-Za-z0-9._-]+)@([^:/]+):(.+)$').firstMatch(s);
    if (m == null) return null;
    return 'git+ssh://${m[1]}@${m[2]}/${m[3]}';
  }

  // ...........................................................................
  /// Returns [gitUrl] with any `#…` fragment removed.
  static String stripFragment(String gitUrl) {
    final i = gitUrl.indexOf('#');
    return i < 0 ? gitUrl : gitUrl.substring(0, i);
  }

  // ...........................................................................
  /// Returns [gitUrl] with its fragment replaced by `#semver:<range>`.
  /// Idempotent — safe to re-apply.
  static String withSemverFragment(String gitUrl, String range) {
    return '${stripFragment(gitUrl)}#semver:$range';
  }
}
