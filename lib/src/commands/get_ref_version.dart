// @license
// Copyright (c) ggsuite
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
import 'package:gg_log/gg_log.dart';

// #############################################################################
/// Command that reads the current version/spec of a dependency from
/// pubspec.yaml or package.json.
class GetRefVersion extends DirCommand<dynamic> {
  /// Constructor.
  GetRefVersion({required super.ggLog})
    : super(
        name: 'get-ref-version',
        description:
            'Reads the current version/spec of a dependency from pubspec.yaml.',
      ) {
    argParser.addOption('ref', help: 'The dependency name to read.');
  }

  // ...........................................................................
  @override
  Future<String?> get({
    required Directory directory,
    GgLog? ggLog,
    String? ref,
  }) async {
    ggLog?.call('Running get-ref-version in ${directory.path}');

    final String? dependencyName = ref ?? (argResults?['ref'] as String?);
    if (dependencyName == null || dependencyName.isEmpty) {
      throw Exception(red('Please provide a dependency name via --ref.'));
    }

    try {
      // A cross-language hybrid carries both a pubspec.yaml and a
      // package.json. Look the dependency up in EVERY manifest of the repo,
      // not just the one Utils.findLanguage would pick — that one is Dart
      // whenever a pubspec exists, so an npm dependency of a hybrid came back
      // as »not found« and its version was never propagated. Mirrors what
      // SetRefVersion already does; a single-language repo is unaffected.
      final languages = <ProjectLanguage>[
        DartProjectLanguage(),
        TypeScriptProjectLanguage(),
      ].where((l) => l.isProjectRoot(directory)).toList();

      if (languages.isEmpty) {
        // Reproduce the original "manifest not found" error.
        Utils.findLanguage(directory);
      }

      for (final language in languages) {
        final manifest = await language.readManifest(directory);

        final reference = language.findDependency(
          manifest.parsed,
          dependencyName,
        );
        if (reference == null) {
          continue;
        }

        final result = language.stringifyDependencyForReading(reference.value);
        ggLog?.call(result);
        return result;
      }

      ggLog?.call(yellow('Dependency $dependencyName not found.'));
      return null;
    } catch (e) {
      throw Exception(red('An error occurred: $e'));
    }
  }
}
