#!/usr/bin/env bash
# =============================================================================
# adapters/codex-cli/adapter.sh - OpenAI Codex CLI platform adapter
# =============================================================================
# Codex CLI ships native Agent Skills (since Dec 2025): a skill is a directory
# under `.agents/skills/<name>/` with a `SKILL.md` (name + description
# frontmatter + instructions). Codex loads only each skill's name/description
# until it selects one (progressive disclosure), then runs it IN-SESSION - the
# agent invokes it with `$<name>`, `/skills`, or implicitly by description.
#
# We therefore emit one native skill per command. AGENTS.md stays as a thin
# always-on operating manual (AI-first rule + how skills work); it no longer
# carries a giant routing table, because Codex discovers skills itself.
#
# This replaces the previous AGENTS.md-routing-table + `codex exec` wrapper
# design, which had no session continuity, no native skill discovery, ambiguous
# write permissions, and per-command startup overhead.
# =============================================================================

CODEX_PLATFORM="codex-cli"
CODEX_DIR="codex"
CODEX_SKILLS_DIR=".agents/skills"
CODEX_DISPATCHER="AGENTS.md"

adapter_build() {
  local src="$1" dst="$2"

  _codex_emit_dispatcher "$src" "$dst"
  _codex_emit_skills "$src/commands" "$dst/$CODEX_SKILLS_DIR"
  _codex_copy_references "$src/references" "$dst/.${CODEX_DIR}/references"
  _codex_copy_scripts "$src/scripts" "$dst/.${CODEX_DIR}/scripts"
  _codex_emit_pointer_files "$dst"
  _codex_emit_install_hint "$dst"
}

# AGENTS.md is the single populated operating manual. Every other agent
# instruction file is a THIN POINTER (plain text, never a symlink) so the same
# vault runs Claude, Gemini, and Copilot simultaneously from one manual.
_codex_emit_pointer_files() {
  local dst="$1"

  cat > "$dst/CLAUDE.md" <<'EOF'
@AGENTS.md

# Claude Code

All project instructions live in **AGENTS.md** at the repository root, imported above and treated as the single source of truth. Read it and follow every rule there, including the memory protocol.

Do not duplicate or restate instructions in this file. If a rule needs to change, change it in `AGENTS.md`.
EOF

  cat > "$dst/GEMINI.md" <<'EOF'
# Gemini CLI

The single source of truth for this project is **AGENTS.md** at the repository root.

Read `AGENTS.md` and follow all instructions there, including the memory protocol: read the `memory/` directory at the start of work and keep it updated as the project progresses.

This file is a pointer only. It intentionally contains no rules of its own — `AGENTS.md` governs. If a rule needs to change, change it in `AGENTS.md`.
EOF

  mkdir -p "$dst/.github"
  cat > "$dst/.github/copilot-instructions.md" <<'EOF'
# GitHub Copilot

The single source of truth for this project is **AGENTS.md** at the repository root.

Read `AGENTS.md` and follow all instructions there, including the memory protocol: read the `memory/` directory at the start of work and keep it updated as the project progresses.

This file is a pointer only. It intentionally contains no rules of its own; `AGENTS.md` governs. If a rule needs to change, change it in `AGENTS.md`.
EOF
}

