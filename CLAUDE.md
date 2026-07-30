# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`gg_localize_refs` is a Dart CLI + library that switches a package and its local sibling checkouts between three mutually exclusive dependency modes:

- **local** — `dependency_overrides` with `path: ../other_pkg` in `pubspec_overrides.yaml`; `pubspec.yaml` is **not** touched. The file is committed: its paths are relative, so it travels with a shared ticket workspace,
- **git feature branch** — git refs written into `pubspec.yaml`,
- **pub.dev** — published version constraints in `pubspec.yaml`.

It supports both Dart projects (`pubspec.yaml`) and TypeScript/JavaScript projects (`package.json`) side-by-side in the same workspace. TypeScript keeps its own scheme unchanged: `link:` specs are written straight into `package.json`, with the original specs backed up in `.gg_localize_refs_backup.json` at the project root.

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
`change-refs-to-local`, `change-refs-to-git-feature-branch`, `change-refs-to-pub-dev`, `backup-publish-to`, `restore-publish-to`, `get-ref-version`, `set-ref-version`, `get-version`.

`test/gg_localize_refs_test.dart` asserts every file under `lib/src/commands/` is registered — put helpers in `lib/src/backend/`, not there.

Commit/push go through `gg do commit` / `gg do push` (never raw `git commit`/`git push`).

## The three modes

Exactly one mode is active at a time. The invariant each command establishes:

| Mode | `pubspec.yaml` | `pubspec_overrides.yaml` | `publish_to` |
| --- | --- | --- | --- |
| local | version constraints, untouched | `dependency_overrides` with `path:`, committed | untouched |
| git feature branch | git refs (`git: {url, ref}`) | absent | `none` injected |
| pub.dev | version constraints | absent | restored via `restore-publish-to` |

Rules that follow from it:

- `change-refs-to-local` writes only `pubspec_overrides.yaml`. It **never** edits `pubspec.yaml` except to undo an earlier localization (see migration below).
- `change-refs-to-git-feature-branch` and `change-refs-to-pub-dev` remove the path overrides **before** their own "nothing to do" early-out — a repo in local mode has a pristine `pubspec.yaml`, so a check on the manifest would skip the removal and leave the overrides shadowing the new refs.
- Removal is structural: an entry is dropped when it is a bare `path:` pointing at a sibling checkout whose package name matches the key (`PubspecOverridesIo.isOwnedPathOverride`). pub only accepts `dependency_overrides`, `resolution` and `workspace` in that file, so an ownership marker key is not possible. Hand written entries and `resolution:`/`workspace:` survive; the file is deleted only when nothing but an empty section remains.
- Pub does **not** merge the two override sections: once `pubspec_overrides.yaml` exists, the `dependency_overrides` of `pubspec.yaml` are silently ignored. They are therefore copied into the written file.
- An override for a package that is no longer a dependency is pruned — pub pulls every overridden package into the resolution, declared or not.
- A bare `path:` override pointing at a **missing sibling** is pruned too, even though ownership can no longer be proven (the package name it would have to match is unreadable once the checkout is gone). It is the exact shape this tool writes, pub fails hard on it, and while it stays the overrides file cannot be deleted either — so the workspace could never leave local mode. A path reaching further out (a vendored `../../vendor/x`) is left alone.
- `pubspec_overrides.yaml` must **not** be gitignored, so `change-refs-to-local` *removes* such an entry (anchored or not) instead of adding one. Reasons, all measured: the file holds only relative paths, so committing it is what makes a shared ticket workspace resolve against the sibling checkouts — the same guarantee the committed `path:` refs used to give; pub excludes the package-root `pubspec_overrides.yaml` from `dart pub publish` unconditionally (verified with the file git-tracked and no `.gitignore` present: 0 warnings), so committing it cannot leak into a release; and gitignored **and** checked in is the one combination that makes publishing fail with "checked-in files are ignored by a `.gitignore`" (exit 65). Several repositories of the suite still carry the entry by hand — running `change-refs-to-local` there clears it.
- In a pub workspace, overriding the same package in the workspace root and in a member is a hard `pub get` failure. No repo of the suite uses `resolution: workspace` today.

### Migration of a legacy workspace

An earlier version wrote the local paths into `pubspec.yaml` itself and injected `publish_to: none`. `change-refs-to-local` undoes that before writing the overrides file:

- `path:` refs and version-less git refs are restored from `.gg/.gg_localize_refs_backup.json` — **verbatim**, via `ChangeRefsToPubDev.restoreDartRefs(reconstructGitRefs: false)`. The networkless pub.dev reconstruction must not run here: `IsOnPubDev` reads the *dependency's* `publish_to`, which the old localization set to `none` for every repo of a ticket, so every dependency would be rewritten into a git ref with an invented `tag_pattern` — and a checkout without an `origin` remote would abort the command.
- Without a dependency backup nothing is guessed: the manifest is left alone and the user is warned.
- `publish_to: none` is reverted only when `.gg/.gg_localize_refs_publish_to_backup.json` says it was not the original value. Without that backup it is kept (it cannot be told apart from a package that is private by intention) and the user is warned. The backup file is **not** deleted — git feature branch mode still injects `publish_to: none` and needs it.

