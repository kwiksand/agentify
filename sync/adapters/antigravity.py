"""Google Antigravity custom agents adapter.

Writes agents to `.agents/agents/<name>.md` using Antigravity's native
YAML-frontmatter format.
"""
from pathlib import Path
import yaml

TARGET_DIR = ".agents/agents"

# Map canonical short model names to Gemini models for Google Antigravity
MODEL_MAP = {
    "sonnet": "gemini-2.5-pro",
    "opus": "gemini-2.5-pro",
    "haiku": "gemini-2.5-flash",
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
        fm["tools"] = agent["tools"]

    body = (
        "---\n"
        + yaml.safe_dump(fm, sort_keys=False, width=float("inf")).strip()
        + "\n---\n\n"
        + agent["body"].strip()
        + "\n"
    )
    path = Path(TARGET_DIR) / f"{agent['name']}.md"
    return path, body
