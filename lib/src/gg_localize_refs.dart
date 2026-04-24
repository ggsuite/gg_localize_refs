// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_localize_refs/src/commands/backup_publish_to.dart';
import 'package:gg_localize_refs/src/commands/change_refs_to_git_feature_branch.dart';
import 'package:gg_localize_refs/src/commands/change_refs_to_local.dart';
import 'package:gg_localize_refs/src/commands/change_refs_to_pub_dev.dart';
import 'package:gg_localize_refs/src/commands/get_ref_version.dart';
import 'package:gg_localize_refs/src/commands/get_version.dart';
import 'package:gg_localize_refs/src/commands/restore_publish_to.dart';
import 'package:gg_localize_refs/src/commands/set_ref_version.dart';
import 'package:gg_log/gg_log.dart';

/// The command line interface for GgToLocal.
class GgToLocal extends Command<dynamic> {
  /// Constructor.
  GgToLocal({required this.ggLog}) {
    addSubcommand(ChangeRefsToLocal(ggLog: ggLog));
    addSubcommand(ChangeRefsToGitFeatureBranch(ggLog: ggLog));
    addSubcommand(ChangeRefsToPubDev(ggLog: ggLog));
    addSubcommand(BackupPublishTo(ggLog: ggLog));
    addSubcommand(RestorePublishTo(ggLog: ggLog));
    addSubcommand(GetRefVersion(ggLog: ggLog));
    addSubcommand(SetRefVersion(ggLog: ggLog));
    addSubcommand(GetVersion(ggLog: ggLog));
  }

  /// The log function.
  final GgLog ggLog;

  @override
  final name = 'ggToLocal';

  @override
  final description = 'Add your description here.';
}
