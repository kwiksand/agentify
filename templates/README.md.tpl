# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Stack

- **Language:** {{PROJECT_LANGUAGE}}
- **Frameworks / runtime:** {{PROJECT_FRAMEWORKS}}
- **Build / test:** {{PROJECT_BUILD}}

## Layout

```
agents/                       # canonical sub-agent definitions (synced to platforms)
.claude/skills/               # Claude Code skills (capability bundles)
AGENTS.md                     # top-level instructions (read by many AI tools)
```

After running `agentify.sh` and `sync/sync.py`, platform-specific
directories are populated:

```
.claude/agents/               # Claude Code
.github/agents/               # GitHub Copilot
.kiro/steering/               # Kiro
.goose/recipes/               # Goose
```

## Getting started

{{PROJECT_GETTING_STARTED}}

## Re-syncing agents

When you edit anything under `agents/` or add a new agent file, push
the change to every platform with:

```bash
python3 "$AGENTIFY_SYNC_PY" --dry-run    # preview
python3 "$AGENTIFY_SYNC_PY"               # write
```
