// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

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
      final pubspecFile = File('${directory.path}/pubspec.yaml');
      final packageJsonFile = File('${directory.path}/package.json');

      if (!pubspecFile.existsSync() && !packageJsonFile.existsSync()) {
        throw Exception('pubspec.yaml not found at ${pubspecFile.path}');
      }

      if (pubspecFile.existsSync()) {
        final content = pubspecFile.readAsStringSync();
        final pubspec = Pubspec.parse(content);

        final version = pubspec.version?.toString();
        if (version == null || version.isEmpty) {
          ggLog?.call(yellow('No version found in pubspec.yaml.'));
          return null;
        }

        ggLog?.call(version);
        return version;
      }

      final content = packageJsonFile.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final version = json['version']?.toString();
      if (version == null || version.isEmpty) {
        ggLog?.call(yellow('No version found in package.json.'));
        return null;
      }

      ggLog?.call(version);
      return version;
    } catch (e) {
      throw Exception(red('An error occurred: $e'));
    }
  }
}