## Architecture

Entry point `bin/gg_localize_refs.dart` wires a `GgCommandRunner` (from `gg_args`) to the root `GgToLocal` command, which adds the subcommands above. Each subcommand lives in `lib/src/commands/` and operates on a directory passed via `-i`.

`lib/src/backend/pubspec_overrides_io.dart` owns everything about `pubspec_overrides.yaml`. It computes a `PubspecOverridesEdit` (unchanged / write / delete) without touching the disk, merging into an existing file via `yaml_edit` so comments and foreign entries survive. Never build that YAML by string interpolation: an unquoted path containing `:` is a parse error and one containing `#` is silently truncated.

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
2. Resolves the workspace root (`workspaceRootOf`): normally the **parent** of the project. A gg workspace may group its repositories in a folder named after their organization (`<workspace>/<org>/<repo>`) — then the **grandparent** is the root, recognized by the marker every gg workspace carries (the master workspace by its `.master` folder name, a ticket workspace by its `.ticket` file). A plain folder of sibling checkouts outside a gg workspace keeps resolving to the parent.
3. Collects the candidate directories (`projectCandidateDirs`): the immediate subdirectories of the workspace root plus the children of each of them that is a *grouping folder* — a visible directory that is neither a project of any registered language nor a git repository. An organization folder is one, a repository is not, so projects nested inside a repository (`example/`, fixtures) stay invisible. For each candidate that `language.isProjectRoot` recognizes, `createNode` is called. A single `buildGraph` pass covers one language; duplicate names throw.
4. Cross-links nodes by walking each node's declared deps; if a dep name matches another discovered node, it is wired into both `dependencies` and the counterpart's `dependents`.
5. Returns `(rootNode, allNodes)`.

A **cross-language bridge** (pubspec.yaml + package.json + tsconfig.json) is a project root for more than one language. `MultiLanguageGraph.findRootAndLanguages` reports every language a root supports, and `processProject` (in `process_dependencies.dart`) builds + processes the workspace **once per language** (`buildGraph(forLanguage: …)`), so a bridge's Dart manifest and TypeScript manifest are both rewritten. A single-language repo is processed exactly once.

Only the Dart pass reaches the `pubspec_overrides.yaml` logic, so a bridge's overrides file is written once. Keep it that way: `PubspecOverridesIo` reads the file from disk, so two passes editing it would not see each other's buffered edit.

Commands then traverse this graph (see `process_dependencies.dart`, `replace_dependency.dart`, `manifest_command_support.dart`) to rewrite manifests consistently. `file_changes_buffer.dart` batches writes **and deletions** (`addDeletion`) so a failure partway through does not leave the workspace half-rewritten; all parsing happens while computing the edits, so `apply()` can only fail on I/O. Report "No files were changed." from `isEmpty`, which covers deletions too — a queued no-op must therefore never be added.

### Adding a new language

Implement `ProjectLanguage` + register it in the `languages:` list passed to `MultiLanguageGraph`. All commands flow through that abstraction — no command code should branch on language.

## Tests

Fixture-based. `test/sample_folder/` holds Dart fixtures; `test/sample_folder_ts/` holds TypeScript fixtures. Tests under `test/commands/` and `test/backend/` run scenarios against copies of these fixtures via helpers in `test/test_helpers.dart`. When touching graph or rewrite logic, add/adjust a fixture under the relevant scenario folder rather than inventing ad-hoc dirs. `test/sample_folder/**` is excluded from analysis (see `analysis_options.yaml`).

Mode-related scenarios under `test/sample_folder/localize_refs/`: `already_localized` (new style, drives the idempotency test), `legacy_localized` / `legacy_localized_private` / `legacy_localized_no_backup` (the three publish_to migration cases), `overrides_unrelated` (hand written overrides file), `git_overrides_present`; plus `unlocalize_refs/overrides_present`.

## Code Standards

- **Line length**: 80 characters maximum (`lines_longer_than_80_chars`).
- **Quotes**: single quotes (`prefer_single_quotes`).
- **Trailing commas**: required (`require_trailing_commas`).
- **Return types**: always declared (`always_declare_return_types` is an error, not a warning).
- **Public API docs**: required on all public members (`public_member_api_docs`).
- **Strict analyzer**: `strict-casts`, `strict-inference`, `strict-raw-types` all enabled.
- **Const**: prefer const constructors, declarations, and literals where applicable.
