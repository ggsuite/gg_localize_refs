<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Development guide for AIs

## Ask the developer for the ticket infos

Ask for these one after the other and give the developer a single input
field per answer — one question per field, never all of them in one
question and never as a plain prose question:

- Ask for the ticket ID
- Ask for the ticket title
- Ask for the ticket description

## Replace in this document

- Replace `~/dev/` by the workspace directory from the memory
- Ask for the workspace directory if none is known
- Replace `gGS-145` by the ticket ID you asked for
- Replace `Fix issue abc` by the ticket title you asked for

## Create a ticket

```bash
cd ~/dev/ # workspace
gg do create ticket gGS-145 -m"Fix issue abc"
cd tickets/gGS-145
```

## Choose the project management repo — or work without one

A ticket may belong to a project management repo. It holds the plans,
decisions and blog posts of a project, but no code. It is optional: ask the
user whether this ticket uses one. Write "project management repo" whenever
you write to the user, never "PM repo".

With a project management repo: look at the `index.jsonc` of each repo in
.ocean and find the one the ticket belongs to — its summary or domain talks
about project management or planning, not about code. If one fits, propose
it to the user. If none fits, ask the user which repo to use, or whether to
create a new one.

After the user's confirmation, add it to the ticket **before** any other
repo:

```bash
gg do add pm_repo
```

If it has `doc/guides/pm-repo-guide.md`, read it: it describes how the repo
is structured and how planning works there. If the file does not exist,
follow the guides that repo has.

Without a project management repo: skip this step and continue with the git
repositories. The ticket then carries no plan of its own.

## Add git repositories

Look at the `index.jsonc` of each repo in .ocean and decide which repos need to
be added to the ticket.
Make a plan for how you roughly want to implement the ticket.
If certain parts of the implementation belong to a domain that does not yet
exist in the .ocean folder, consider creating a new repository.
Ask the user about this. Also explain to the user what you roughly want to
change in which repo to implement the ticket and let them confirm that the
corresponding repos are added to the ticket.

If the ticket is only planned (see below), the project management repo may
be the only repo of the ticket.

After the user's confirmation, add the repos to the ticket:

```bash
gg do add repo1 repo2
```

## Open the workspace in Vscode

```bash
gg do code
```

## Plan (optional)

Ask the user whether the ticket is planned before it is implemented.

If yes, write the plan into the project management repo, following its
`doc/guides/pm-repo-guide.md` if present, otherwise its other guides: the
goal, the affected repos, the rough steps and open questions. Without a
project management repo, put the plan into the ticket itself. Let the user
review the plan and revise it until they confirm it.

## Implement (optional)

Ask the user whether the ticket is implemented now, or whether it is only
planned. Some tickets are only planned; the implementation follows in a later
ticket.

- Implement: implement your features based on the guides
- Plan only: skip this step. The following steps then apply to the project
  management repo only.

## Commit

```bash
gg do commit
```

`gg do commit` and `gg can commit` act on all repos of the ticket. When you
are inside a single repo instead of the ticket folder, use the standalone
form on that repo:

```bash
gg one can commit
gg one do commit
```

## Push

```bash
gg do push
```

## Review

Let the user confirm that the review phase is started.

```bash
gg do review
```

gg creates pull requests for each repo and prints the URLs to the
terminal.

Afterwards load the review-light skill and execute it.

## Publish

- Create a blog post for the current ticket
- Update the index.jsonc and README.md
- Create the configuration for gg do publish
- If the ticket was only planned, publish the project management repo only

Ask the user to run the following command **manually**:

```bash
gg do publish
```

gg triggers the pull request merge and publishes the changes to the
registry. Finally the version tag is created and pushed.
