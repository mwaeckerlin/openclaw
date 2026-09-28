---
name: opencode-delegation
description: Use this skill for every software development task — writing, changing, fixing, reviewing or testing code in a repository. Delegate the task to the central OpenCode server instead of editing code yourself.
---

# Delegate Development to OpenCode

Software development is done by OpenCode, the development agent of this cluster, which is tuned for it. You hand the task over, wait for the result, and report it. You do not write or change code in your own sandbox.

## When

Delegate whenever the task is to write, change, fix, refactor, review or test code, or to build, extend or repair a software project. Answer questions about code, plan or discuss yourself; delegate as soon as a repository has to change.

## Check

In the sandbox shell:

```bash
echo "OPENCLAW_OPENCODE_URL=${OPENCLAW_OPENCODE_URL}"
```

Empty: no OpenCode server is configured. Tell the user that development delegation is not set up, and do the task only if the user asks you to do it yourself.

## Delegate

```bash
opencode-delegate "<the complete task>"
```

- The task text is all OpenCode knows: name the repository (clone URL), the branch, the goal, the acceptance criteria, and what to deliver (commit, pull request, report). OpenCode works in its own workspace; your sandbox files are not visible there.
- `--dir <path>` selects a directory on the OpenCode server when the repository is already checked out there.
- The command waits until OpenCode is done, prints its answer and, on the last line, the OpenCode session id. Relay the result to the user: what was done, where it is (branch, commit, pull request), and what is open.
- To continue the same work, pass that id: `opencode-delegate --session <id> "<follow-up>"`.
- An HTTP 401 means the OpenCode server requires a password. The password never comes into your sandbox; tell the user that the operator puts a proxy in front of OpenCode.

## Credentials

You never pass a token or a password to OpenCode and never ask the user for one. If OpenCode reports that it needs a credential, tell the user that the operator configures it for OpenCode.
