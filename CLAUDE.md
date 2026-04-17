# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
Self-contained Ruby CLI that automates setting up a new MacBook. Runs on macOS stock Ruby 2.6 with zero external gems — only stdlib. Modular design where each setup concern is a class inheriting `MacSetup::BaseModule`.

### Architecture
- `bin/setup` → `MacSetup::Runner` parses CLI args, instantiates a shared `Logger` + `CommandRunner`, then iterates `Runner::MODULES` creating each module with those dependencies and calling `#run`
- `lib/mac_setup/base_module.rb` — base class; subclasses implement `#run`. `self.module_name` auto-derives a display name from the class name
- `lib/mac_setup/*.rb` — individual setup modules (Hostname, Homebrew, Node, ClaudeCode, Cask, MacosDefaults, TerminalApp, GitConfig, Shell, Ssh). Execution order is defined by `Runner::MODULES` in `lib/mac_setup/runner.rb` and mirrored in README.md.
- `lib/mac_setup/utils/file_editor.rb` — `ensure_line_in_file` / `ensure_block_in_file` helpers for idempotent shell-config edits
- `lib/mac_setup/utils/logger.rb` — colored terminal output (`info`, `success`, `warn`, `error`)
- `lib/mac_setup/utils/command_runner.rb` — wraps `Open3.capture3`; `run()` returns `[stdout, stderr, status]`, `success?()` returns bool
- `config/` — declarative configuration: `Brewfile` (Homebrew bundle), `macos_defaults.yml` (YAML array of `{domain, key, type, value}`)
- `install-gui.sh` — GUI-mode bootstrap for fresh Macs (runs on target): installs Xcode CLT, clones repo, runs `ruby bin/setup`
- `install-ssh-controller.sh` — SSH-mode bootstrap (runs on a controller Mac): installs pubkey/NOPASSWD sudo/CLT on target, rsyncs repo, runs `ruby bin/setup --all` over SSH
- `install-ssh-target.sh` — SSH-mode finishing touches (runs on target after login): default browser, SSH keychain, Finder/Dock restart
- `MacSetup::ROOT` (defined in `lib/mac_setup.rb`) — absolute path to repo root, used by modules to resolve config files

## Testing

### Commands
- Framework: Minitest (`test/unit/`, `test/integration/`)
- Run single file: `ruby -Ilib:test test/unit/test_command_runner.rb`
- Run unit tests: `rake test:unit`
- Run all tests: `rake test`

### What to test
- **Utilities and config parsing** (CommandRunner, Logger, YAML loading) — always test, this is where real bugs hide
- **Module registration and orchestration** (Runner, BaseModule interface) — always test
- **Setup modules** (Homebrew, Shell, etc.) — thin wrappers around shell commands. Test only non-trivial logic (e.g., conditional install paths, idempotency checks). Do not mock shell commands just for coverage

### Conventions
- Test method naming: `test_<method_or_behavior>_<scenario>_<expected_outcome>`
- Structure within each test: Arrange → Act → Assert
- A failing test is a bug signal — investigate every failure

## Coding Standards
- Ruby 2.6 compatible — no gems, only stdlib
- Single responsibility per class/method
- `frozen_string_literal: true` in every Ruby file
- **Idempotency is mandatory.** Every module must be safe to re-run. Always check state before acting (file exists? tool installed? key present?). Never assume a clean slate.
- **Config-driven over code-driven.** When possible, new setup steps should be data in `config/` (Brewfile entries, YAML defaults) rather than new Ruby code. Keep the common case trivial.
- **Homebrew is the preferred package manager.** If a tool is available via `brew` or `brew --cask`, install it through the Brewfile rather than npm, pip, curl-to-bash, or other managers. This keeps installs declarative, updatable via `brew upgrade`, and avoids runtime dependencies (e.g., Claude Code is a cask, not an npm global).
- **Refactoring is a deliberate, separate step** — it happens after tests are green, changes no external behavior, and gets its own commit

### Adding a new module
1. Create `lib/mac_setup/your_module.rb` — class inheriting `BaseModule`, implement `#run`
2. Add `require_relative` in `lib/mac_setup.rb`
3. Add the class to `Runner::MODULES` in the desired execution position
4. Update the sequential step list in `README.md`
5. Add tests for any non-trivial logic in `test/unit/`

## Work Protocol

### For ALL tasks:
1. **Read relevant code** before proposing or making changes — never rely on assumptions
2. **Never change behavior** beyond what was explicitly requested — no drive-by refactors, no "improvements"
3. **Run relevant tests before making changes** to establish a green baseline
4. **Run tests** after making changes
5. **All tests must pass.** If a test fails, investigate — never dismiss it as "pre-existing"
6. **Work in small, testable increments.** Each step should leave the codebase in a passing state

### When to propose a plan first:
- New modules or architectural changes — propose and wait for approval
- Straightforward changes (add a package, tweak a default, fix a path) — just do it

### When a bug or problem is reported:
1. Think through potential root causes — list them explicitly
2. Run exploratory read-only commands (grep, logs, traces) to gather evidence
3. Present a diagnosis with reasoning and a proposed fix
4. Write a regression test **when the bug is in logic** (config parsing, module selection, utility code). Skip tests for trivial fixes (typo in a package name, changed URL)

**Never implement a fix speculatively.** "This might help" changes are not allowed.
If you are unsure about the root cause, say so and ask a clarifying question instead of guessing with code.

## Documentation
- **README.md must always reflect the current state of the code.** When a feature is implemented, changed, or removed, update README.md in the same commit.
- README.md must list all setup steps the script executes, **in sequential order** (first, then next, then next, etc.) — matching the actual execution order in `Runner::MODULES`.
- When a new module is added or the module order changes, update the sequential step list in README.md immediately.

## Workflow Notes
- "Document" means update both CLAUDE.md and README.md
- "CRPR" means commit, review, push, release — the default workflow (see below)
- "CPR" means commit, push, release — skips review, only when explicitly requested

### CRPR — Code Review Workflow
1. **Commit** changes as normal
2. **Review** — spawn a worktree agent (`isolation: "worktree"`) running the `/cr` skill. The reviewer operates in a separate session with no shared context from the coding session. It is report-only — it never modifies code
3. **Resolve** — address all BLOCKERs and WARNINGs flagged by the reviewer. After fixes, commit again and re-run review. **Repeat until the reviewer returns APPROVED or APPROVED WITH WARNINGS.** NITs are optional and do not block
4. **Push** to origin — CI runs unit tests automatically (`.github/workflows/ci.yml`)
5. **Verify CI** — check CI status via `gh run list`. If CI fails, diagnose, fix, commit, and re-push
6. **Release** — create GitHub release via `gh release create`

The review loop (steps 2–3) is mandatory unless the user explicitly says "CPR" or "skip review". Never skip it silently.

### CI/CD
- **CI** (`.github/workflows/ci.yml`): Runs syntax check + `rake test:unit` on every push to main and on PRs

### End-to-end validation
The real integration test is running on a clean macOS environment (fresh VM or new user account). Unit tests validate logic; only a live run validates that the setup actually works.
