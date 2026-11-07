# Contributing

Keep changes focused, practical, and easy to verify. Search existing issues and
PRs before starting; explain the problem and resulting behavior in the PR.

## Setup and scope

Use the [README](README.md#build) for Xcode requirements and build setup, and
[AGENTS.md](AGENTS.md) for agent guidance. Keep credentials and signing overrides
in ignored local configuration. A clean checkout can build without an Apple
account.

Inspect `git status --short --branch` before editing. Preserve unrelated work.
Ordinary PRs start from the latest `origin/main` and target `main`; stacked PRs
must identify their parent and merge order. Use descriptive branches such as
`fix/<slug>`, `feat/<slug>`, or `docs/<slug>`.

Solve one underlying problem per PR, including the code, tests, and docs needed
for it. Put independent fixes and optional cleanup in separate PRs. Prefer the
smallest solution that fits the existing SwiftUI and shared core architecture.
Update existing docs when their instructions change.

## Verification and evidence

Run checks that match the change and record their actual results:

```sh
git diff --check
swift test
./scripts/build.sh macos --ad-hoc
./scripts/build.sh ios
```

Docs-only changes usually need only `git diff --check` and a review of links and
commands. For script changes, check shell syntax and exercise the affected path.
CI runs core tests and an unsigned iOS Release build; it does not replace manual
verification of changed UI.

Logic, data, and state fixes should have a focused regression test that fails
before the fix when practical. Use synthetic fixtures and extend existing tests
where a case fits. Purely visual fixes need before/after captures rather than
tests for spacing, color, or static markup.

UI changes require clear before/after screenshots **in the PR**, including
drafts. Capture the original behavior before editing and match surface,
content, state, appearance, dimensions, and orientation in the after capture.
Include a short recording when interaction, motion, or timing matters. Rehearse
first; keep recordings short and free of tool pauses. Review captures before
uploading. Prefer demo content and remove private information.

Describe reproduction steps, device/OS, commands, observed results, and anything
you could not verify. Check the affected native platforms and form factors.
Simulator builds alone do not verify runtime behavior; Simulator playback does
not prove physical-device behavior. For nonvisual or docs-only changes, explain
why screenshots do not apply. If a required capture is unavailable, state that
explicitly and treat it as a review gap; draft status does not waive evidence.

Keep PR-only images and recordings outside the repository and code branch.
Local paths and screenshots retained only on the author's machine are not
reviewable evidence.

## Upload PR evidence

Current GitHub CLI supports image and video attachments directly. Check your
installed CLI before using it:

```sh
gh pr create --help
gh pr edit --help
```

Look for `--attach`. If it is missing, upgrade `gh` or attach files through the
GitHub web editor. A separate image host is not required. See the official
[create](https://cli.github.com/manual/gh_pr_create) and
[edit](https://cli.github.com/manual/gh_pr_edit) documentation.

Keep the PR body and captures in a temporary directory outside the checkout.
For example, put `pr-body.md`, `before.png`, and `after.png` together and include
these references in the body:

```markdown
## Evidence

| Before | After |
| --- | --- |
| ![Before: describe the defect](./before.png) | ![After: describe the result](./after.png) |
```

Upload while creating the PR (replace the example paths and branch):

```sh
gh pr create --base main --head fix/example \
  --title 'fix(scope): describe the result' \
  --body-file /path/outside/checkout/pr-body.md \
  --attach /path/outside/checkout/before.png \
  --attach /path/outside/checkout/after.png
```

`gh` rewrites the attached local image references to hosted URLs. Paths in a
body file resolve relative to that file's directory, falling back to the working
directory. Add a recording with another `--attach /path/to/interaction.mp4`.

For an existing PR, append attachments without replacing its current body:

```sh
gh pr edit 123 \
  --attach '/path/outside/checkout/before.png#Before: describe the defect' \
  --attach '/path/outside/checkout/after.png#After: describe the result'
```

If editing body prose too, fetch the latest body first and preserve bot-managed
blocks and existing hosted URLs. Do not replace it with a stale local copy.
Attachments can partially succeed even when `gh` exits nonzero: inspect the
returned PR before retrying, and retry only missing files. Read back the body
with `gh pr view 123 --json body` and verify that every expected hosted image or
video is present. Check rendering in GitHub before declaring evidence complete.
Do not create evidence branches, releases, or public repositories as an upload
workaround.

## Commit and open the PR

Review the complete diff and staged scope. Check `git config user.name` and
`git config user.email`; use your established contributor identity. Use a
conventional, imperative commit subject and PR title, such as
`fix(player): respect the iPhone safe area`. Keep AI authorship, coauthor, and
generated footers out of commits.

Use the [PR template](.github/pull_request_template.md). Explain what changed,
why, exact verification, evidence, and known gaps. Disclose agent use at the end
of the human-authored body:

```text
Model: <full model name, version, and variant> | Harness: <agent and app or CLI>
```

Use the actual runtime values, for example `GPT-6.1 Sol` and `Codex in T3 Code`;
list all contributing models and harnesses if several were used. Human-only
contributions can omit this line. Keep disclosure separate from git authorship.

Push the focused branch and open against the verified base. Honor requests to
keep changes local. Address concrete review findings and check CI on the latest
head. PR creation does not authorize merging.
