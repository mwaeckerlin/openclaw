---
name: opencode-delegation
description: Use this skill for every software development task — writing, changing, fixing, reviewing or testing code in a repository. Hand the task to OpenCode, in your own sandbox or on the central OpenCode server, instead of editing code yourself.
---

# Development with OpenCode

Software development is done by OpenCode, the coding agent, which is tuned for it. You hand the task over, wait for the result, and report it. OpenCode runs in two places, and the choice below decides which one takes a task.

## When

Hand a task to OpenCode whenever it is to write, change, fix, refactor, review or test code, or to build, extend or repair a software project. Answer questions about code, plan or discuss yourself; hand it over as soon as a repository has to change.

## Check

In the sandbox shell:

```bash
echo "OPENCODE_GATEWAY_URL=${OPENCODE_GATEWAY_URL}"
echo "OPENCLAW_OPENCODE_URL=${OPENCLAW_OPENCODE_URL}"
```

`OPENCODE_GATEWAY_URL` set: OpenCode runs here, in your sandbox. `OPENCLAW_OPENCODE_URL` set: the central OpenCode server takes tasks. Both empty: tell the user that development with OpenCode is not set up, and do the task only if the user asks you to do it yourself.

## Which one

- **In your sandbox** (the default, whenever `OPENCODE_GATEWAY_URL` is set): the task works on a checkout in your sandbox, with your tools and your Docker, and the result stays in your workspace.
- **On the central server** (when the user wants to follow or take over the work in the browser, or when `OPENCODE_GATEWAY_URL` is empty): the task runs in the workspace of the server, which the user sees in its web interface; your sandbox files are not visible there.

## In your sandbox

```bash
cd <checkout> && opencode run "<the complete task>"
```

- Clone the repository first where it is not checked out yet; OpenCode works in the current directory.
- The command waits until OpenCode is done and prints its answer. Relay the result to the user: what was done, where it is (branch, commit, pull request), and what is open.
- To continue the same work, add `--continue` to the next `opencode run` in the same checkout.

## On the central server

```bash
opencode-delegate "<the complete task>"
```

- The task text is all OpenCode knows: name the repository (clone URL), the branch, the goal, the acceptance criteria, and what to deliver (commit, pull request, report).
- `--dir <path>` selects a directory on the OpenCode server when the repository is already checked out there.
- The command waits until OpenCode is done, prints its answer and, on the last line, the OpenCode session id. Relay the result as above.
- To continue the same work, pass that id: `opencode-delegate --session <id> "<follow-up>"`.
- An HTTP 401 means the OpenCode server requires a password. The password never comes into your sandbox; tell the user that the operator puts a proxy in front of OpenCode.

## Credentials

You never pass a token, a key or a password to OpenCode and never ask the user for one: in your sandbox, its gateway adds the keys. If OpenCode reports that it needs a credential, tell the user that the operator configures it.
