// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_project_root/gg_project_root.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

// #############################################################################
/// An example command
class Local extends Command<dynamic> {
  /// Constructor
  Local({
    required this.ggLog,
  }) {
    _addArgs();
  }

  /// The log function
  final GgLog ggLog;

  /// Then name of the command
  @override
  final name = 'local';

  /// The description of the command
  @override
  final description = 'Changes dependencies to local dependencies.';

  // ...........................................................................
  @override
  Future<void> run() async {
    String? root = await GgProjectRoot.get(Directory('.').absolute.path);

    if (root == null) {
      ggLog('No root found');
      return;
    }

    Directory projectDir = Directory(root).parent;

    final pubspec = File('${projectDir.path}/pubspec.yaml');
    final pubspecContent = await pubspec.readAsString();
    late Pubspec pubspecYaml;
    try {
      pubspecYaml = Pubspec.parse(pubspecContent);
    } catch (e) {
      throw Exception(red('Error parsing pubspec.yaml:') + e.toString());
    }

    String packageName = pubspecYaml.name;

    Graph graph = Graph(ggLog: ggLog);
    Map<String, Node> nodes = await graph.get(
      directory: projectDir.parent,
      ggLog: ggLog,
    );

    Node? node = nodes[packageName];

    if (node == null) {
      ggLog('No node found for $packageName');
      return;
    }

    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      ggLog('Processing dependency ${dependency.key}');
    }

    // copy pubspec.yaml to pubspec.yaml.original
    File originalPubspec = File('${projectDir.path}/pubspec.yaml.original');
    if (await originalPubspec.exists()) {
      await originalPubspec.delete();
    }
    await pubspec.copy(originalPubspec.path);

    // change dependencies to local dependencies
    String newPubspecContent = pubspecContent;
    for (MapEntry<String, Node> dependency in node.dependencies.entries) {
      String dependencyName = dependency.key;
      String dependencyPath = dependency.value.directory.path;
      String newDependency = 'path: $dependencyPath';
      newPubspecContent =
          changeDependency(newPubspecContent, dependencyName, newDependency);
    }

    print(newPubspecContent);

    // write new pubspec.yaml.modified
    File modifiedPubspec = File('${projectDir.path}/pubspec.yaml.modified');
    if (await modifiedPubspec.exists()) {
      await modifiedPubspec.delete();
    }
    await modifiedPubspec.writeAsString(newPubspecContent);
  }

  String changeDependency(
      String pubspecContent, String dependency, String newValue) {
    // Erstelle einen YamlEditor mit dem aktuellen Inhalt
    final editor = YamlEditor(pubspecContent);

    // Lade den YAML-Inhalt als Map
    final yamlMap = loadYaml(pubspecContent) as Map;

    // Überprüfe, ob die 'dependencies'-Sektion existiert
    if (!yamlMap.containsKey('dependencies')) {
      throw Exception("Die 'dependencies'-Sektion wurde nicht gefunden.");
    }

    // Versuche, newValue als YAML zu parsen
    dynamic newDependencyValue;
    try {
      newDependencyValue = loadYaml(newValue);
    } catch (e) {
      // Falls Parsing fehlschlägt, behandle newValue als String
      newDependencyValue = newValue;
    }

    // Aktualisiere oder füge die Abhängigkeit hinzu
    editor.update(['dependencies', dependency], newDependencyValue);

    // Gib den aktualisierten YAML-Inhalt zurück
    return editor.toString();
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
