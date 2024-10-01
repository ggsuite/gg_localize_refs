// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

// #############################################################################
/// An example command
class MyCommand extends Command<dynamic> {
  /// Constructor
  MyCommand({
    required this.ggLog,
  }) {
    _addArgs();
  }

  /// The log function
  final GgLog ggLog;

  /// Then name of the command
  @override
  final name = 'my-command';

  /// The description of the command
  @override
  final description = 'Description of my command.';

  // ...........................................................................
  @override
  Future<void> run() async {
    input = argResults!['input'] as String;
    ggLog('Running $name with param $input');
  }

  // ...........................................................................
  void _addArgs() {
    argParser.addOption(
      'input',
      abbr: 'i',
      help: 'The subcommands input param.',
      mandatory: true,
    );
  }

  // ...........................................................................
  /// Replace by your parameter
  late String input;
}
