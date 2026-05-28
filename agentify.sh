#!/usr/bin/env bash
# agentify.sh — scaffold an existing/new project directory for AI tooling.
#
# Detects the project's language/framework, asks a few questions to fill
# in gaps, lays down AGENTS.md / README.md / agents/ / .claude/skills/,
# initialises git if needed, and (optionally) invokes sync/sync.py to
# fan canonical agent definitions out to Claude Code, Copilot, Kiro and
# Goose.
#
# Usage:
#   agentify.sh [--dir PATH] [--name NAME] [--no-sync] [--yes]
#               [--sync PATH_TO_SYNC_PY] [--targets LIST]
#               [--steer-honest] [--require-lint] [--require-test]
#
# --targets is a comma-separated subset of the sync.py adapter names
# (e.g. "claude-code,copilot,antigravity"). If omitted, you'll be prompted.
#
# Env:
#   AGENTIFY_HOME      Directory containing this script + templates/.
#                      Defaults to the script's own directory.
#   AGENTIFY_SYNC_PY   Path to sync/sync.py. Default:
#                      $AGENTIFY_HOME/sync/sync.py, falling back to
#                      ~/.local/share/agentify/sync/sync.py.

set -euo pipefail

# ---------- locate self & defaults ----------------------------------------
# Resolve symlinks so AGENTIFY_HOME points at the real install dir
# (e.g. when this script is symlinked into ~/.local/bin).
_resolve_self() {
  local src="${BASH_SOURCE[0]}" dir
  while [[ -L "$src" ]]; do
    dir="$(cd -P -- "$(dirname -- "$src")" && pwd)"
    src="$(readlink -- "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P -- "$(dirname -- "$src")" && pwd
}
SCRIPT_DIR="$(_resolve_self)"
AGENTIFY_HOME="${AGENTIFY_HOME:-$SCRIPT_DIR}"
TEMPLATES_DIR="$AGENTIFY_HOME/templates"
AGENTS_SOURCE_DIR="$AGENTIFY_HOME/agents"

DEFAULT_SYNC_PY="$AGENTIFY_HOME/sync/sync.py"
[[ -f "$DEFAULT_SYNC_PY" ]] || DEFAULT_SYNC_PY="$HOME/.local/share/agentify/sync/sync.py"
SYNC_PY="${AGENTIFY_SYNC_PY:-$DEFAULT_SYNC_PY}"

TARGET_DIR="$(pwd)"
PROJECT_NAME=""
RUN_SYNC=1
ASSUME_YES=0
SYNC_TARGETS=""
DEFAULT_SYNC_TARGETS="claude-code,copilot"
STEER_HONEST=""
REQUIRE_LINT=""
REQUIRE_TEST=""

# ---------- arg parsing ----------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)            TARGET_DIR="$(cd -- "$2" && pwd)"; shift 2 ;;
    --name)           PROJECT_NAME="$2"; shift 2 ;;
    --sync)           SYNC_PY="$2"; shift 2 ;;
    --targets)        SYNC_TARGETS="$2"; shift 2 ;;
    --no-sync)        RUN_SYNC=0; shift ;;
    --yes|-y)         ASSUME_YES=1; shift ;;
    --steer-honest)   STEER_HONEST="yes"; shift ;;
    --require-lint)   REQUIRE_LINT="yes"; shift ;;
    --require-test)   REQUIRE_TEST="yes"; shift ;;
    -h|--help)
      sed -n '2,24p' "$0"; exit 0 ;;
    *)
      echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

cd "$TARGET_DIR"
: "${PROJECT_NAME:=$(basename "$TARGET_DIR")}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

ask() {
  # ask "prompt" "default" -> echoes the answer
  local prompt="$1" default="${2-}" reply
  if (( ASSUME_YES )); then
    printf '%s\n' "$default"; return
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " reply || true
  else
    read -r -p "$prompt: " reply || true
  fi
  printf '%s\n' "${reply:-$default}"
}

