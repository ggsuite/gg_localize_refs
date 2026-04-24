// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_localize_refs/src/backend/manifest_command_support.dart';
import 'package:gg_localize_refs/src/backend/publish_to_utils.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Command that backs up the original `publish_to` value of a Dart project.
///
/// The backup is written as JSON to
/// `.gg/.gg_localize_refs_publish_to_backup.json`. The command is a no-op for
/// non-Dart projects and is idempotent: it does not overwrite an existing
/// backup file, so repeated invocations do not capture a previously injected
/// `publish_to: none` as the original value.
class BackupPublishTo extends DirCommand<void> {
  /// Creates the command.
  BackupPublishTo({required super.ggLog})
    : super(
        name: 'backup-publish-to',
        description:
            'Backs up the original publish_to value of pubspec.yaml to '
            '.gg/.gg_localize_refs_publish_to_backup.json.',
      );

  final ManifestCommandSupport _support = const ManifestCommandSupport();

  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    ggLog('Running backup-publish-to in ${directory.path}');

    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      ggLog(yellow('No pubspec.yaml found. Skipping publish_to backup.'));
      return;
    }

    _support.ensureDartBackupDir(directory);
    _support.ensureGitignoreHasDartBackupEntries(directory);

    final backupFile = Utils.dartPublishToBackupFile(directory);
    if (backupFile.existsSync()) {
      ggLog(yellow('publish_to backup already exists. Skipping.'));
      return;
    }

    final content = await pubspec.readAsString();
    final yamlMap = loadYaml(content) as Map<dynamic, dynamic>? ?? const {};
    final backupMap = backupPublishTo(yamlMap);

    await backupFile.writeAsString(jsonEncode(backupMap));
  }
}
