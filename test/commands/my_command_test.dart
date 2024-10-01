// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_to_local/src/commands/my_command.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  late CommandRunner<void> runner;

  setUp(() {
    messages.clear();
    runner = CommandRunner<void>('test', 'test');
    final myCommand = MyCommand(ggLog: messages.add);
    runner.addCommand(myCommand);
  });

  group('MyCommand', () {
    group('run()', () {
      // .......................................................................
      group('should print a usage description', () {
        test('when called args=[--help]', () async {
          capturePrint(
            ggLog: messages.add,
            code: () => runner.run(
              ['--help'],
            ),
          );

          expect(messages.last, contains('Available commands:'));
          expect(
            messages.last,
            contains('my-command   Description of my command.'),
          );
        });
      });

      // .......................................................................
      group('should throw', () {
        test('if input is missing', () async {
          await expectLater(
            runner.run(
              ['my-command'],
            ),
            throwsA(
              isA<ArgumentError>().having(
                (e) => e.message,
                'message',
                contains('Option input is mandatory.'),
              ),
            ),
          );
        });
      });

      // .......................................................................
      group('should succeed', () {
        test('when called with right input param', () async {
          await runner.run(['my-command', '--input', 'test']);
          expect(messages, ['Running my-command with param test']);
        });
      });
    });
  });
}
