# Repository notes

- Run Android integration tests only on disposable devices. Use `integration_test/support/notebook_test_helpers.dart` to snapshot on-device files before writing fixtures and restore them in `finally`. Preserve reminder scheduling barriers around file restoration.
- The four downloadable TTFs are pinned font binaries and test fixtures even though they are not bundled in `pubspec.yaml`. Keep their license texts packaged.
- `android/app/src/main/res/raw/keep.xml` keeps the notification icon discoverable by resource name in shrunk release builds.

## Testing and delivery

- If the Flutter SDK is missing, install it before running `flutter test`. Don't skip tests because the SDK isn't preinstalled.
- After the tests pass, push the feature branch and enable auto-merge on its pull request into `main`. Don't bypass required checks or reviews.
- Exception for this project's direct work on `main`: commits made on `main` are pushed straight to `main` without a pull request, as the user requested. Feature branches still use pull requests.

## Development workflow

- The main agent handles high-level planning and discussion, and integration only. Workers own implementation, review, verification, and reporting.
- Use the [`fast-worker`](.agents/agents/fast-worker.md) profile for quick, simple, well-scoped jobs: small code changes, targeted tests, focused review, and other short tasks. It uses `deepseek-v4.1-flash` with high reasoning effort.
- Use the [`smart-worker`](.agents/agents/smart-worker.md) profile for detailed planning, architecture, difficult or cross-cutting changes, and other macro-level work. It uses `gpt-6.2-sol` with high reasoning effort. Use it when a task needs more detailed planning than the main agent's high-level plan.
- Start code changes from the current `main` in a dedicated Git worktree. Before removing a worktree, check for unmerged commits or unique changes.
- Independent verification runs after a task or milestone is committed and before the main agent integrates it. Assign a fresh worker, normally `fast-worker`, to check out the integrated branch in its own worktree, run the targeted tests, and report. The implementer does not perform this check.
- Break implementation into small, independently executable tasks with acceptance criteria in [`PLAN.md`](PLAN.md). Append worktree, delegation, test, and commit events to [`PROCESS.jsonl`](PROCESS.jsonl); do not rewrite earlier entries.
- Push every local `main` commit to GitHub immediately. This project intentionally pushes directly to `main`; do not open a pull request for these commits.
- Do not hold back a commit for known defects. Fix the defect in a follow-up commit, push it, and repeat. The 15-minute commit cadence keeps the exposure short.
- During active implementation, make at least one meaningful commit every 15 minutes, starting in the first 15 minutes. Assign commit checkpoints explicitly when delegating. Empty commits do not count.
- For each small development task, run targeted tests covering the affected behavior. Run the full suite at milestone integration or sooner if a change has wider impact.
