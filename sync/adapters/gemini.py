"""Gemini CLI custom-command adapter.

Gemini CLI has no first-class "sub-agent" concept. The closest analog is
a custom slash command in `.gemini/commands/<name>.toml`, whose `prompt`
field is loaded as the system/user prompt when the command is invoked.

Reference: https://github.com/google-gemini/gemini-cli (custom commands).
"""
from pathlib import Path

TARGET_DIR = ".gemini/commands"


def _toml_escape_triple(s: str) -> str:
    return s.replace('"""', '\\"\\"\\"')


def render(agent: dict) -> tuple[Path, str]:
    description = agent["description"].replace('"', '\\"')
    prompt = _toml_escape_triple(agent["body"].strip())

    content = (
        f'description = "{description}"\n'
        f'prompt = """\n{prompt}\n"""\n'
    )
    path = Path(TARGET_DIR) / f"{agent['name']}.toml"
    return path, content
