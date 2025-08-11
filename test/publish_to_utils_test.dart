import 'package:gg_localize_refs/src/publish_to_utils.dart';
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
    });
  });
}
