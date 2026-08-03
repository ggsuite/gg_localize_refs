# Changelog

## 3.3.2 - 2026-08-03

### Changed

- Prevent pubspec.lock interrupting publishing

### Fixed

- Fix issues with pubspec.lock

## 3.4.0 - 2026-08-01

### Fixed

- Override transitive workspace dependencies too. Pub honors
`dependency_overrides` only from the root package of a resolution, so a
project two steps down was resolved from pub.dev while its siblings came
from the ticket workspace.

## 3.3.1 - 2026-08-01

### Changed

- gg_localize_refs: write overrides for transitive local dependencies

## 3.3.0 - 2026-08-01

### Fixed

- Fix missing git references

### Removed

- Remove code modifying publish_to because it is not used anymore

## 3.2.2 - 2026-08-01

### Changed

- Fix: Skipping unchanged repos from publishing does not work
- Make sure package is already published in registry before publishing
- Adapt first-publish gate to merge-only mode. Make sure package is at least one time published before publishing.

### Fixed

- Fix error with branch names that do only contain numbers

## 3.2.1 - 2026-08-01

### Changed

- Adapt first-publish gate to merge-only mode from main

## 3.2.0 - 2026-08-01

### Changed

- \#gg: changed references to git
- \#gg: changed references to pub.dev

## 3.1.0 - 2026-07-31

### Changed

- Don't hide files in .gg folder

## 3.0.0 - 2026-07-31

## 2.7.1 - 2026-07-30

## 2.7.0 - 2026-07-30

### Changed

- BREAKING: change-refs-to-local writes the local paths as
dependency_overrides into pubspec_overrides.yaml and does not edit
pubspec.yaml anymore, so a localized package keeps its published constraints
- BREAKING: change-refs-to-local does not inject publish_to: none anymore -
pubspec.yaml stays publishable while the refs are localized
- change-refs-to-git-feature-branch and change-refs-to-pub-dev remove
the local path overrides, so exactly one of the three modes is ever active
- change-refs-to-local migrates a workspace that an earlier version localized
inside pubspec.yaml: the dependency backup is restored, an injected
publish_to: none is reverted, and the paths move to pubspec_overrides.yaml
- pubspec_overrides.yaml is committed - it holds relative paths only, so a
shared ticket workspace keeps resolving against the sibling checkouts;
change-refs-to-local removes a stale .gitignore entry for it, because
gitignored plus checked in makes dart pub publish fail
- change-refs-to-local drops an override of a dependency that left
pubspec.yaml, and one whose sibling checkout is gone - pub cannot resolve
either, and the second kind also blocked deleting the file
- dependency_overrides declared in pubspec.yaml are carried over into
pubspec_overrides.yaml, because pub replaces that section instead of merging
- change-refs-to-local writes no dependency backup anymore - pubspec.yaml
remains the single source of truth for the remote refs
- TypeScript projects are unchanged: package.json keeps carrying the link: specs
- Use pubspec_override.yaml instead of editing pubspec.yaml files
- Commit pubspec_overrides.yaml to share it with others

## 2.6.0 - 2026-07-29

### Changed

- Support projects without manifest: ProjectType.none, checks skipped, version tracked as git tag only
- gg_multi: changed references to git

## 2.5.4 - 2026-07-25

### Fixed

- FIX: tag_patterns get lost when publishing

## 2.5.3 - 2026-07-22

### Changed

- Make publish_to handling CRLF-safe so restore-publish-to no longer appends a duplicate publish_to line on Windows checkouts
- gg_multi: changed references to git

## 2.5.2 - 2026-07-20

### Fixed

