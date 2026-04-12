---
name: develop-feature
description: "Orchestrate feature development with specialized subagents. Use when starting work on any feature, bugfix, or refactoring task. Accepts a GitHub issue URL or task description."
user_invocable: true
args: task
---

# /develop-feature — Feature Development Workflow

Orchestrate the full development lifecycle for WhisperType using specialized subagents. You (Opus) are the orchestrator — you dispatch agents, review their output, and make decisions.

## Phase 1: Analyse

1. Read the issue URL (if provided) or parse the task description
2. Identify affected areas of the codebase:
   - **Swift backend:** AppState, services (Audio, Transcription, Input), models
   - **UI:** SwiftUI views, Settings, MenuBar, StatusOverlay
   - **Tests:** XCTest additions or modifications
   - **Localization:** New or changed user-visible strings
   - **Build/CI:** Makefile, project.yml, GitHub Actions
   - **whisper.cpp bridge:** BridgingHeader, WhisperEngine, CMake
3. Determine which agents to dispatch using this matrix:

| Change area | Agents to dispatch |
|---|---|
| Swift code (non-UI) | swift-engineer → test-engineer → code-reviewer + security-scanner |
| UI code (SwiftUI/AppKit) | ui-engineer → test-engineer + app-tester → code-reviewer + i18n-checker |
| Tests only | test-engineer → code-reviewer |
| Build/CI/CD | (you handle directly) → security-scanner |
| Localization only | i18n-checker → code-reviewer |
| whisper.cpp/Bridge | swift-engineer → test-engineer → code-reviewer + security-scanner |
| Mixed/unclear | All agents |

## Phase 2: Branch & Planning

1. Create a feature branch from `main`:
   ```bash
   git checkout -b <type>/<short-description>
   # Types: feat/, fix/, chore/, refactor/, docs/
   ```

2. Create an implementation plan (use EnterPlanMode if the task is non-trivial)

3. Present the plan to the user for confirmation before proceeding

## Phase 3: Implementation

Dispatch implementation agents based on Phase 1 analysis.

**For independent changes** (e.g., backend + UI that don't interact):
- Dispatch `swift-engineer` and `ui-engineer` in parallel via the Agent tool

**For dependent changes** (e.g., new model in backend, then UI for it):
- Dispatch sequentially: `swift-engineer` first, then `ui-engineer`

**Agent dispatch template:**
```
Use the Agent tool with subagent_type matching the agent name.
Provide the agent with:
1. The specific task to implement
2. Which files to modify
3. Any constraints or patterns to follow
4. Expected output
```

Review each agent's output before proceeding. If the output has issues, re-dispatch with feedback.

## Phase 4: Testing

1. **Unit tests** — Dispatch `test-engineer`:
   - For bugfixes: Write a regression test FIRST (TDD red), then verify implementation makes it green
   - For features: Write tests for the new behavior
   - Must run `make test` and all tests must pass

2. **App testing** (if UI was changed) — Dispatch `app-tester`:
   - Build and launch the app
   - Verify UI changes visually via screenshots
   - Check settings, menu bar, overlay behavior

3. Verify: `make test` passes before proceeding

## Phase 5: Verification (dispatch in parallel)

Dispatch all applicable verification agents **in a single message** (parallel):

- **Always dispatch:** `code-reviewer`, `security-scanner`
- **If strings changed:** Also dispatch `i18n-checker`

Each agent returns a verdict:
- `APPROVED` / `SECURE` → proceed
- `CHANGES_REQUESTED` / `CONCERNS_FOUND` / `ISSUES_FOUND` → fix and re-verify

**If any agent requests changes:**
1. Review the feedback
2. Re-dispatch the appropriate implementation agent with the fix instructions
3. Re-run verification agents that failed

## Phase 6: Commit & Completion

Once ALL verification agents approve:

1. **Stage changes:**
   ```bash
   git add <specific files>  # Never use git add -A
   ```

2. **Commit with conventional commit message:**
   ```bash
   git commit -m "$(cat <<'EOF'
   <type>(<scope>): <description>

   <body explaining what and why>

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
   Types: `feat`, `fix`, `refactor`, `test`, `chore`, `docs`
   Scopes: `audio`, `transcription`, `input`, `ui`, `settings`, `build`, `i18n`

3. **Report to user:**
   - Summary of what was implemented
   - Test results
   - Verification verdicts
   - Security findings (especially whisper.cpp update status)
   - Ask if they want to create a PR

## Rules

- **Never skip verification.** Even for "small" changes, at minimum dispatch code-reviewer + security-scanner.
- **Never auto-push.** Only commit locally. Pushing requires explicit user approval.
- **All git messages in English.** Branch names, commits, PR descriptions — always English.
- **Build must succeed.** Run `make build` before committing. If it fails, fix first.
- **Tests must pass.** Run `make test` before committing. If any test fails, fix first.
- **SwiftLint must pass.** The PostToolUse hook handles this automatically, but verify with `swiftlint lint` on changed files before committing.
