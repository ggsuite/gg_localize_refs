# Changelog

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

[2.0.1]: https://github.com/ggsuite/gg_localize_refs/compare/2.0.0...2.0.1
[2.0.0]: https://github.com/ggsuite/gg_localize_refs/compare/1.0.0...2.0.0
[1.0.0]: https://github.com/ggsuite/gg_localize_refs/tag/%tag
