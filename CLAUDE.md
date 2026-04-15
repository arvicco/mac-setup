# Mac Setup — Claude Code Instructions

## Work Protocol

### For ALL tasks:
1. **Read relevant code** before proposing or making changes — never rely on assumptions
2. **Propose your plan** and wait for explicit approval before implementing
3. **Never change behavior** beyond what was explicitly requested — no drive-by refactors, no "improvements"
4. **Run relevant tests before making changes** to establish a green baseline — you cannot distinguish regressions from pre-existing failures without one
5. **Run tests** after making changes (see Testing below)
6. **All tests must pass.** If a test fails, investigate — never dismiss it as "pre-existing"
7. **Work in small, testable increments.** Each step should leave the codebase in a passing state. Prefer multiple small commits over one large change

### When a bug or problem is reported:
1. **STOP. Do not touch the codebase.**
2. Think through potential root causes — list them explicitly
3. Run exploratory read-only commands (grep, logs, traces) to gather evidence
4. Present a diagnosis with your reasoning and a proposed fix plan
5. Wait for explicit approval before making any code changes
6. Write regression test before implementing any fix

**Never implement a fix speculatively.** "This might help" changes are not allowed.
If you are unsure about the root cause, say so and ask a clarifying question instead of guessing with code.

**Every bug fix must include a regression test** that fails without the fix and passes with it. No fix is complete without one.

## Testing

### Commands
- Framework: Minitest (`test/unit/`, `test/integration/`)
- Run single file: `ruby -Ilib:test test/unit/test_command_runner.rb`
- Run unit tests: `rake test:unit`
- Run all tests: `rake test`

### Test-Driven Development
- **Tests first for new behavior:** Write a failing test that specifies the desired behavior → make it pass with the simplest implementation → refactor. (Red → Green → Refactor)
- **Tests first for bug fixes:** Write a failing test that reproduces the bug → fix it → confirm the test passes
- **New production code must have corresponding tests.** Untested code should not be merged without explicit justification

### Test Tiers
- **Unit** (`test/unit/`): All new classes, modules, and non-trivial methods. No network, no filesystem side-effects. Must be fast and isolated
- **Integration** (`test/integration/`): Interactions between components (module orchestration, config loading)

### Conventions
- Test method naming: `test_<method_or_behavior>_<scenario>_<expected_outcome>` (e.g., `test_parse_with_empty_input_returns_default`)
- Structure within each test: Arrange → Act → Assert
- **A failing test is a bug signal.** Investigate every failure — determine root cause, whether related to your changes or a separate issue. If separate, flag it to the user
- Never treat failing tests as acceptable background noise

## Coding Standards
- Ruby 2.6 compatible — no gems, only stdlib
- Single responsibility per class/method
- `frozen_string_literal: true` in every Ruby file
- **Refactoring is a deliberate, separate step** — it happens after tests are green, changes no external behavior, and gets its own commit. Drive-by refactors during feature work are still not allowed

## Workflow Notes
- When user mentions screenshots or pics, check ~/Desktop for recent .png files sorted by date
- "Document" means update both CLAUDE.md and README.md
- "CRPR" means commit, review, push, release — the default release workflow (see below)
- "CPR" means commit, push, release — skips review, only when explicitly requested

### CRPR — Code Review Workflow
1. **Commit** changes as normal
2. **Review** — spawn a worktree agent (`isolation: "worktree"`) running the `/cr` skill. The reviewer operates in a separate session with no shared context from the coding session. It is report-only — it never modifies code
3. **Resolve** — the main session must address all BLOCKERs and WARNINGs flagged by the reviewer. After fixes, commit again and re-run review. **Repeat until the reviewer returns APPROVED or APPROVED WITH WARNINGS.** NITs are optional and do not block
4. **Push** to origin — CI runs unit tests automatically (`.github/workflows/ci.yml`)
5. **Verify CI** — check CI status via `gh run list` or the GitHub MCP plugin. Do not proceed to release until CI is green. If CI fails, diagnose, fix, commit, and re-push
6. **Release** — create GitHub release via `gh release create`

The review loop (steps 2–3) is mandatory unless the user explicitly says "CPR" or "skip review". Never skip it silently.

### CI/CD
- **CI** (`.github/workflows/ci.yml`): Runs syntax check + `rake test:unit` on every push to main and on PRs

## Project Overview
Self-contained Ruby CLI that automates setting up a new MacBook. Runs on macOS stock Ruby 2.6 with zero external gems. Modular design — each setup concern (Homebrew, macOS defaults, git, shell, SSH, Node) is a class inheriting `MacSetup::BaseModule`.

### Architecture
- `bin/setup` — entry point
- `lib/mac_setup/runner.rb` — CLI arg parsing + interactive module selection
- `lib/mac_setup/base_module.rb` — base class all modules inherit
- `lib/mac_setup/*.rb` — individual setup modules
- `lib/mac_setup/utils/` — shared utilities (logger, command runner)
- `config/` — declarative configuration (Brewfile, macOS defaults YAML)
- `install.sh` — bootstrap script for curl-pipe-bash on a fresh Mac
