// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/languages/dart_language.dart';
import 'package:gg_localize_refs/src/backend/languages/project_language.dart';
import 'package:gg_localize_refs/src/backend/languages/typescript_language.dart';
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
      final language = _findLanguage(directory);
      final manifest = await language.readManifest(directory);

      final reference = language.findDependency(manifest.parsed, dependencyName);
      if (reference == null) {
        ggLog?.call(yellow('Dependency $dependencyName not found.'));
        return null;
      }

      final result = language.stringifyDependencyForReading(reference.value);
      ggLog?.call(result);
      return result;
    } catch (e) {
      throw Exception(red('An error occurred: $e'));
    }
  }

  ProjectLanguage _findLanguage(Directory directory) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    final packageJson = File('${directory.path}/package.json');

    if (pubspec.existsSync()) {
      return DartProjectLanguage();
    }
    if (packageJson.existsSync()) {
      return TypeScriptProjectLanguage();
    }

    throw Exception('pubspec.yaml not found at ${pubspec.path}');
  }
}
