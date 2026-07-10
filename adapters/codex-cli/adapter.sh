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

# Claude Code / Claude Cowork

All project instructions live in **AGENTS.md** at the repository root, imported above and treated as the single source of truth. This applies to every Claude surface working in this vault - Claude Code and Claude Cowork alike. Read it and follow every rule there, including the memory protocol.

Do not duplicate or restate instructions in this file. If a rule needs to change, change it in `AGENTS.md`.
EOF

  cat > "$dst/GEMINI.md" <<'EOF'
# Gemini CLI

The single source of truth for this project is **AGENTS.md** at the repository root.

Read `AGENTS.md` and follow all instructions there, including the memory protocol: read the `memory/` directory at the start of work and keep it updated as the project progresses.

This file is a pointer only. It intentionally contains no rules of its own - `AGENTS.md` governs. If a rule needs to change, change it in `AGENTS.md`.
EOF

  mkdir -p "$dst/.github"
  cat > "$dst/.github/copilot-instructions.md" <<'EOF'
# GitHub Copilot

The single source of truth for this project is **AGENTS.md** at the repository root.

Read `AGENTS.md` and follow all instructions there, including the memory protocol: read the `memory/` directory at the start of work and keep it updated as the project progresses.

This file is a pointer only. It intentionally contains no rules of its own; `AGENTS.md` governs. If a rule needs to change, change it in `AGENTS.md`.
EOF
}

# Emit AGENTS.md at the dist root: the single operating manual EVERY agent
# reads (the pointer files route them here). Agent-neutral by design - it
# explains per-agent invocation, then carries routing tables + trigger
# phrases for agents without native skill discovery (Copilot, Gemini, or a
# Claude session without the skills installed).
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
# Obsidian Second Brain - Agent Operating Manual

This vault runs the **obsidian-second-brain** skill as ${count} portable
**Agent Skills** under \`.agents/skills/<name>/SKILL.md\`. That directory is
the canonical, agent-neutral copy: any agent can read a skill file and follow
it. This manual is the single source of truth for every agent working in this
vault - Codex CLI, Claude Code, Claude Cowork, GitHub Copilot, Gemini CLI, and
anything else; the pointer files (\`CLAUDE.md\`, \`GEMINI.md\`,
\`.github/copilot-instructions.md\`) all route here.

## Vault-local custom instructions (AGENTS.local.md)

\`AGENTS.local.md\` at the vault root carries the vault owner's **custom
instructions** - rules, protocols, conventions, and extra skill routing that
belong to this vault, not to the tooling. The tooling never creates, modifies,
or deletes it: rebuilding or reinstalling obsidian-second-brain regenerates
only this file (\`AGENTS.md\`) and the skill tree.

**Every agent must read \`AGENTS.local.md\` immediately after this file and
treat its instructions as binding.** If it conflicts with this generated
manual, \`AGENTS.local.md\` wins.

## How to invoke skills, per agent

- **Codex CLI** discovers \`.agents/skills/\` natively (progressive
  disclosure). Invoke with \`\$<skill-name>\`, pick from \`/skills\`, or let
  implicit selection match the description. No routing table needed.
- **Claude Code / Claude Cowork**: if the skills are installed user-side
  (\`~/.claude/skills/\`, from the claude-code build), invoke them as
  \`/<name>\` or let Claude select them. Otherwise use the routing tables
  below and read the matching \`.agents/skills/<name>/SKILL.md\`.
- **GitHub Copilot** has no native skill discovery: use the routing tables
  and trigger phrases below, then read and follow the matching skill file
  step by step.
- **Gemini CLI and any other agent**: same as Copilot - route via the tables
  below.

## How to operate

1. Read \`AGENTS.local.md\` in the vault root, if it exists: it carries the
   vault conventions (folder map, daily note format, naming) and the owner's
   custom instructions (see section above).
2. When the user's request matches a skill, invoke it via your client's best
   mechanism (see per-agent list above).
3. Treat the AI-first vault rule (\`.codex/references/ai-first-rules.md\`) as
   non-negotiable for every note you write: the \`## For future Claude\`
   preamble (a fixed, historical header name - it addresses whichever agent
   reads the note next), rich frontmatter (\`type\`, \`date\`, \`tags\`,
   \`ai-first: true\`), \`[[wikilinks]]\` for every person/project/concept,
   recency markers per external claim, sources verbatim, confidence levels
   where applicable.
4. Do not invent skills. If none matches, ask the user or fall back to plain
   natural-language help.

## Command routing tables for agents without native skill discovery

When the user request matches a command below, read the linked skill file and
follow it step by step. Agents with native discovery (Codex, Claude with the
skills installed) can ignore these tables - the skill list is the router.
EOF
    emit_routing_table_grouped "$src/commands" "$CODEX_PLATFORM" ".agents/skills" "/SKILL.md"
    emit_trigger_reference "$src/commands" "$CODEX_PLATFORM"
    cat <<EOF

## Scripts

Python helpers live under \`.codex/scripts/\`. They run via
\`uv run -m scripts.research.<name>\` from the vault root. Skills that need them
reference the exact invocation inside the skill body.

---

*Fully generated by adapters/codex-cli/adapter.sh - do not edit this file.
All vault-local content (project init rules, memory protocol, path
resolution, extra skill repos, conventions) belongs in \`AGENTS.local.md\`,
which rebuilds never touch.*
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
  local f name desc out
  for f in "$src"/*.md; do
    [[ -f "$f" ]] || continue
    should_include "$f" "$CODEX_PLATFORM" || continue

    name="$(basename "$f" .md)"
    desc="$(compose_skill_description "$f")"

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
