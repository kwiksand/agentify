"""Kiro steering-doc adapter.

Kiro does not have a per-agent markdown file concept. Its primary
customization mechanism is *steering docs* at `.kiro/steering/*.md`,
which are injected into the assistant's context based on inclusion
rules. We project each canonical agent onto a steering doc with
`inclusion: manual` so the user can pull it in on demand ("act as
code-writer"), approximating sub-agent behavior.

Semantic mismatch to be aware of: steering docs are loaded context,
not a separate agent with its own tool allowlist. Tools defined in
the source file are ignored here — configure tools via
`.kiro/settings/mcp.json` instead.

Reference: https://kiro.dev/docs/steering/
"""
from pathlib import Path
import yaml

TARGET_DIR = ".kiro/steering"


def render(agent: dict) -> tuple[Path, str]:
    fm = {
        "inclusion": "manual",
        "description": agent["description"],
    }

    body = (
        "---\n"
        + yaml.safe_dump(fm, sort_keys=False, width=float("inf")).strip()
        + "\n---\n\n"
        + f"# {agent['name']}\n\n"
        + agent["body"].strip()
        + "\n"
    )
    path = Path(TARGET_DIR) / f"{agent['name']}.md"
    return path, body
