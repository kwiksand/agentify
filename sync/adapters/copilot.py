"""GitHub Copilot custom agents adapter.

Writes agents to `.github/agents/<name>.agent.md`. This is Copilot's
current ("custom agents") format, which replaced the earlier
"chat modes" feature. The markdown body is the system prompt.

Reference: https://code.visualstudio.com/docs/copilot/chat/chat-modes
(redirects to the current custom-agents documentation).
"""
from pathlib import Path
import yaml

TARGET_DIR = ".github/agents"

# Map canonical tool names -> Copilot tool identifiers. Copilot's
# vocabulary is feature-oriented (search/codebase, edit, web/fetch)
# rather than primitive tool names. Unknown entries are dropped.
TOOL_MAP = {
    "Read": "search/codebase",
    "Edit": "edit",
    "Write": "edit",
    "Grep": "search",
    "Glob": "search",
    "WebFetch": "web/fetch",
    # Bash / shell execution has no stable first-party identifier in
    # the current schema. Leave it out; callers who need shell can add
    # an MCP server glob (e.g. "shell/*") themselves.
}

# Map canonical short model names -> Copilot's "Name (vendor)" format.
MODEL_MAP = {
    "sonnet": "Claude Sonnet 4.5 (copilot)",
    "opus": "Claude Opus 4.5 (copilot)",
    "haiku": "Claude Haiku 4.5 (copilot)",
}


def render(agent: dict) -> tuple[Path, str]:
    fm = {"description": agent["description"]}
    if "tools" in agent:
        mapped = sorted({TOOL_MAP[t] for t in agent["tools"] if t in TOOL_MAP})
        if mapped:
            fm["tools"] = mapped
    if "model" in agent:
        fm["model"] = MODEL_MAP.get(agent["model"], agent["model"])

    body = (
        "---\n"
        + yaml.safe_dump(fm, sort_keys=False, width=float("inf")).strip()
        + "\n---\n\n"
        + agent["body"].strip()
        + "\n"
    )
    path = Path(TARGET_DIR) / f"{agent['name']}.agent.md"
    return path, body
