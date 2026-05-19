"""Claude Code adapter.

Writes agents to `.claude/agents/<name>.md` using Claude Code's native
YAML-frontmatter format. Source and target schemas are identical, so
this adapter is a near-passthrough.

Reference: https://docs.claude.com/en/docs/claude-code/sub-agents
"""
from pathlib import Path
import yaml

TARGET_DIR = ".claude/agents"

MODEL_MAP = {
    "opus": "opus",
    "sonnet": "sonnet",
    "haiku": "haiku",
    "inherit": "inherit",
}


def render(agent: dict) -> tuple[Path, str]:
    fm = {
        "name": agent["name"],
        "description": agent["description"],
    }
    if "model" in agent:
        fm["model"] = MODEL_MAP.get(agent["model"], agent["model"])
    if "tools" in agent:
        fm["tools"] = ", ".join(agent["tools"])

    body = (
        "---\n"
        + yaml.safe_dump(fm, sort_keys=False, width=float("inf")).strip()
        + "\n---\n\n"
        + agent["body"].strip()
        + "\n"
    )
    path = Path(TARGET_DIR) / f"{agent['name']}.md"
    return path, body
