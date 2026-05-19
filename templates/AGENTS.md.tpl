# {{PROJECT_NAME}} — Agent Instructions

This file is auto-loaded by Claude Code, Cursor, Aider, and other tools
that follow the AGENTS.md convention.

## Project summary

{{PROJECT_DESCRIPTION}}

- **Primary language:** {{PROJECT_LANGUAGE}}
- **Frameworks / runtime:** {{PROJECT_FRAMEWORKS}}
- **Build / test:** {{PROJECT_BUILD}}

## Conventions

- Prefer editing existing files over creating new ones.
- Don't add speculative abstractions or backwards-compat shims.
- For exploratory questions, recommend before implementing.

## Available sub-agents

Source-of-truth definitions live under `agents/`. Each is synced into
this project's platform-specific agent directories by `sync/sync.py`
(Claude Code, Copilot, Kiro, Goose).

## Skills

Reusable capability bundles live under `.claude/skills/`. See
`.claude/skills/<name>/SKILL.md` for what each one does.
