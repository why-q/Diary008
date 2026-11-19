# Agent profile delivery plan

## Goal

Create four reusable project-level OpenHands sub-agent profiles for implementation work, using the requested model assignments, and remove the obsolete architecture-specific profile names if they exist.

## Constraints

- Work only in the dedicated Git worktree `/workspace/project/Diary008-agent-profiles` on branch `chore/agent-profiles`.
- Do not use sub-agents for planning or discussion.
- Use `gpt-6.2-sol` for `planner`.
- Use `deepseek-v4.1-flash` for `fast-worker`, `tester`, and `reviewer`.
- Include high-reasoning operating guidance without inventing unsupported frontmatter fields.
- Store profiles in `.agents/agents/`.
- Keep `PROCESS.jsonl` append-only.
- Create a meaningful commit within the first 15 minutes of implementation work.

## Tasks

1. Initialize the dedicated worktree, agent directory, plan, and process log.
2. Create `planner.md` with planning-only behavior, detailed task decomposition, dependencies, acceptance criteria, and test checkpoints.
3. Create `fast-worker.md` with focused implementation behavior, worktree discipline, scope control, and early focused testing.
4. Create `tester.md` with test-first reproduction, focused and regression testing, and clear failure reporting.
5. Create `reviewer.md` with diff review for correctness, security, compatibility, maintainability, and acceptance criteria.
6. Search for and remove obsolete `sync-engine-builder.md`, `mcp-interface-builder.md`, and `sync-qa-engineer.md` files if present.
7. Validate YAML frontmatter, exact names, model assignments, required examples, tool declarations, and profile paths.
8. Append completion and validation events to `PROCESS.jsonl` without rewriting prior records.
9. Commit the profile changes on `chore/agent-profiles`.

## Acceptance criteria

- Exactly the requested generic profiles are present under `.agents/agents/`.
- Each profile filename matches its `name` field.
- Each description contains at least two concrete `<example>` tags.
- `planner` uses `gpt-6.2-sol`; the other three use `deepseek-v4.1-flash`.
- Every profile has only the tools it needs.
- Obsolete architecture-specific profile files are absent.
- Profile files are valid Markdown with valid YAML frontmatter.
- The process log is append-only and records the work.
- A meaningful Git commit contains the changes.
