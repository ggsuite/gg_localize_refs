// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/pubspec_overrides_io.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// A package embedded in a project: its directory and its `pubspec.yaml`, as
/// text and parsed.
typedef EmbeddedPackage = ({
  Directory directory,
  String content,
  Map<dynamic, dynamic> pubspec,
});

/// The edits that make the embedded packages of a project members of its pub
/// workspace, computed without touching the disk.
class PubWorkspaceJoin {
  /// Constructor.
  const PubWorkspaceJoin({
    required this.rootContent,
    required this.memberContents,
    required this.joined,
    required this.skipped,
  });

  /// The new content of the root `pubspec.yaml`, or null when it stays.
  final String? rootContent;

  /// The new content of each member `pubspec.yaml` that changes, by the
  /// path of the file.
  final Map<String, String> memberContents;

  /// The members, relative to the root, that are not fully joined yet and
  /// get joined by this edit. Empty when no file changes.
  final List<String> joined;

  /// One reason per embedded package that cannot be joined automatically.
  final List<String> skipped;
}

/// Makes the embedded packages of a Dart project - an `example/` app with a
/// `pubspec.yaml` of its own - members of the project's pub workspace.
///
/// An embedded package is a pub package of its own. Pub resolves it on its
/// own and ignores the `pubspec_overrides.yaml` of the project it lives in,
/// so a localized sibling would resolve from pub.dev in `example/` while the
/// project itself uses the sibling's checkout. As a member of the project's
/// pub workspace it shares the project's resolution, and with it every
/// override of the project.
///
/// Joining declares the member in the `workspace` list of the root
/// `pubspec.yaml` and sets `resolution: workspace` in the member. That is a
/// permanent change of the repository, not a localization: it holds for
/// published refs just as well and is never reverted.
class PubWorkspaceIo {
  /// Constructor.
  const PubWorkspaceIo();

  /// The Dart SDK that introduced pub workspaces.
  static final Version minSdk = Version(3, 6, 0);

  /// Directory names never searched for embedded packages: sources, build
  /// output, generated docs, the platform folders of a Flutter app with their
  /// pods, installed node packages - and tests, whose fixtures may depend on
  /// the project on purpose with a resolution of their own.
  static const Set<String> _skippedDirNames = <String>{
    'android',
    'bin',
    'build',
    'coverage',
    'doc',
    'ios',
    'lib',
    'linux',
    'macos',
    'node_modules',
    'test',
    'web',
    'windows',
  };

