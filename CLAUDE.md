# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`gg_localize_refs` is a Dart CLI + library that rewrites dependency references in a package's manifest. It can switch a package and its local sibling checkouts between:

- local path refs (`path: ../other_pkg`),
- git refs pinned to a feature branch,
- published pub.dev versions.

It supports both Dart projects (`pubspec.yaml`) and TypeScript/JavaScript projects (`package.json`) side-by-side in the same workspace.

## Commands

Dart SDK `>=3.8.0 <4.0.0`.

- Install deps: `dart pub get`
- Analyze: `dart analyze`
- Format: `dart format .`
- Run all tests: `dart test`
- Run one test file: `dart test test/commands/change_refs_to_local_test.dart`
- Run tests by name: `dart test -N "<substring>"`
- Run the CLI locally: `dart run bin/gg_localize_refs.dart <subcommand> [-i <dir>]`
- Install globally from source: `dart pub global activate --source path .`

Subcommands registered by `GgToLocal` (`lib/src/gg_localize_refs.dart`):
`changeRefsToLocal`, `changeRefsToGitFeatureBranch`, `changeRefsToPubDev`, `getRefVersion`, `setRefVersion`, `getVersion`.

Commit/push go through `gg do commit` / `gg do push` (never raw `git commit`/`git push`).

## Architecture

Entry point `bin/gg_localize_refs.dart` wires a `GgCommandRunner` (from `gg_args`) to the root `GgToLocal` command, which adds the six subcommands above. Each subcommand lives in `lib/src/commands/` and operates on a directory passed via `-i`.

### Language abstraction (`lib/src/backend/languages/`)

`ProjectLanguage` is the central extension point. It describes one supported manifest format:

- `manifestFileName` — `pubspec.yaml` or `package.json`
- `isProjectRoot(dir)` — detection
- `createNode(dir)` — parse + build a `ProjectNode`
- `readDeclaredDependencies(node)` — name → raw spec map
- `findDependency` / `listDependencyReferences` — locate entries across dep sections
- `replaceDependencyInContent(...)` — in-place, format-preserving rewrite of a single dep
- `readPackageVersion` / `stringifyManifest`

Concrete implementations: `DartPackageLanguage` (uses `yaml` + `yaml_edit` to keep formatting/comments intact) and `TypeScriptPackageLanguage` (JSON).

A `ProjectNode` carries `name`, `directory`, `language`, plus `dependencies` and `dependents` maps populated during graph construction.

### Graph construction (`lib/src/backend/multi_language_graph.dart`)

`MultiLanguageGraph.buildGraph(directory)`:

1. Finds the project root from the starting directory and picks the matching language.
2. Treats the **parent** directory as the workspace root and scans its immediate subdirectories.
3. For each sibling directory that `language.isProjectRoot` recognizes, calls `createNode`. Only projects in the **same language** as the root are included; duplicate names throw.
4. Cross-links nodes by walking each node's declared deps; if a dep name matches another discovered node, it is wired into both `dependencies` and the counterpart's `dependents`.
5. Returns `(rootNode, allNodes)`.

Commands then traverse this graph (see `process_dependencies.dart`, `replace_dependency.dart`, `manifest_command_support.dart`) to rewrite manifests consistently. `file_changes_buffer.dart` batches writes so a failure partway through does not leave the workspace half-rewritten.

### Adding a new language

Implement `ProjectLanguage` + register it in the `languages:` list passed to `MultiLanguageGraph`. All commands flow through that abstraction — no command code should branch on language.

## Tests

Fixture-based. `test/sample_folder/` holds Dart fixtures; `test/sample_folder_ts/` holds TypeScript fixtures. Tests under `test/commands/` and `test/backend/` run scenarios against copies of these fixtures via helpers in `test/test_helpers.dart`. When touching graph or rewrite logic, add/adjust a fixture under the relevant scenario folder rather than inventing ad-hoc dirs. `test/sample_folder/**` is excluded from analysis (see `analysis_options.yaml`).

## Code Standards

- **Line length**: 80 characters maximum (`lines_longer_than_80_chars`).
- **Quotes**: single quotes (`prefer_single_quotes`).
- **Trailing commas**: required (`require_trailing_commas`).
- **Return types**: always declared (`always_declare_return_types` is an error, not a warning).
- **Public API docs**: required on all public members (`public_member_api_docs`).
- **Strict analyzer**: `strict-casts`, `strict-inference`, `strict-raw-types` all enabled.
- **Const**: prefer const constructors, declarations, and literals where applicable.