# ---------- detection ------------------------------------------------------
detect_language() {
  [[ -f package.json ]]                  && { echo "JavaScript/TypeScript"; return; }
  [[ -f pyproject.toml || -f setup.py || -f requirements.txt ]] && { echo "Python"; return; }
  [[ -f go.mod ]]                        && { echo "Go"; return; }
  [[ -f Cargo.toml ]]                    && { echo "Rust"; return; }
  [[ -f pom.xml || -f build.gradle || -f build.gradle.kts ]] && { echo "Java/JVM"; return; }
  [[ -f Gemfile ]]                       && { echo "Ruby"; return; }
  [[ -f composer.json ]]                 && { echo "PHP"; return; }
  [[ -f mix.exs ]]                       && { echo "Elixir"; return; }
  echo "unknown"
}

detect_frameworks() {
  local out=()
  [[ -f package.json ]] && {
    grep -q '"next"'    package.json 2>/dev/null && out+=("Next.js")
    grep -q '"react"'   package.json 2>/dev/null && out+=("React")
    grep -q '"vue"'     package.json 2>/dev/null && out+=("Vue")
    grep -q '"express"' package.json 2>/dev/null && out+=("Express")
    grep -q '"vite"'    package.json 2>/dev/null && out+=("Vite")
  }
  [[ -f pyproject.toml ]] && {
    grep -q 'django'  pyproject.toml 2>/dev/null && out+=("Django")
    grep -q 'fastapi' pyproject.toml 2>/dev/null && out+=("FastAPI")
    grep -q 'flask'   pyproject.toml 2>/dev/null && out+=("Flask")
  }
  [[ -f Dockerfile || -f compose.yaml || -f docker-compose.yml ]] && out+=("Docker")
  (( ${#out[@]} )) && (IFS=", "; echo "${out[*]}") || echo "none detected"
}

detect_build() {
  [[ -f Makefile ]]                              && { echo "make"; return; }
  [[ -f package.json ]]                          && { echo "npm/yarn/pnpm scripts"; return; }
  [[ -f pyproject.toml ]]                        && { echo "pytest / hatch / poetry"; return; }
  [[ -f go.mod ]]                                && { echo "go test ./..."; return; }
  [[ -f Cargo.toml ]]                            && { echo "cargo test"; return; }
  [[ -f build.gradle || -f build.gradle.kts ]]   && { echo "gradle"; return; }
  [[ -f pom.xml ]]                               && { echo "maven"; return; }
  echo "unknown"
}

detect_linter() {
  [[ -f package.json ]] && {
    grep -q '"lint"' package.json 2>/dev/null && { echo "npm run lint"; return; }
  }
  [[ -f pyproject.toml || -f setup.py || -f requirements.txt ]] && {
    if grep -q "ruff" pyproject.toml 2>/dev/null; then
      echo "ruff check"
      return
    fi
    which ruff >/dev/null 2>&1 && { echo "ruff check"; return; }
    which flake8 >/dev/null 2>&1 && { echo "flake8"; return; }
    which pylint >/dev/null 2>&1 && { echo "pylint"; return; }
  }
  [[ -f go.mod ]]                        && { echo "golangci-lint run"; return; }
  [[ -f Cargo.toml ]]                    && { echo "cargo clippy"; return; }
  echo "none"
}

# ---------- gather ---------------------------------------------------------
say "Target directory: $TARGET_DIR"
[[ -d "$TEMPLATES_DIR" ]] || die "templates not found at $TEMPLATES_DIR (set AGENTIFY_HOME)"

DETECTED_LANG="$(detect_language)"
DETECTED_FW="$(detect_frameworks)"
DETECTED_BUILD="$(detect_build)"
DETECTED_LINT="$(detect_linter)"

say "Detected: lang=$DETECTED_LANG, frameworks=$DETECTED_FW, build=$DETECTED_BUILD, linter=$DETECTED_LINT"

PROJECT_NAME="$(ask 'Project name' "$PROJECT_NAME")"
PROJECT_DESCRIPTION="$(ask 'One-line description' "TODO: describe $PROJECT_NAME")"
PROJECT_LANGUAGE="$(ask 'Primary language' "$DETECTED_LANG")"
PROJECT_FRAMEWORKS="$(ask 'Frameworks / runtime' "$DETECTED_FW")"
PROJECT_BUILD="$(ask 'Build / test command' "$DETECTED_BUILD")"
PROJECT_LINT="$(ask 'Linter command' "$DETECTED_LINT")"
PROJECT_GETTING_STARTED="$(ask 'Getting-started one-liner' 'TODO: install deps, run tests, etc.')"

: "${STEER_HONEST:=$(ask 'Steer LLM to write honest, concise responses (yes/no)' 'yes')}"
: "${REQUIRE_LINT:=$(ask 'Require linting before completing coding tasks (yes/no)' 'yes')}"
: "${REQUIRE_TEST:=$(ask 'Require running tests after modifying code (yes/no)' 'yes')}"

# Which agent platforms to sync to. Known adapters in sync.py:
#   claude-code, copilot, gemini, kiro, goose, antigravity
if [[ -z "$SYNC_TARGETS" ]]; then
  SYNC_TARGETS="$(ask 'Sync targets (comma-separated: claude-code,copilot,gemini,kiro,goose,antigravity)' "$DEFAULT_SYNC_TARGETS")"
fi

# ---------- render helper --------------------------------------------------
render() {
  # render TEMPLATE_PATH OUTPUT_PATH KEY=VAL ...
  local tpl="$1" out="$2"; shift 2
  [[ -e "$out" ]] && { warn "exists, skipping: $out"; return; }
  local content; content="$(cat "$tpl")"
  local kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    # literal substitution; avoids sed escaping headaches
    content="${content//\{\{$k\}\}/$v}"
  done
  mkdir -p "$(dirname "$out")"
  printf '%s' "$content" > "$out"
  say "wrote $out"
}

# ---------- scaffold -------------------------------------------------------
STEER_HONEST_CONVENTIONS=""
if [[ "$STEER_HONEST" == "yes" || "$STEER_HONEST" == "true" || "$STEER_HONEST" == "1" ]]; then
  STEER_HONEST_CONVENTIONS=$'\n- Provide honest, concise responses. Avoid overly optimistic, overly positive, or unnecessarily verbose explanations.\n- State limitations, risks, and trade-offs clearly. If unsure, ask for clarification.'
fi

QUALITY_CONVENTIONS=""
if [[ "$REQUIRE_LINT" == "yes" || "$REQUIRE_LINT" == "true" || "$REQUIRE_LINT" == "1" ]] && [[ "$PROJECT_LINT" != "none" && -n "$PROJECT_LINT" ]]; then
  QUALITY_CONVENTIONS+=$'\n- Before completing any coding task, run the linter (`'"$PROJECT_LINT"'`) and fix all linting errors.'
fi
if [[ "$REQUIRE_TEST" == "yes" || "$REQUIRE_TEST" == "true" || "$REQUIRE_TEST" == "1" ]] && [[ "$PROJECT_BUILD" != "unknown" && -n "$PROJECT_BUILD" ]]; then
  QUALITY_CONVENTIONS+=$'\n- Run the test suite using (`'"$PROJECT_BUILD"'`) after any code changes to verify that all tests pass.'
fi

render "$TEMPLATES_DIR/AGENTS.md.tpl" "AGENTS.md" \
  "PROJECT_NAME=$PROJECT_NAME" \
  "PROJECT_DESCRIPTION=$PROJECT_DESCRIPTION" \
  "PROJECT_LANGUAGE=$PROJECT_LANGUAGE" \
  "PROJECT_FRAMEWORKS=$PROJECT_FRAMEWORKS" \
  "PROJECT_BUILD=$PROJECT_BUILD" \
  "STEER_HONEST_CONVENTIONS=$STEER_HONEST_CONVENTIONS" \
  "QUALITY_CONVENTIONS=$QUALITY_CONVENTIONS"

has_target() {
  # has_target NAME -> 0 if NAME is in the comma-separated SYNC_TARGETS
  local needle="$1"
  case ",$SYNC_TARGETS," in
    *",$needle,"*) return 0 ;;
    *)             return 1 ;;
  esac
}

if has_target "claude-code"; then
  render "$TEMPLATES_DIR/CLAUDE.md.tpl" "CLAUDE.md"
fi

if has_target "gemini"; then
  render "$TEMPLATES_DIR/GEMINI.md.tpl" "GEMINI.md"
fi

if has_target "antigravity"; then
  render "$TEMPLATES_DIR/ANTIGRAVITY.md.tpl" "ANTIGRAVITY.md"
fi

render "$TEMPLATES_DIR/README.md.tpl" "README.md" \
  "PROJECT_NAME=$PROJECT_NAME" \
  "PROJECT_DESCRIPTION=$PROJECT_DESCRIPTION" \
  "PROJECT_LANGUAGE=$PROJECT_LANGUAGE" \
  "PROJECT_FRAMEWORKS=$PROJECT_FRAMEWORKS" \
  "PROJECT_BUILD=$PROJECT_BUILD" \
  "PROJECT_GETTING_STARTED=$PROJECT_GETTING_STARTED"

# ---------- agents/ (canonical source) -------------------------------------
mkdir -p agents
if [[ -d "$AGENTS_SOURCE_DIR" ]]; then
  for f in "$AGENTS_SOURCE_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    if [[ -e "agents/$base" ]]; then
      warn "exists, skipping: agents/$base"
    else
      cp "$f" "agents/$base"
      say "seeded agents/$base"
    fi
  done
else
  warn "no canonical agents found at $AGENTS_SOURCE_DIR — agents/ left empty"
fi

# ---------- skills ---------------------------------------------------------
seed_skill() {
  local name="$1" desc="$2" body="$3"
  
  # Claude Code
  local dir=".claude/skills/$name"
  local out="$dir/SKILL.md"
  if [[ ! -e "$out" ]]; then
    mkdir -p "$dir"
    local content; content="$(cat "$TEMPLATES_DIR/SKILL.md.tpl")"
    content="${content//\{\{SKILL_NAME\}\}/$name}"
    content="${content//\{\{SKILL_DESCRIPTION\}\}/$desc}"
    content="${content//\{\{SKILL_BODY\}\}/$body}"
    printf '%s' "$content" > "$out"
    say "wrote $out"
  else
    warn "exists, skipping: $out"
  fi

  # Antigravity
  if has_target "antigravity"; then
    local adir=".agents/skills/$name"
    local aout="$adir/SKILL.md"
    if [[ ! -e "$aout" ]]; then
      mkdir -p "$adir"
      local content; content="$(cat "$TEMPLATES_DIR/SKILL.md.tpl")"
      content="${content//\{\{SKILL_NAME\}\}/$name}"
      content="${content//\{\{SKILL_DESCRIPTION\}\}/$desc}"
      content="${content//\{\{SKILL_BODY\}\}/$body}"
      printf '%s' "$content" > "$aout"
      say "wrote $aout"
    else
      warn "exists, skipping: $aout"
    fi
  fi
}

seed_skill "project-overview" \
  "High-level orientation for $PROJECT_NAME: stack, layout, build/test." \
  "Use this skill when a contributor needs a fast tour of the repo. Walk them through the layout described in README.md and AGENTS.md, then point at the build/test command: \`$PROJECT_BUILD\`."

seed_skill "run-tests" \
  "Run the project's tests and surface failures." \
  "Invoke \`$PROJECT_BUILD\` (or the equivalent for $PROJECT_LANGUAGE). Report failing test names and the first useful line of each failure."

if [[ "$PROJECT_LINT" != "none" && -n "$PROJECT_LINT" ]]; then
  seed_skill "lint" \
    "Run the project's linter and check for style/syntax violations." \
    "Invoke \`$PROJECT_LINT\`. Report any linting errors or warnings, including file names and line numbers."
fi

# ---------- git init -------------------------------------------------------
if [[ ! -d .git ]]; then
  say "initialising git repo"
  git init -q
  [[ -f .gitignore ]] || cat > .gitignore <<'EOF'
.DS_Store
__pycache__/
*.pyc
node_modules/
.venv/
dist/
build/
.antigravity
.antigravitycli
.gemini
EOF
else
  say "git repo already present — leaving git state alone"
fi

# ---------- run sync.py ----------------------------------------------------
if (( RUN_SYNC )); then
  if [[ -f "$SYNC_PY" ]]; then
    say "running sync: $SYNC_PY (targets: $SYNC_TARGETS)"
    python3 "$SYNC_PY" --out "$TARGET_DIR" --target "$SYNC_TARGETS"
  else
    warn "sync.py not found at $SYNC_PY"
    warn "set AGENTIFY_SYNC_PY or pass --sync PATH, then run:"
    warn "  python3 \$AGENTIFY_SYNC_PY --out \"$TARGET_DIR\" --target \"$SYNC_TARGETS\""
  fi
else
  say "skipping sync (--no-sync)"
fi

say "done. Next: review AGENTS.md, README.md, agents/, .claude/skills/, .agents/skills/."
