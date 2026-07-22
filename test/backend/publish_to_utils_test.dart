import 'package:gg_localize_refs/src/backend/publish_to_utils.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('yaml_utils', () {
    group('addPublishToNone', () {
      test('adds publish_to: none after version if not present', () {
        const yaml = 'name: test\nversion: 1.0.0\n';
        final result = addPublishToNone(yaml);
        expect(result, 'name: test\nversion: 1.0.0\npublish_to: none\n');
      });

      test('does not add if already present', () {
        const yaml = 'name: test\nversion: 1.0.0\npublish_to: none\n';
        final result = addPublishToNone(yaml);
        expect(result, yaml);
      });

      test('adds at end if no version', () {
        const yaml = 'name: test';
        final result = addPublishToNone(yaml);
        expect(result, 'name: test\npublish_to: none\n');
      });

      test('keeps CRLF line endings when inserting after version', () {
        const yaml = 'name: test\r\nversion: 1.0.0\r\n';
        final result = addPublishToNone(yaml);
        expect(result, 'name: test\r\nversion: 1.0.0\r\npublish_to: none\r\n');
      });

      test('does not add if already present in a CRLF file', () {
        const yaml = 'name: test\r\nversion: 1.0.0\r\npublish_to: none\r\n';
        final result = addPublishToNone(yaml);
        expect(result, yaml);
      });

      test('adds at end with CRLF if no version', () {
        const yaml = 'name: test\r\ndescription: x';
        final result = addPublishToNone(yaml);
        expect(result, 'name: test\r\ndescription: x\r\npublish_to: none\r\n');
      });
    });

    group('removePublishToNone', () {
      test('removes publish_to: none if present', () {
        const yaml = 'name: test\nversion: 1.0.0\npublish_to: none\n';
        final result = removePublishToNone(yaml);
        expect(result, 'name: test\nversion: 1.0.0\n');
      });

      test('does nothing if not present', () {
        const yaml = 'name: test\nversion: 1.0.0\n';
        final result = removePublishToNone(yaml);
        expect(result, yaml);
      });

      test('removes a CRLF publish_to: none line completely', () {
        const yaml = 'name: test\r\nversion: 1.0.0\r\npublish_to: none\r\n';
        final result = removePublishToNone(yaml);
        expect(result, 'name: test\r\nversion: 1.0.0\r\n');
      });
    });

    group('backupPublishTo', () {
      test('backs up existing publish_to', () {
        final yamlMap = loadYaml('publish_to: some_repo') as Map;
        final backup = backupPublishTo(yamlMap);
        expect(backup['publish_to_original'], 'some_repo');
      });

      test('backs up null if not present', () {
        final yamlMap = loadYaml('name: test') as Map;
        final backup = backupPublishTo(yamlMap);
        expect(backup['publish_to_original'], isNull);
      });
    });

    group('restorePublishTo', () {
      test('restores original publish_to', () {
        const yaml =
            'name: test\nversion: 1.0.0\npublish_to: none\ndependencies:';
        final backup = {'publish_to_original': 'some_repo'};
        final result = restorePublishTo(yaml, backup);
        expect(
          result,
          'name: test\nversion: 1.0.0\npublish_to: some_repo\ndependencies:',
        );
      });

      test('removes if original was none or null', () {
        const yaml = 'name: test\nversion: 1.0.0\npublish_to: none\n';
        final backup = {'publish_to_original': null};
        final result = restorePublishTo(yaml, backup);
        expect(result, 'name: test\nversion: 1.0.0\n');
      });

      test('adds at end if no publish_to: none', () {
        const yaml = 'name: test';
        final backup = {'publish_to_original': 'some_repo'};
        final result = restorePublishTo(yaml, backup);
        expect(result, 'name: test\npublish_to: some_repo\n');
      });

      test('replaces in place in a CRLF file instead of appending a '
          'duplicate', () {
        // Regression: on Windows checkouts (core.autocrlf) the pubspec has
        // CRLF endings. The old `.*\n` regex missed the existing line and
        // appended a second `publish_to:` — pub then failed with
        // »Duplicate mapping key«.
        const yaml =
            'name: test\r\n'
            'version: 1.0.0\r\n'
            'repository: https://example.com/repo\r\n'
            'publish_to: none\r\n'
            '\r\n'
            'dependencies:\r\n';
        final backup = {'publish_to_original': 'none'};
        final result = restorePublishTo(yaml, backup);
        expect(result, yaml);
        expect(
          RegExp(r'^publish_to:', multiLine: true).allMatches(result).length,
          1,
        );
      });

      test('removes a CRLF publish_to line when original was null', () {
        const yaml = 'name: test\r\nversion: 1.0.0\r\npublish_to: none\r\n';
        final backup = {'publish_to_original': null};
        final result = restorePublishTo(yaml, backup);
        expect(result, 'name: test\r\nversion: 1.0.0\r\n');
      });

      test('appends with CRLF when the CRLF file has no publish_to', () {
        const yaml = 'name: test\r\nversion: 1.0.0';
        final backup = {'publish_to_original': 'some_repo'};
        final result = restorePublishTo(yaml, backup);
        expect(
          result,
          'name: test\r\nversion: 1.0.0\r\npublish_to: some_repo\r\n',
        );
      });

      test('replaces a publish_to line at the end of file without a '
          'trailing newline', () {
        const yaml = 'name: test\nversion: 1.0.0\npublish_to: none';
        final backup = {'publish_to_original': 'some_repo'};
        final result = restorePublishTo(yaml, backup);
        expect(result, 'name: test\nversion: 1.0.0\npublish_to: some_repo');
      });
    });
  });
}
