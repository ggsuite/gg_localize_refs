// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// #############################################################################
/// Pure helpers around the small grammar of npm dependency-spec strings as
/// they appear in `package.json`.
///
/// The methods here are intentionally I/O-free so they can be unit-tested in
/// isolation and reused from any command that needs to read or build a spec
/// string — `change-refs-to-pub-dev`, `set-ref-version`, etc.
///
/// The npm spec grammar we care about:
///
///  * **Registry range** — `^1.2.3`, `~1.2.3`, `>=1.2.3 <2`, the bare
///    `1.2.3`, the empty string, `latest`, `next`, …
///  * **Git URL** — `git+https://…`, `git+ssh://…`, `git://…`
///  * **Git shorthand** — `github:user/repo`, `gitlab:…`, `bitbucket:…`
///  * **Localized** — `file:…`, `link:…` (only produced by gg_localize_refs)
///
/// A git URL may carry a `#<fragment>` that pins it to a tag, branch, commit,
/// or — what this helper exists for — a `#semver:<range>` selector.
class TypeScriptNpmSpec {
  TypeScriptNpmSpec._(); // coverage:ignore-line

  // ...........................................................................
  /// Whether [spec] is one of the npm git URL or git-shorthand forms.
  static bool isGitSpec(String spec) {
    final t = spec.trim();
    return t.startsWith('git+') ||
        t.startsWith('git://') ||
        t.startsWith('github:') ||
        t.startsWith('gitlab:') ||
        t.startsWith('bitbucket:');
  }

  // ...........................................................................
  /// Whether [spec] is a localized path/link reference produced by the
  /// `change-refs-to-local` step.
  static bool isLocalizedSpec(String spec) {
    final t = spec.trim();
    return t.startsWith('file:') || t.startsWith('link:');
  }

  // ...........................................................................
  /// Whether [spec] is a git URL that already carries a `#…` fragment
  /// (a tag, branch, commit, or `#semver:` selector).
  ///
  /// Returns `false` for non-git specs so callers can use this as a guard
  /// without first having to check `isGitSpec`.
  static bool hasUrlFragment(String spec) {
    final t = spec.trim();
    if (!isGitSpec(t)) return false;
    return t.contains('#');
  }

  // ...........................................................................
  /// Coerces a version-ish string into a SemVer **range** suitable for an
  /// npm `#semver:` fragment or a `dependencies` entry.
  ///
  /// Pass-through for anything already shaped like a range:
  ///   * `^1.2.3`, `~1.2.3` (caret / tilde)
  ///   * `>=1.2.3 <2.0.0`, `>1`, `=1.2.3` (comparator-based)
  ///   * `1.x`, `1.2.x`, `*` (wildcard)
  ///
  /// Wraps a bare SemVer with a caret so it behaves like an npm constraint
  /// rather than an exact pin:
  ///   * `1.2.3`         → `^1.2.3`
  ///   * `1.2.3-beta.4`  → `^1.2.3-beta.4`
  ///
  /// Returns `null` when [spec] is empty or doesn't look like a version
  /// (e.g. a tag name like `next` or `latest`) — callers can then fall back
  /// to a different source or omit the `#semver:` fragment entirely.
  static String? toSemverRange(String spec) {
    final t = spec.trim();
    if (t.isEmpty) return null;
    // Already a range — pass through unchanged.
    if (t.startsWith('^') || t.startsWith('~')) return t;
    if (t.startsWith('<') || t.startsWith('>') || t.startsWith('=')) return t;
    if (t == '*' || t.contains('.x')) return t;
    // Bare SemVer — wrap with caret so the spec stays a range.
    final firstChar = t.codeUnitAt(0);
    if (firstChar >= 0x30 && firstChar <= 0x39) return '^$t';
    return null;
  }

  // ...........................................................................
  /// Converts a raw git remote URL (the kind `git remote get-url` prints) into
  /// an **npm-compatible** git dependency base.
  ///
  /// The npm/pnpm git resolver only accepts a handful of forms; in
  /// particular it does **not** accept the bare SCP-style URL
  /// `git@host:path` even with a leading `git+` — that yields
  /// `ERR_PNPM_SPEC_NOT_SUPPORTED_BY_ANY_RESOLVER` on pnpm 11. This helper
  /// normalizes the common shapes:
  ///
  ///  * `git+https://…`, `git+ssh://…`, `git+git://…` — kept as-is.
  ///  * `github:`, `gitlab:`, `bitbucket:` shorthands — kept as-is (they do
  ///    not take a `git+` prefix).
  ///  * `https://…`, `http://…`, `ssh://…`, `git://…` — prefixed with `git+`.
  ///  * SCP-style `<user>@<host>:<path>` (with or without an erroneous
  ///    `git+` prefix) — rewritten to `git+ssh://<user>@<host>/<path>`.
  ///  * Anything else — prefixed with `git+` so historical call sites that
  ///    receive a non-URL filesystem path (e.g. test fixtures) still produce
  ///    a syntactically valid spec.
  static String toNpmGitBase(String remoteUrl) {
    final t = remoteUrl.trim();

    // `git+<body>` — the body decides: re-emit unchanged when it's a real
    // URL scheme, otherwise let the SCP rewrite normalize it.
    if (t.startsWith('git+')) {
      final body = t.substring(4);
      if (_isAcceptedUrlScheme(body)) return t;
      return _scpToGitPlusSsh(body) ?? t;
    }

    // Already an accepted shape — return as-is.
    if (t.startsWith('git://') ||
        t.startsWith('github:') ||
        t.startsWith('gitlab:') ||
        t.startsWith('bitbucket:')) {
      return t;
    }

    // Bare URL scheme — prefix `git+`.
    if (_isAcceptedUrlScheme(t)) return 'git+$t';

    // SCP-style remote — rewrite to `git+ssh://…`.
    final ssh = _scpToGitPlusSsh(t);
    if (ssh != null) return ssh;

    // Anything else (filesystem paths, future schemes) — preserve the
    // historical "just prepend git+" behavior so existing call sites keep
    // emitting a syntactically valid spec.
    return 'git+$t';
  }

  /// True for the URL-scheme prefixes npm/pnpm's git resolver accepts when
  /// they appear after a leading `git+` (or on their own, in which case the
  /// caller adds the prefix).
  static bool _isAcceptedUrlScheme(String s) {
    return s.startsWith('https://') ||
        s.startsWith('http://') ||
        s.startsWith('ssh://') ||
        s.startsWith('git://');
  }

  /// Rewrites `<user>@<host>:<path>` to `git+ssh://<user>@<host>/<path>`,
  /// or returns null if [s] is not SCP-shaped.
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
  ///
  /// Idempotent — calling this on an already-pinned URL produces the same
  /// output as calling it on the bare URL.
  static String withSemverFragment(String gitUrl, String range) {
    return '${stripFragment(gitUrl)}#semver:$range';
  }
}