- Write `.gg/*` instead of the bare `.gg` into `.gitignore`, so the `!.gg/.gg.json` re-include works and the check state reaches CI; a stale `.gg` is replaced where it stands
- Make the file-changes-buffer failure test independent of the user it runs as: it wrote below `/root`, which succeeds when the tests run as root (gg_one_server's container) and left the expected `FileSystemException` unthrown

## 2.5.1 - 2026-07-20

### Added

- Add rc prerelease channel to gg do publish (channel field/flag, X.Y.Z-rc.N computation, npm --tag rc, single + multi repo)

### Changed

- gg_multi: changed references to git

## 2.5.0 - 2026-07-01

### Changed

- feat(gg): do checkout + .gg/.ticket.json ticket marker; TS format no direct eslint & P:\programs\flutter/bin/internal/exit_with_errorlevel.bat
- gg_multi: changed references to git

## 2.4.1 - 2026-06-26

### Changed

- Preserve dependency constraint operator (^^/~/exact) through publish
- gg_multi: changed references to git

## 2.4.0 - 2026-06-19

### Changed

- Treat dart-typescript bridge repos as TypeScript for can/do review (npm install, skip dart pub get); export isBridgeProject from gg_one
- Process cross-language bridge repos in BOTH languages during ref localization: processProject now builds+rewrites the workspace once per language the root supports (buildGraph forLanguage), so a bridge's pubspec.yaml and package.json are both localized/unlocalized
- set-ref-version updates the dependency in every manifest a bridge declares it in (per-language loop over present manifests), so a bridge's package.json dependency is no longer missed; single-language repos unchanged
- Publish bridges as TypeScript: pnpm-aware publish, dual-manifest version bump, non-swallowed publish errors, idempotent resume, review skips merged repos, link: for local TS deps, package.json scripts check
- gg_multi: changed references to git
- Gg Multi: changed references to pub.dev

## 2.3.0 - 2026-06-09

### Changed

- feat(ts): version-pinned git deps via #semver: + tag-push for npm/pnpm
- refactor(ts): trim comments to grace-cloud style limits + do_maintain layout
- style: apply grace-cloud comment + 80-char limits across ticket

### Fixed

- refactor(tests): drive TS unlocalize scenarios from test/sample_folder_ts fixtures

## 2.2.0 - 2026-06-08

### Changed

- feat(do add): auto-clone transitive deps into master before graph build & P:\programs\flutter/bin/internal/exit_with_errorlevel.bat
- gg_multi: changed references to git
- gg_multi: changed references to git

## 2.1.2 - 2026-05-11

### Changed

- fix: add tag_pattern to git fallback in change-refs-to-pub-dev
- gg_multi: changed references to git

## 2.1.1 - 2026-04-24

## 2.1.0 - 2026-04-23

### Changed

- kidney: changed references to local

## 2.0.2 - 2026-04-07

### Changed

- Kidney: changed references to pub.dev

## 2.0.1 - 2026-03-31

### Changed

- commit

## 2.0.0 - 2026-03-27

### Added

- Add shouldBackupPublishTo and related tests for publish_to backup

### Changed

- kidney: changed references to path
- rename localize-refs and unlocalize-refs
- kidney: changed references to git

## 1.0.0 - 2026-03-24

### Added

- Initial boilerplate.
- Add git parameter to localize refs get
- Add commands to export
- Add tests for get ref and set ref
- Add get version command
- Add tests for process dependencies
- add .idea to .gitignore
- Add publish_to: none when localizing
- Add .gitattributes file
- Add --git-ref option to change-refs-to-local for custom git refs
- Add test for updating .gitignore with missing .gg entries
- Add tests for devDependencies handling in TS localize/unlocalize
- Add tests for dependency and manifest methods in language tests
- Add canCheckout to .gg.json; rename example and update print msg

### Changed

- Automatic checks
- Collect all nodes in allNodesMap
- posix style path
- change ggLog parameter to optional
- Use sample_folder for test files
- Create backend subfolder and move source files
- changed gg_local_package_dependencies to git dependency
- Update repository URL to ggsuite organization
- Downgrade package version from 1.0.0 to 0.0.1

### Fixed

- Fix tests on windows

### Removed

- Update gg_publish to ^^3.2.0 and remove publish_to field
