<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Development guide

[Install the required software](./install-guide.md)

[Prepare a GG workspace](./install-guide/install-gg-workspace-guide.md)

Switch into the workspace

```bash
cd ~/dev/ # workspace
```

Start claude

```bash
claude
```

Start the development in Claude

```bash
/gg-ticket
```

Use the following skills in Claude

```bash
/gg-commit
/gg-push
/gg-review
/gg-publish
/gg-cleanup
```

`/gg` lists the skills of the workflow and says which one comes next.

## Your prompts

When the repo belongs to a project management repo, every prompt you write
to Claude Code is kept there, under `doc/prompts/<your first name>/` on the
branch `prompts`. Only the prompts, not the answers. Tokens and passwords
are replaced by `[redacted]`. Your first name comes from
`doc/team/people.md` in the project management repo: the person whose
first name is your git user name or its first word, or whose `Git` line
lists your git user name. Otherwise your prompts land in
`doc/prompts/_unknown/`. Your e-mail address never goes there.
