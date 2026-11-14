<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Check the refs of many projects with one read

## Motivation

- `UnlocalizedRefs.get` answers for one project which of its workspace
  refs are not localized. To do so it builds the graph of the whole
  workspace: every manifest beside the project and, in a gg ticket, every
  manifest of the ocean
- That is fine for one project. A caller that checks all projects of a
  workspace reads the same workspace and the same ocean once per project:
  ten projects, ten readings of the very same files
- The work grows with the square of the number of projects, although
  nothing changes between two checks: the pass only reads
- The last post left this open: reading the ocean costs about 40 ms per
  graph build (warm, ~80 repos), and a cache would pay off once many
  graphs are built. A pass over many projects is that case

## Strategy

- Offer one call for many projects, `UnlocalizedRefs.getAll`, next to
  `get` for a single one
- Let the graph builder keep the nodes of a workspace it has read, but
  only when asked to (`reuseWorkspaces`). The default stays: every graph
  is read anew
- Limit the reuse to one pass. Nothing is kept between two calls, so a
  manifest that changed in between is always seen
- Keep the answers identical to `get`. The tests compare both for every
  project

## UnlocalizedRefs.getAll

- `getAll(directories:, ggLog:)` returns one list of `UnlocalizedRef` per
  directory, in the order of the directories
- Each list is what `get` answers for that project: missing overrides,
  stale ones and embedded packages outside the pub workspace
- Projects that share a workspace share one reading of it and of its
  ocean
- Every call of `getAll` builds its own graph. What `change-refs-to-local`
  wrote since the last call shows up in the next one
- A directory without a project root throws, as with `get`
- `get` and the command line `unlocalized-refs` work as before

## MultiLanguageGraph takes reuseWorkspaces

- `MultiLanguageGraph(reuseWorkspaces: true)` reads the projects of a
  workspace once per language and instance. `buildGraph` for another
  project of that workspace answers from the nodes it already has and
  only picks another root node
- The nodes are kept by language and by the canonical path of the
  workspace root. A bridge with a Dart and a TypeScript manifest is read
  once for each language
- The reading itself moved into `_readWorkspace`; finding the root node
  among the nodes stays in `buildGraph`
- `workspaceGraph(reuseWorkspaces:)` creates the graph builder for all
  supported languages. `buildRootGraphs` takes such a `graph:` and
  creates one itself when it gets none
- The rule that comes with it: never reuse while manifests change. The
  nodes would be the ones from before the change. So only the read-only
  check uses it; the commands that rewrite refs read anew

## Tests

- `reuseWorkspaces`: three projects of one workspace get the very same
  nodes, each with its own root; another language is read again; off by
  default
- `getAll()`: no projects, the same answers as `get`, the order of the
  projects, a chain through the ocean (scenario `through_ocean`), changes
  written between two calls, a directory without a project root
- Six `--help` tests called `capturePrint` without `await`; they now wait
  for the captured code before they check its output

## Open Points

- The command line still checks one project per call. `getAll` is for
  callers of the library
- `getAll` checks its projects one after the other. Only the reading of
  the workspace is shared, the comparison with the overrides on disk
  still runs per project
- No time was measured for `getAll` in this repo. The known number is the
  cost of one graph build, which a pass now pays once per workspace
  instead of once per project
- `CLAUDE.md` still says the ocean is read once per `buildGraph` pass.
  With `reuseWorkspaces` it is once per workspace and language
