// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_localize_refs/src/backend/package_json_io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PackageJsonIo', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('package_json_io_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    File pkg() => File(p.join(tmp.path, 'package.json'));

    group('readVersion', () {
      test('returns the version field for a valid file', () {
        pkg().writeAsStringSync('{"name":"x","version":"1.2.3"}');
        expect(PackageJsonIo.readVersion(tmp), '1.2.3');
      });

      test('returns null when package.json does not exist', () {
        expect(PackageJsonIo.readVersion(tmp), isNull);
      });

      test('returns null for invalid JSON', () {
        pkg().writeAsStringSync('{not json');
        expect(PackageJsonIo.readVersion(tmp), isNull);
      });

      test('returns null when the top-level value is not an object', () {
        pkg().writeAsStringSync('["array"]');
        expect(PackageJsonIo.readVersion(tmp), isNull);
      });

      test('returns null when the "version" field is missing', () {
        pkg().writeAsStringSync('{"name":"x"}');
        expect(PackageJsonIo.readVersion(tmp), isNull);
      });

      test('returns null when the "version" field is not a string', () {
        pkg().writeAsStringSync('{"name":"x","version":123}');
        expect(PackageJsonIo.readVersion(tmp), isNull);
      });

      test('returns null when the "version" field is the empty string', () {
        pkg().writeAsStringSync('{"name":"x","version":""}');
        expect(PackageJsonIo.readVersion(tmp), isNull);
      });
    });

    group('isPrivate', () {
      test('returns true when "private": true', () {
        pkg().writeAsStringSync('{"name":"x","private":true}');
        expect(PackageJsonIo.isPrivate(tmp), isTrue);
      });

      test('returns false when "private": false', () {
        pkg().writeAsStringSync('{"name":"x","private":false}');
        expect(PackageJsonIo.isPrivate(tmp), isFalse);
      });

      test('returns false when the field is missing', () {
        pkg().writeAsStringSync('{"name":"x"}');
        expect(PackageJsonIo.isPrivate(tmp), isFalse);
      });

      test('returns false when "private" is a non-bool truthy value', () {
        // Only the literal `true` counts; stringly flags are not private.
        pkg().writeAsStringSync('{"name":"x","private":"yes"}');
        expect(PackageJsonIo.isPrivate(tmp), isFalse);
      });

      test('returns false when package.json does not exist', () {
        expect(PackageJsonIo.isPrivate(tmp), isFalse);
      });

      test('returns false on invalid JSON', () {
        pkg().writeAsStringSync('{not json');
        expect(PackageJsonIo.isPrivate(tmp), isFalse);
      });

      test('returns false when the top-level value is not an object', () {
        pkg().writeAsStringSync('"private string"');
        expect(PackageJsonIo.isPrivate(tmp), isFalse);
      });
    });
  });
}
