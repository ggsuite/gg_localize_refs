# Changelog

## [Unreleased]

### Changed

- Make publish\_to handling CRLF-safe so restore-publish-to no longer appends a duplicate publish\_to line on Windows checkouts
- gg\_multi: changed references to git

## [2.5.2] - 2026-07-20

### Fixed

- Write `.gg/*` instead of the bare `.gg` into `.gitignore`, so the `!.gg/.gg.json` re-include works and the check state reaches CI; a stale `.gg` is replaced where it stands
- Make the file-changes-buffer failure test independent of the user it runs as: it wrote below `/root`, which succeeds when the tests run as root (gg\_one\_server's container) and left the expected `FileSystemException` unthrown

## [2.5.1] - 2026-07-20

### Added

- Add rc prerelease channel to gg do publish (channel field/flag, X.Y.Z-rc.N computation, npm --tag rc, single + multi repo)

### Changed

- gg\_multi: changed references to git

## [2.5.0] - 2026-07-01

### Changed

- feat(gg): do checkout + .gg/.ticket.json ticket marker; TS format no direct eslint & P:\programs\flutter/bin/internal/exit\_with\_errorlevel.bat
- gg\_multi: changed references to git

## [2.4.1] - 2026-06-26

### Changed

- Preserve dependency constraint operator (^^/\~/exact) through publish
- gg\_multi: changed references to git

## [2.4.0] - 2026-06-19

### Changed

- Treat dart-typescript bridge repos as TypeScript for can/do review (npm install, skip dart pub get); export isBridgeProject from gg\_one
- Process cross-language bridge repos in BOTH languages during ref localization: processProject now builds+rewrites the workspace once per language the root supports (buildGraph forLanguage), so a bridge's pubspec.yaml and package.json are both localized/unlocalized
- set-ref-version updates the dependency in every manifest a bridge declares it in (per-language loop over present manifests), so a bridge's package.json dependency is no longer missed; single-language repos unchanged
- Publish bridges as TypeScript: pnpm-aware publish, dual-manifest version bump, non-swallowed publish errors, idempotent resume, review skips merged repos, link: for local TS deps, package.json scripts check
- gg\_multi: changed references to git
- Gg Multi: changed references to pub.dev

## [2.3.0] - 2026-06-09

### Changed

- feat(ts): version-pinned git deps via #semver: + tag-push for npm/pnpm
- refactor(ts): trim comments to grace-cloud style limits + do\_maintain layout
- style: apply grace-cloud comment + 80-char limits across ticket

### Fixed

- refactor(tests): drive TS unlocalize scenarios from test/sample\_folder\_ts fixtures

## [2.2.0] - 2026-06-08

### Changed

- feat(do add): auto-clone transitive deps into master before graph build & P:\programs\flutter/bin/internal/exit\_with\_errorlevel.bat
- gg\_multi: changed references to git
- gg\_multi: changed references to git

## [2.1.2] - 2026-05-11

### Changed

- fix: add tag\_pattern to git fallback in change-refs-to-pub-dev
- gg\_multi: changed references to git

## [2.1.1] - 2026-04-24

## [2.1.0] - 2026-04-23

### Changed

- kidney: changed references to local

## [2.0.2] - 2026-04-07

### Changed

- Kidney: changed references to pub.dev

## [2.0.1] - 2026-03-31

### Changed

- commit

## [2.0.0] - 2026-03-27

### Added

- Add shouldBackupPublishTo and related tests for publish\_to backup

### Changed

- kidney: changed references to path
- rename localize-refs and unlocalize-refs
- kidney: changed references to git

## [1.0.0] - 2026-03-24

### Added

- Initial boilerplate.
- Add git parameter to localize refs get
- Add commands to export
- Add tests for get ref and set ref
- Add get version command
- Add tests for process dependencies
- add .idea to .gitignore
- Add publish\_to: none when localizing
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
- Use sample\_folder for test files
- Create backend subfolder and move source files
- changed gg\_local\_package\_dependencies to git dependency
- Update repository URL to ggsuite organization
- Downgrade package version from 1.0.0 to 0.0.1

### Fixed

- Fix tests on windows

### Removed

- Update gg\_publish to ^^3.2.0 and remove publish\_to field

[Unreleased]: https://github.com/ggsuite/gg_localize_refs/compare/2.5.2...HEAD
[2.5.2]: https://github.com/ggsuite/gg_localize_refs/compare/2.5.1...2.5.2
[2.5.1]: https://github.com/ggsuite/gg_localize_refs/compare/2.5.0...2.5.1
[2.5.0]: https://github.com/ggsuite/gg_localize_refs/compare/2.4.1...2.5.0
[2.4.1]: https://github.com/ggsuite/gg_localize_refs/compare/2.4.0...2.4.1
[2.4.0]: https://github.com/ggsuite/gg_localize_refs/compare/2.3.0...2.4.0
[2.3.0]: https://github.com/ggsuite/gg_localize_refs/compare/2.2.0...2.3.0
[2.2.0]: https://github.com/ggsuite/gg_localize_refs/compare/2.1.2...2.2.0
[2.1.2]: https://github.com/ggsuite/gg_localize_refs/compare/2.1.1...2.1.2
[2.1.1]: https://github.com/ggsuite/gg_localize_refs/compare/2.1.0...2.1.1
[2.1.0]: https://github.com/ggsuite/gg_localize_refs/compare/2.0.2...2.1.0
[2.0.2]: https://github.com/ggsuite/gg_localize_refs/compare/2.0.1...2.0.2
[2.0.1]: https://github.com/ggsuite/gg_localize_refs/compare/2.0.0...2.0.1
[2.0.0]: https://github.com/ggsuite/gg_localize_refs/compare/1.0.0...2.0.0
[1.0.0]: https://github.com/ggsuite/gg_localize_refs/tag/%tag
