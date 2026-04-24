// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/commands/restore_publish_to.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('RestorePublishTo', () {
    late List<String> messages;
    late RestorePublishTo command;

    setUp(() {
      messages = <String>[];
      command = RestorePublishTo(ggLog: messages.add);
    });

    void writeBackup(Directory dir, Map<String, dynamic> map) {
      final file = File(
        p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
      )..createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(map));
    }

    test('keeps publish_to: none when original was none', () async {
      final dir = createTempDir('restore_publish_to_none');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pkg\n'
        'version: 1.0.0\n'
        'publish_to: none\n',
      );
      writeBackup(dir, <String, dynamic>{'publish_to_original': 'none'});

      await command.exec(directory: dir, ggLog: messages.add);

      final pubspec = File(p.join(dir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('publish_to: none'));
      expect(
        File(
          p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
        ).existsSync(),
        isFalse,
      );

      deleteDirs(<Directory>[dir]);
    });

    test('removes publish_to: none when original was absent', () async {
      final dir = createTempDir('restore_publish_to_remove');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pkg\n'
        'version: 1.0.0\n'
        'publish_to: none\n',
      );
      writeBackup(dir, <String, dynamic>{'publish_to_original': null});

      await command.exec(directory: dir, ggLog: messages.add);

      final pubspec = File(p.join(dir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, isNot(contains('publish_to:')));
      expect(
        File(
          p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
        ).existsSync(),
        isFalse,
      );

      deleteDirs(<Directory>[dir]);
    });

    test('restores a custom publish_to value', () async {
      final dir = createTempDir('restore_publish_to_custom');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pkg\n'
        'version: 1.0.0\n'
        'publish_to: none\n',
      );
      writeBackup(dir, <String, dynamic>{
        'publish_to_original': 'https://example.com/repo',
      });

      await command.exec(directory: dir, ggLog: messages.add);

      final pubspec = File(p.join(dir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('publish_to: https://example.com/repo'));
      expect(pubspec, isNot(contains('publish_to: none')));

      deleteDirs(<Directory>[dir]);
    });

    test('leaves pubspec untouched when no backup exists', () async {
      final dir = createTempDir('restore_publish_to_no_backup');
      const original =
          'name: pkg\n'
          'version: 1.0.0\n'
          'publish_to: none\n';
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(original);

      await command.exec(directory: dir, ggLog: messages.add);

      final pubspec = File(p.join(dir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, original);
      expect(
        messages.any((m) => m.contains('No publish_to backup found')),
        isTrue,
      );

      deleteDirs(<Directory>[dir]);
    });

    test('skips when no pubspec.yaml exists', () async {
      final dir = createTempDir('restore_publish_to_no_pubspec');
      writeBackup(dir, <String, dynamic>{'publish_to_original': 'none'});

      await command.exec(directory: dir, ggLog: messages.add);

      expect(messages.any((m) => m.contains('No pubspec.yaml found')), isTrue);
      // Backup file is left untouched when pubspec is missing.
      expect(
        File(
          p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
        ).existsSync(),
        isTrue,
      );

      deleteDirs(<Directory>[dir]);
    });
  });
}
