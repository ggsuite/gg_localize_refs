// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_localize_refs/src/commands/unlocalize_refs.dart';
import 'commands/localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_localize_refs/src/commands/get_ref_version.dart';
import 'package:gg_localize_refs/src/commands/set_ref_version.dart';
import 'package:gg_localize_refs/src/commands/get_version.dart';

/// The command line interface for GgToLocal
class GgToLocal extends Command<dynamic> {
  /// Constructor
  GgToLocal({required this.ggLog}) {
    addSubcommand(LocalizeRefs(ggLog: ggLog));
    addSubcommand(UnlocalizeRefs(ggLog: ggLog));
    addSubcommand(GetRefVersion(ggLog: ggLog));
    addSubcommand(SetRefVersion(ggLog: ggLog));
    addSubcommand(GetVersion(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  // ...........................................................................
  @override
  final name = 'ggToLocal';
  @override
  final description = 'Add your description here.';
}
