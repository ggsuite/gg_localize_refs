// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights
// Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
// ignore: lines_longer_than_80_chars
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/multi_language_graph.dart';
import 'package:gg_localize_refs/src/backend/package_json_io.dart';
import 'package:gg_localize_refs/src/backend/typescript_npm_spec.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_publish/gg_publish.dart';

// #############################################################################
/// Command that sets the version/spec of a dependency in pubspec.yaml
/// or package.json. Operates directly on the manifest in the input
/// directory; does not traverse a workspace.
class SetRefVersion extends DirCommand<dynamic> {
  /// Constructor.
  SetRefVersion({required super.ggLog})
    : isOnPubDev = IsOnPubDev(ggLog: ggLog),
      super(
        name: 'set-ref-version',
        description: 'Sets the version/spec of a dependency in pubspec.yaml.',
      ) {
    argParser
      ..addOption('ref', help: 'The dependency name to change.')
      ..addOption(
        'version',
        help:
            'The new version/spec. Can be a scalar (e.g., ^1.2.3) '
            'or a YAML/JSON block.',
      );
  }

  /// Service used to check whether a dependency was published before.
  final IsOnPubDev isOnPubDev;

  // ...........................................................................
  @override
  Future<void> get({
    required Directory directory,
    GgLog? ggLog,
    String? ref,
    String? version,
  }) async {
    final String? dependencyName = ref ?? (argResults?['ref'] as String?);
    final String? newVersion = version ?? (argResults?['version'] as String?);

    if (dependencyName == null || dependencyName.isEmpty) {
      throw Exception(red('Please provide a dependency name via --ref.'));
    }
    if (newVersion == null) {
      throw Exception(red('Please provide the new version via --version.'));
    }

    try {
      // A cross-language bridge carries both a pubspec.yaml and a
      // package.json. Update the dependency in EVERY manifest that declares
      // it, not just the one Utils.findLanguage would pick. A single-language
      // repo is handled exactly as before (one manifest).
      final languages = <ProjectLanguage>[
        DartProjectLanguage(),
        TypeScriptProjectLanguage(),
      ].where((l) => l.isProjectRoot(directory)).toList();

      if (languages.isEmpty) {
        // Reproduce the original "manifest not found" error.
        Utils.findLanguage(directory);
      }

      var found = false;
      var changed = false;
      for (final language in languages) {
        final manifest = await language.readManifest(directory);
        final reference = language.findDependency(
          manifest.parsed,
          dependencyName,
        );
        if (reference == null) {
          continue;
        }
        found = true;

        // Preserve the constraint operator the dependency is currently
        // declared with (`^`, `~`, or exact) when [newVersion] is a bare
        // version number. During a publish the refs were just unlocalized
        // back to their original spec, so the user's chosen style is
        // reapplied to the bumped version. An explicit operator/range in
        // [newVersion] always wins.
        final effectiveVersion = _bumpVersionPreservingOperator(
          reference.value,
          newVersion,
        );

        final replacement = await _buildReplacement(
          language: language,
          workspaceDirectory: directory,
          dependencyName: dependencyName,
          oldDependency: reference.value,
          newVersion: effectiveVersion,
        );

        final updated = language
            .replaceDependencyInContent(
              manifestContent: manifest.content,
              reference: reference,
              newValue: replacement,
            )
            .trim();

        if (updated == manifest.content) {
          continue;
        }
        manifest.file.writeAsStringSync(updated);
        changed = true;
      }

      if (!found) {
        throw Exception('Dependency $dependencyName not found.');
      }
      if (!changed) {
        ggLog?.call(yellow('No files were changed.'));
      }
    } catch (e) {
      throw Exception(red('An error occurred: $e. No files were changed.'));
    }
  }

