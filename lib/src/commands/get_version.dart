// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_log/gg_log.dart';

/// Command that reads the current package version from pubspec.yaml or
/// package.json.
class GetVersion extends DirCommand<dynamic> {
  /// Constructor
  GetVersion({required super.ggLog})
    : super(
        name: 'get-version',
        description: 'Reads the current package version from pubspec.yaml.',
      );

  // ...........................................................................
  @override
  Future<String?> get({required Directory directory, GgLog? ggLog}) async {
    ggLog?.call('Running get-version in ${directory.path}');

    try {
      final language = Utils.findLanguage(directory);
      final manifest = await language.readManifest(directory);
      final version = language.readPackageVersion(manifest.parsed);

      if (version == null || version.isEmpty) {
        ggLog?.call(
          yellow('No version found in ${language.manifestFileName}.'),
        );
        return null;
      }

      ggLog?.call(version);
      return version;
    } catch (e) {
      throw Exception(red('An error occurred: $e'));
    }
  }
}
