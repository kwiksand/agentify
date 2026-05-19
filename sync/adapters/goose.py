"""Goose recipe adapter.

Writes agents to `.goose/recipes/<name>.yaml`. Goose recipes are full
YAML documents describing a named workflow with a system prompt and a
list of extensions.

Reference: https://goose-docs.ai/docs/guides/recipes/recipe-reference

Note: Goose does not auto-discover `.goose/recipes/` as a project-local
directory. Users must either run from that directory, add it to
`GOOSE_RECIPE_PATH`, or point Goose at a GitHub repo via
`GOOSE_RECIPE_GITHUB_REPO`.
"""
from pathlib import Path
import yaml


class _LiteralStr(str):
    pass


def _literal_representer(dumper, data):
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="|")


yaml.add_representer(_LiteralStr, _literal_representer)

TARGET_DIR = ".goose/recipes"

# Goose talks about "extensions" (MCP servers + built-ins) rather than
# per-agent tool allowlists. We translate the canonical tools to the
# closest Goose built-in extension names.
TOOL_TO_EXTENSION = {
    "Read": "developer",
    "Edit": "developer",
    "Write": "developer",
    "Bash": "developer",
    "Grep": "developer",
    "Glob": "developer",
    "WebFetch": "webscraper",
}


def render(agent: dict) -> tuple[Path, str]:
    extensions = sorted({TOOL_TO_EXTENSION[t] for t in agent.get("tools", []) if t in TOOL_TO_EXTENSION})

    recipe = {
        "version": "1.0.0",
        "title": agent["name"],
        "description": agent["description"],
        "instructions": _LiteralStr(agent["body"].strip() + "\n"),
    }
    if extensions:
        recipe["extensions"] = [{"type": "builtin", "name": e} for e in extensions]

    path = Path(TARGET_DIR) / f"{agent['name']}.yaml"
    return path, yaml.dump(
        recipe,
        sort_keys=False,
        allow_unicode=True,
        width=float("inf"),
        default_flow_style=False,
    )