  // ...........................................................................
  /// Returns the packages below [projectDir] whose `pubspec.yaml` depends on
  /// [projectDir] through a `path` dependency, sorted by path.
  ///
  /// A `pubspec.yaml` that does not point back at the project - a test
  /// fixture, a vendored package - is no embedded package of it. Hidden
  /// directories and those in [_skippedDirNames] are not searched.
  List<EmbeddedPackage> embeddedPackages(Directory projectDir) {
    final target = p.normalize(projectDir.absolute.path);
    final result = <EmbeddedPackage>[];
    final pending = <Directory>[projectDir];

    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final name = p.basename(entity.path);
        if (name.startsWith('.') || _skippedDirNames.contains(name)) {
          continue;
        }
        pending.add(entity);

        final file = File(p.join(entity.path, 'pubspec.yaml'));
        if (!file.existsSync()) {
          continue;
        }
        final content = file.readAsStringSync();
        final pubspec = _parseMap(content);
        if (_dependsOnPath(entity, pubspec, target)) {
          result.add((directory: entity, content: content, pubspec: pubspec));
        }
      }
    }

    result.sort((a, b) => a.directory.path.compareTo(b.directory.path));
    return result;
  }

  // ...........................................................................
  /// Computes the edit that joins every embedded package of [projectDir]
  /// into its pub workspace.
  ///
  /// [pubspecContent] is the current content of the root `pubspec.yaml` -
  /// possibly already edited by the caller. [overriddenNames] are the
  /// dependencies the caller overrides in the root's `pubspec_overrides.yaml`;
  /// the root's own `dependency_overrides` and an existing overrides file are
  /// read here.
  ///
  /// A package is left alone, with a reason in [PubWorkspaceJoin.skipped],
  /// when joining would break its resolution: an SDK constraint below
  /// [minSdk], a `resolution` other than `workspace`, a Flutter member of a
  /// project that is no Flutter package, a version constraint that
  /// contradicts the one of the root, or an override the root declares too -
  /// pub allows a single override per package in a workspace.
  PubWorkspaceJoin join({
    required Directory projectDir,
    required String pubspecContent,
    Iterable<String> overriddenNames = const <String>[],
  }) {
    final rootPubspec = _parseMap(pubspecContent);
    final listed = _workspaceEntries(rootPubspec);
    final root = (
      supportsWorkspaces: _supportsWorkspaces(rootPubspec),
      isFlutter: _dependsOnFlutter(rootPubspec),
      constraints: _versionConstraints(rootPubspec),
      overrides: <String>{
        ...overriddenNames,
        ..._overrideNames(rootPubspec),
        ..._overrideNames(_readOverrides(projectDir)),
      },
    );

    final toList = <String>[];
    final memberContents = <String, String>{};
    final joined = <String>[];
    final skipped = <String>[];

    for (final member in embeddedPackages(projectDir)) {
      final relative = p.posix.joinAll(
        p.split(p.relative(member.directory.path, from: projectDir.path)),
      );
      final isListed = listed.any((entry) => entry.matches(relative));
      final hasResolution = member.pubspec['resolution'] == 'workspace';
      if (isListed && hasResolution) {
        continue;
      }

      final reason = _blocker(relative: relative, member: member, root: root);
      if (reason != null) {
        skipped.add(reason);
        continue;
      }

      joined.add(relative);
      if (!isListed) {
        toList.add(relative);
      }
      if (!hasResolution) {
        final editor = YamlEditor(member.content)
          ..update(<Object>['resolution'], 'workspace');
        memberContents[p.join(member.directory.path, 'pubspec.yaml')] =
            Utils.withTrailingNewline(editor.toString());
      }
    }

    return PubWorkspaceJoin(
      rootContent: toList.isEmpty
          ? null
          : _addToWorkspace(pubspecContent, rootPubspec, toList),
      memberContents: memberContents,
      joined: joined,
      skipped: skipped,
    );
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  /// Returns why the embedded package [member] at [relative] cannot join the
  /// workspace of [root], or null.
  String? _blocker({
    required String relative,
    required EmbeddedPackage member,
    required ({
      bool supportsWorkspaces,
      bool isFlutter,
      Map<String, VersionConstraint> constraints,
      Set<String> overrides,
    })
    root,
  }) {
    final prefix = 'Cannot make $relative a pub workspace member';
    final pubspec = member.pubspec;

    final resolution = pubspec['resolution'];
    if (resolution != null && resolution != 'workspace') {
      return '$prefix: it declares resolution: $resolution.';
    }

    if (!root.supportsWorkspaces) {
      return '$prefix: the SDK constraint of pubspec.yaml allows Dart below '
          '$minSdk, which has no pub workspaces.';
    }

    if (!_supportsWorkspaces(pubspec)) {
      return '$prefix: the SDK constraint of $relative/pubspec.yaml allows '
          'Dart below $minSdk, which has no pub workspaces.';
    }

    if (_dependsOnFlutter(pubspec) && !root.isFlutter) {
      return '$prefix: it needs Flutter, but the package it belongs to does '
          'not - resolving the package would need the Flutter SDK then.';
    }

    final contradicting = <String>[
      for (final MapEntry(key: name, value: constraint) in _versionConstraints(
        pubspec,
      ).entries)
        if (root.constraints[name]?.intersect(constraint).isEmpty ?? false)
          name,
    ]..sort();
    if (contradicting.isNotEmpty) {
      return '$prefix: its version constraints of '
          '${contradicting.join(', ')} contradict those of pubspec.yaml, so '
          'the workspace could not be resolved.';
    }

    final doubled = <String>{
      ..._overrideNames(pubspec),
      ..._overrideNames(_readOverrides(member.directory)),
    }.intersection(root.overrides).toList()..sort();
    if (doubled.isNotEmpty) {
      return '$prefix: it overrides ${doubled.join(', ')} itself, and pub '
          'allows a single override per package in a workspace. Remove the '
          'override from $relative.';
    }

    return null;
  }

  // ...........................................................................
  /// Returns [content] with [paths] appended to its `workspace` list.
  String _addToWorkspace(
    String content,
    Map<dynamic, dynamic> root,
    List<String> paths,
  ) {
    final editor = YamlEditor(content);
    if (root['workspace'] is List) {
      for (final path in paths) {
        editor.appendToList(<Object>['workspace'], path);
      }
    } else {
      editor.update(<Object>['workspace'], paths);
    }
    return Utils.withTrailingNewline(editor.toString());
  }

  // ...........................................................................
  /// Returns the entries of the `workspace` list of [pubspec] as globs -
  /// pub accepts glob patterns such as `packages/*` there.
  List<Glob> _workspaceEntries(Map<dynamic, dynamic> pubspec) {
    final workspace = pubspec['workspace'];
    if (workspace is! List) {
      return const <Glob>[];
    }
    return <Glob>[
      for (final entry in workspace)
        if (entry is String) Glob(p.posix.normalize(entry), context: p.posix),
    ];
  }

  // ...........................................................................
  /// Returns the entries of the dependencies and dev dependencies of
  /// [pubspec].
  Iterable<MapEntry<dynamic, dynamic>> _dependencyEntries(
    Map<dynamic, dynamic> pubspec,
  ) sync* {
    for (final section in const <String>['dependencies', 'dev_dependencies']) {
      final dependencies = pubspec[section];
      if (dependencies is Map) {
        yield* dependencies.entries;
      }
    }
  }

  // ...........................................................................
  /// Returns the version constraints of the hosted dependencies and dev
  /// dependencies of [pubspec]. `path`, `git` and `sdk` dependencies carry
  /// none.
  Map<String, VersionConstraint> _versionConstraints(
    Map<dynamic, dynamic> pubspec,
  ) {
    final result = <String, VersionConstraint>{};
    for (final MapEntry(:key, :value) in _dependencyEntries(pubspec)) {
      final spec = value is Map ? value['version'] : value;
      if (spec is! String) {
        continue;
      }
      try {
        result['$key'] = VersionConstraint.parse(spec);
      } on FormatException {
        // pub reports an invalid constraint itself.
      }
    }
    return result;
  }

  // ...........................................................................
  /// Returns whether the SDK constraint of [pubspec] excludes every Dart
  /// version below [minSdk]. A missing or unparsable constraint does not.
  bool _supportsWorkspaces(Map<dynamic, dynamic> pubspec) {
    final environment = pubspec['environment'];
    final sdk = environment is Map ? environment['sdk'] : null;
    if (sdk is! String) {
      return false;
    }

    final VersionConstraint constraint;
    try {
      constraint = VersionConstraint.parse(sdk);
    } on FormatException {
      return false;
    }
    return !constraint.allowsAny(VersionRange(max: minSdk));
  }

  // ...........................................................................
  /// Returns whether [pubspec] depends on the Flutter SDK.
  bool _dependsOnFlutter(Map<dynamic, dynamic> pubspec) {
    final dependencies = pubspec['dependencies'];
    final flutter = dependencies is Map ? dependencies['flutter'] : null;
    return flutter is Map && flutter['sdk'] == 'flutter';
  }

  // ...........................................................................
  /// Returns the names in the `dependency_overrides` of [yaml].
  Set<String> _overrideNames(Map<dynamic, dynamic> yaml) {
    final section = yaml['dependency_overrides'];
    if (section is! Map) {
      return const <String>{};
    }
    return <String>{for (final key in section.keys) key.toString()};
  }

  // ...........................................................................
  /// Returns whether [pubspec] of the package in [dir] declares a `path`
  /// dependency or dev dependency on the normalized absolute path [target].
  bool _dependsOnPath(
    Directory dir,
    Map<dynamic, dynamic> pubspec,
    String target,
  ) {
    for (final MapEntry(:value) in _dependencyEntries(pubspec)) {
      final path = value is Map ? value['path'] : null;
      if (path is String &&
          p.equals(p.normalize(p.join(dir.absolute.path, path)), target)) {
        return true;
      }
    }
    return false;
  }

  // ...........................................................................
  /// Returns the `pubspec_overrides.yaml` of [dir] as a YAML map, or an
  /// empty map when there is none or it holds no readable map.
  Map<dynamic, dynamic> _readOverrides(Directory dir) {
    final file = const PubspecOverridesIo().file(dir);
    return file.existsSync()
        ? _parseMap(file.readAsStringSync())
        : const <dynamic, dynamic>{};
  }

  // ...........................................................................
  /// Returns the YAML map in [content], or an empty map.
  Map<dynamic, dynamic> _parseMap(String content) {
    try {
      final parsed = loadYaml(content);
      return parsed is Map ? parsed : const <dynamic, dynamic>{};
    } catch (_) {
      return const <dynamic, dynamic>{};
    }
  }
}