  /// Applies the version number of [newVersion] while keeping the operator the
  /// dependency currently uses. If [newVersion] already carries an operator or
  /// range (anything not starting with a digit) it is returned unchanged.
  /// Otherwise the leading `^`/`~` of [oldDependency] — a scalar like `~1.2.3`
  /// or a block with a `version:` field — is prepended; a bare/exact current
  /// spec yields a bare (exact) result.
  String _bumpVersionPreservingOperator(
    dynamic oldDependency,
    String newVersion,
  ) {
    final newTrimmed = newVersion.trim();
    if (!RegExp(r'^\d').hasMatch(newTrimmed)) {
      return newVersion;
    }
    final oldText = oldDependency is String
        ? oldDependency
        : yamlToString(oldDependency);
    final operator = RegExp(r'(\^|~)\s*\d').firstMatch(oldText)?.group(1) ?? '';
    return '$operator$newTrimmed';
  }

  Future<String> _buildReplacement({
    required ProjectLanguage language,
    required Directory workspaceDirectory,
    required String dependencyName,
    required dynamic oldDependency,
    required String newVersion,
  }) async {
    if (language.id == ProjectLanguageId.typescript) {
      // Private dep → git+<remote>#semver:; public dep → hosted range.
      final dependencyDirectory = await _findDependencyDirectory(
        workspaceDirectory: workspaceDirectory,
        dependencyName: dependencyName,
        language: language,
      );
      if (dependencyDirectory != null &&
          PackageJsonIo.isPrivate(dependencyDirectory)) {
        return _buildPrivateTypeScriptGitSpec(
          dependencyDirectory: dependencyDirectory,
          dependencyName: dependencyName,
          oldDependency: oldDependency,
          newVersion: newVersion,
        );
      }
      return newVersion;
    }

    final dependencyDirectory = await _findDependencyDirectory(
      workspaceDirectory: workspaceDirectory,
      dependencyName: dependencyName,
      language: language,
    );

    if (dependencyDirectory == null) {
      throw Exception(
        'Could not find local directory for dependency $dependencyName. '
        'Make sure it is part of the workspace.',
      );
    }

    final published = await isOnPubDev.get(
      directory: dependencyDirectory,
      ggLog: ggLog,
    );
    if (published) {
      return newVersion;
    }

    final gitUrl = await Utils.getGitRemoteUrl(
      dependencyDirectory,
      dependencyName,
    );
    return yamlToString(<String, dynamic>{
      'git': gitUrl,
      'version': newVersion,
    }).trimRight();
  }

  /// Builds `git+<remote>#semver:<range>` for a private TS dep — reuses the
  /// protocol of an existing git spec, otherwise reads the remote fresh.
  /// Bare `1.2.3` is caret-wrapped via [TypeScriptNpmSpec.toSemverRange].
  Future<String> _buildPrivateTypeScriptGitSpec({
    required Directory dependencyDirectory,
    required String dependencyName,
    required dynamic oldDependency,
    required String newVersion,
  }) async {
    final oldSpec = oldDependency?.toString().trim() ?? '';
    final String rawBase;
    if (TypeScriptNpmSpec.isGitSpec(oldSpec)) {
      rawBase = TypeScriptNpmSpec.stripFragment(oldSpec);
    } else {
      rawBase = await Utils.getGitRemoteUrl(
        dependencyDirectory,
        dependencyName,
      );
    }
    final base = TypeScriptNpmSpec.toNpmGitBase(rawBase);
    final range = TypeScriptNpmSpec.toSemverRange(newVersion) ?? newVersion;
    return TypeScriptNpmSpec.withSemverFragment(base, range);
  }

  /// Finds the local dependency directory for [dependencyName] if available,
  /// resolving it within the graph of [language] (so a bridge's TypeScript
  /// dependency is looked up among TypeScript nodes, not Dart ones).
  Future<Directory?> _findDependencyDirectory({
    required Directory workspaceDirectory,
    required String dependencyName,
    required ProjectLanguage language,
  }) async {
    try {
      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[
          DartProjectLanguage(),
          TypeScriptProjectLanguage(),
        ],
      );
      final result = await graph.buildGraph(
        directory: workspaceDirectory,
        forLanguage: language,
      );
      final node = result.allNodes[dependencyName];
      return node?.directory;
    } catch (_) {
      return null;
    }
  }
}
