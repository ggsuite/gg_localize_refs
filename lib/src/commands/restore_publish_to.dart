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
import 'package:gg_localize_refs/src/backend/publish_to_utils.dart';
import 'package:gg_localize_refs/src/backend/utils.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;

/// Command that restores the original `publish_to` value from the backup.
///
/// Reads `.gg/.gg_localize_refs_publish_to_backup.json`, applies
/// [restorePublishTo] to the current `pubspec.yaml`, and deletes the backup
/// file. If no backup exists, the manifest is left untouched — in particular,
/// an existing `publish_to: none` is preserved.
class RestorePublishTo extends DirCommand<void> {
  /// Creates the command.
  RestorePublishTo({required super.ggLog})
    : super(
        name: 'restore-publish-to',
        description:
            'Restores the original publish_to value in pubspec.yaml from '
            '.gg/.gg_localize_refs_publish_to_backup.json.',
      );

  @override
  Future<void> get({required Directory directory, required GgLog ggLog}) async {
    ggLog('Running restore-publish-to in ${directory.path}');

    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      ggLog(yellow('No pubspec.yaml found. Skipping publish_to restore.'));
      return;
    }

    final backupFile = Utils.dartPublishToBackupFile(directory);
    if (!backupFile.existsSync()) {
      ggLog(
        yellow('No publish_to backup found. Leaving pubspec.yaml unchanged.'),
      );
      return;
    }

    final backupMap =
        jsonDecode(await backupFile.readAsString()) as Map<String, dynamic>;
    final content = await pubspec.readAsString();
    final restored = restorePublishTo(content, backupMap);

    if (restored != content) {
      await pubspec.writeAsString(restored);
    }

    await backupFile.delete();
  }
}
