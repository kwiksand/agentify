#!/usr/bin/env python3
"""Sync canonical agent definitions to each supported platform.

Reads `agents/*.md` next to this script's parent directory, parses the
YAML frontmatter + markdown body, and writes platform-native files
into the current working directory.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent))
from adapters import ADAPTERS  # noqa: E402

SOURCE_DIR = Path(__file__).parent.parent / "agents"


def parse_agent(path: Path) -> dict:
    text = path.read_text()
    if not text.startswith("---\n"):
        raise ValueError(f"{path}: missing YAML frontmatter")
    _, fm_text, body = text.split("---\n", 2)
    fm = yaml.safe_load(fm_text) or {}
    if "name" not in fm or "description" not in fm:
        raise ValueError(f"{path}: frontmatter must include name and description")
    fm["body"] = body
    return fm


def load_agents(name_filter: str | None = None) -> list[dict]:
    agents = []
    for path in sorted(SOURCE_DIR.glob("*.md")):
        agent = parse_agent(path)
        if name_filter and agent["name"] != name_filter:
            continue
        agents.append(agent)
    return agents


def write(path: Path, content: str, *, dry_run: bool) -> None:
    if dry_run:
        print(f"  [dry-run] would write {path} ({len(content)} bytes)")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    print(f"  wrote {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--target",
        help=f"Comma-separated subset of {sorted(ADAPTERS)}. Default: all.",
    )
    parser.add_argument("--agent", help="Sync a single agent by name.")
    parser.add_argument("--dry-run", action="store_true", help="Show actions without writing.")
    parser.add_argument("--out", default=".", help="Destination root (default: cwd).")
    args = parser.parse_args()

    targets = args.target.split(",") if args.target else list(ADAPTERS)
    unknown = [t for t in targets if t not in ADAPTERS]
    if unknown:
        parser.error(f"unknown targets: {unknown}. Known: {sorted(ADAPTERS)}")

    agents = load_agents(args.agent)
    if not agents:
        parser.error("no agents matched")

    out_root = Path(args.out).resolve()
    print(f"Source: {SOURCE_DIR}")
    print(f"Destination root: {out_root}")

    for target in targets:
        adapter = ADAPTERS[target]
        print(f"\n[{target}]")
        for agent in agents:
            rel_path, content = adapter.render(agent)
            write(out_root / rel_path, content, dry_run=args.dry_run)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
