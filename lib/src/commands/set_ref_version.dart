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
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_localize_refs/src/backend/multi_language_graph.dart';
import 'package:gg_localize_refs/src/backend/yaml_to_string.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_publish/gg_publish.dart';

// #############################################################################
/// Command that sets the version/spec of a dependency in pubspec.yaml
/// or package.json.
///
/// This command operates directly on the manifest in the provided
/// input directory. It does not traverse a workspace or use project graphs.
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
      final language = Utils.findLanguage(directory);
      final manifest = await language.readManifest(directory);
      final reference = language.findDependency(
        manifest.parsed,
        dependencyName,
      );

      if (reference == null) {
        throw Exception('Dependency $dependencyName not found.');
      }

      final replacement = await _buildReplacement(
        language: language,
        workspaceDirectory: directory,
        dependencyName: dependencyName,
        oldDependency: reference.value,
        newVersion: newVersion,
      );

      final updated = language
          .replaceDependencyInContent(
            manifestContent: manifest.content,
            reference: reference,
            newValue: replacement,
          )
          .trim();

      if (updated == manifest.content) {
        ggLog?.call(yellow('No files were changed.'));
        return;
      }

      manifest.file.writeAsStringSync(updated);
    } catch (e) {
      throw Exception(red('An error occurred: $e. No files were changed.'));
    }
  }

  Future<String> _buildReplacement({
    required ProjectLanguage language,
    required Directory workspaceDirectory,
    required String dependencyName,
    required dynamic oldDependency,
    required String newVersion,
  }) async {
    if (language.id == ProjectLanguageId.typescript) {
      return newVersion;
    }

    final dependencyDirectory = await _findDependencyDirectory(
      workspaceDirectory: workspaceDirectory,
      dependencyName: dependencyName,
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
      'git': <String, dynamic>{'url': gitUrl, 'tag_pattern': '{{version}}'},
      'version': newVersion,
    }).trimRight();
  }

  /// Finds the local dependency directory for [dependencyName] if available.
  Future<Directory?> _findDependencyDirectory({
    required Directory workspaceDirectory,
    required String dependencyName,
  }) async {
    try {
      final graph = MultiLanguageGraph(
        languages: <ProjectLanguage>[
          DartProjectLanguage(),
          TypeScriptProjectLanguage(),
        ],
      );
      final result = await graph.buildGraph(directory: workspaceDirectory);
      final node = result.allNodes[dependencyName];
      return node?.directory;
    } catch (_) {
      return null;
    }
  }
}
