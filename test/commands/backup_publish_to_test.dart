// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_localize_refs/src/commands/backup_publish_to.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test_helpers.dart';

void main() {
  group('BackupPublishTo', () {
    late List<String> messages;
    late BackupPublishTo command;

    setUp(() {
      messages = <String>[];
      command = BackupPublishTo(ggLog: messages.add);
    });

    test('captures publish_to: none as the original value', () async {
      final dir = createTempDir('backup_publish_to_none');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pkg\n'
        'version: 1.0.0\n'
        'publish_to: none\n',
      );

      await command.exec(directory: dir, ggLog: messages.add);

      final backupFile = File(
        p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
      );
      expect(backupFile.existsSync(), isTrue);
      final backup =
          jsonDecode(backupFile.readAsStringSync()) as Map<String, dynamic>;
      expect(backup['publish_to_original'], 'none');

      deleteDirs(<Directory>[dir]);
    });

    test('captures null when publish_to is absent', () async {
      final dir = createTempDir('backup_publish_to_absent');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pkg\n'
        'version: 1.0.0\n',
      );

      await command.exec(directory: dir, ggLog: messages.add);

      final backupFile = File(
        p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
      );
      final backup =
          jsonDecode(backupFile.readAsStringSync()) as Map<String, dynamic>;
      expect(backup.containsKey('publish_to_original'), isTrue);
      expect(backup['publish_to_original'], isNull);

      deleteDirs(<Directory>[dir]);
    });

    test('captures custom publish_to value', () async {
      final dir = createTempDir('backup_publish_to_custom');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pkg\n'
        'version: 1.0.0\n'
        'publish_to: https://example.com/repo\n',
      );

      await command.exec(directory: dir, ggLog: messages.add);

      final backupFile = File(
        p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
      );
      final backup =
          jsonDecode(backupFile.readAsStringSync()) as Map<String, dynamic>;
      expect(backup['publish_to_original'], 'https://example.com/repo');

      deleteDirs(<Directory>[dir]);
    });

    test('does not overwrite an existing backup', () async {
      final dir = createTempDir('backup_publish_to_idempotent');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pkg\n'
        'version: 1.0.0\n'
        'publish_to: none\n',
      );

      await command.exec(directory: dir, ggLog: messages.add);

      // Simulate a later state where publish_to was injected by the
      // localize step. A second backup must NOT replace the original.
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pkg\n'
        'version: 1.0.0\n'
        'publish_to: https://injected.example.com\n',
      );

      await command.exec(directory: dir, ggLog: messages.add);

      final backupFile = File(
        p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
      );
      final backup =
          jsonDecode(backupFile.readAsStringSync()) as Map<String, dynamic>;
      expect(backup['publish_to_original'], 'none');

      deleteDirs(<Directory>[dir]);
    });

    test('skips when no pubspec.yaml is present', () async {
      final dir = createTempDir('backup_publish_to_no_pubspec');

      await command.exec(directory: dir, ggLog: messages.add);

      final backupFile = File(
        p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
      );
      expect(backupFile.existsSync(), isFalse);
      expect(messages.any((m) => m.contains('No pubspec.yaml found')), isTrue);

      deleteDirs(<Directory>[dir]);
    });

    test('handles an empty pubspec.yaml', () async {
      final dir = createTempDir('backup_publish_to_empty');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('');

      await command.exec(directory: dir, ggLog: messages.add);

      final backupFile = File(
        p.join(dir.path, '.gg', '.gg_localize_refs_publish_to_backup.json'),
      );
      final backup =
          jsonDecode(backupFile.readAsStringSync()) as Map<String, dynamic>;
      expect(backup['publish_to_original'], isNull);

      deleteDirs(<Directory>[dir]);
    });

    test('writes .gitignore entries for the backup directory', () async {
      final dir = createTempDir('backup_publish_to_gitignore');
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: pkg\n'
        'version: 1.0.0\n',
      );

      await command.exec(directory: dir, ggLog: messages.add);

      final gitignore = File(p.join(dir.path, '.gitignore'));
      expect(gitignore.existsSync(), isTrue);
      final contents = gitignore.readAsStringSync();
      expect(contents, contains('.gg'));
      expect(contents, contains('!.gg/.gg.json'));

      deleteDirs(<Directory>[dir]);
    });
  });
}