# Emit AGENTS.md at the dist root. Thin always-on manual - no routing table,
# because Codex's native skill discovery (progressive disclosure) handles
# routing. We just tell the agent the skills exist and the AI-first rule.
_codex_emit_dispatcher() {
  local src="$1" dst="$2"
  local out="$dst/$CODEX_DISPATCHER"
  local count=0 f
  for f in "$src"/commands/*.md; do
    [[ -f "$f" ]] || continue
    should_include "$f" "$CODEX_PLATFORM" && count=$((count + 1))
  done

  {
    cat <<EOF
# Obsidian Second Brain - Codex CLI Operating Manual

This vault runs the **obsidian-second-brain** skill as ${count} native Codex
**Agent Skills** under \`.agents/skills/\`. Codex discovers them automatically:
each skill's name and description are always visible, and the full instructions
load only when a skill is selected (progressive disclosure).

## How to operate

1. Read \`_CLAUDE.md\` in the vault root, if it exists, to learn the user's
   vault conventions (folder map, daily note format, naming).
2. When the user's request matches a skill, invoke it - by \`\$<skill-name>\`,
   via \`/skills\`, or let Codex select it implicitly from its description.
   You do not need a routing table here; the skill list is the router.
3. Treat the AI-first vault rule (\`.codex/references/ai-first-rules.md\`) as
   non-negotiable for every note you write: \`## For future Claude\` preamble,
   rich frontmatter (\`type\`, \`date\`, \`tags\`, \`ai-first: true\`),
   \`[[wikilinks]]\` for every person/project/concept, recency markers per
   external claim, sources verbatim, confidence levels where applicable.
4. Do not invent skills. If none matches, ask the user or fall back to plain
   natural-language help.

## Scripts

Python helpers live under \`.codex/scripts/\`. They run via
\`uv run -m scripts.research.<name>\` from the vault root. Skills that need them
reference the exact invocation inside the skill body.

---

*Generated by adapters/codex-cli/adapter.sh - do not edit manually.*
EOF
  } > "$out"
}

# Emit one native Codex skill per command:
#   .agents/skills/<name>/SKILL.md
# Frontmatter carries `name` + `description` (required by Codex). We fold the
# command's English triggers into the description so Codex's implicit selection
# matches them. The body is the command body, tool-neutralized and
# path-rewritten so references/scripts resolve under .codex/.
_codex_emit_skills() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  local f name desc triggers out
  for f in "$src"/*.md; do
    [[ -f "$f" ]] || continue
    should_include "$f" "$CODEX_PLATFORM" || continue

    name="$(basename "$f" .md)"
    desc="$(parse_frontmatter "$f" description)"
    triggers="$(parse_frontmatter "$f" triggers_en)"
    [[ -z "$desc" ]] && desc="Run the $name command of the obsidian-second-brain skill."

    # Fold triggers into the description for implicit selection.
    if [[ -n "$triggers" ]]; then
      local trig_clean
      trig_clean="$(echo "$triggers" | tr -d '[]"' | sed 's/,/, /g; s/  */ /g; s/^ *//; s/ *$//')"
      [[ -n "$trig_clean" ]] && desc="$desc Triggers: $trig_clean."
    fi

    mkdir -p "$dst/$name"
    out="$dst/$name/SKILL.md"
    {
      echo "---"
      echo "name: $name"
      # Quote the description; escape embedded double quotes.
      printf 'description: "%s"\n' "${desc//\"/\\\"}"
      echo "---"
      echo
      command_body "$f"
    } > "$out"

    rewrite_tool_neutral "$out"
    rewrite_platform_paths "$out" "$CODEX_DIR"
  done
}

_codex_copy_references() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"
  cp -R "$src/." "$dst/"
  find "$dst" -type f -name '*.md' -print0 | while IFS= read -r -d '' f; do
    rewrite_platform_paths "$f" "$CODEX_DIR"
  done
}

_codex_copy_scripts() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"
  cp -R "$src/." "$dst/"
}

_codex_emit_install_hint() {
  local dst="$1"
  cat > "$dst/INSTALL.md" <<'EOF'
# Install on Codex CLI

```bash
# From the repo root, after running `bash scripts/build.sh --platform codex-cli`:
# Copy (or symlink) the built tree into your vault root:
cp -R dist/codex-cli/. /path/to/your/vault/
```

Then in your vault:

- `.agents/skills/<name>/SKILL.md` are native Codex Agent Skills. Codex
  discovers them automatically and loads each one's instructions only when it
  is selected (progressive disclosure). Invoke a skill with `$<name>`, pick it
  from `/skills`, or just describe the task and let Codex match it.
- `AGENTS.md` is the always-on operating manual Codex reads at session start
  (vault conventions + the AI-first rule). It is intentionally thin - the skill
  list is the router.
- `.codex/references/` holds shared specs (the AI-first vault rule) that skills
  reference.
- `.codex/scripts/` holds the Python helpers invoked by the research toolkit
  skills. Run them via `uv run -m scripts.research.<name>` from the vault root.

Start Codex CLI from the vault root. Skills run in your current session - no
`codex exec` wrapper, no per-command startup, and writes honor your session's
approval/sandbox mode.
EOF
}
