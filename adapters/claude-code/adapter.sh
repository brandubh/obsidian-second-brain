#!/usr/bin/env bash
# =============================================================================
# adapters/claude-code/adapter.sh - Claude / Claude Cowork platform adapter
# =============================================================================
# Sourced by scripts/build.sh AFTER adapters/lib.sh.
# Writes dist/claude-code/ serving BOTH Claude surfaces:
#   - skills/<name>/SKILL.md - one Agent Skill per command. Installed into
#     ~/.claude/skills/ these are discovered by Claude Code AND Claude Cowork
#     (Cowork reads ~/.claude/skills/ but never ~/.claude/commands/). In
#     Claude Code each also surfaces as the /name slash command.
#   - commands/ - legacy slash-command files (Claude Code only). Kept for
#     existing installs; do not install both surfaces or /name duplicates.
#   - SKILL.md - the umbrella skill carrying references/, scripts/, hooks/.
# =============================================================================

CC_PLATFORM="claude-code"

# adapter_build <src_root> <dst_root>
adapter_build() {
  local src="$1" dst="$2"

  _cc_copy_commands "$src/commands" "$dst/commands"
  _cc_emit_skills "$src/commands" "$dst/skills"
  _cc_copy_skill_manifest "$src" "$dst"
  _cc_copy_references "$src/references" "$dst/references"
  _cc_copy_scripts "$src/scripts" "$dst/scripts"
  _cc_copy_hooks "$src/hooks" "$dst/hooks"
  _cc_emit_install_hint "$dst"
}

# Identity copy of slash commands - Claude Code's source format matches ours.
_cc_copy_commands() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"
  local f
  for f in "$src"/*.md; do
    [[ -f "$f" ]] || continue
    should_include "$f" "$CC_PLATFORM" || continue
    cp "$f" "$dst/$(basename "$f")"
  done
}

# Emit one Agent Skill per command: skills/<name>/SKILL.md.
# Frontmatter carries name + description (triggers folded in, same as the
# codex-cli adapter) so Cowork's and Code's implicit selection match the
# trigger phrases. The body is the command body VERBATIM - Claude is the
# native dialect, so no tool neutralization and no path rewriting. A short
# preamble points at the sibling umbrella skill dir for supporting files.
_cc_emit_skills() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  local f name desc out
  for f in "$src"/*.md; do
    [[ -f "$f" ]] || continue
    should_include "$f" "$CC_PLATFORM" || continue

    name="$(basename "$f" .md)"
    desc="$(compose_skill_description "$f")"

    mkdir -p "$dst/$name"
    out="$dst/$name/SKILL.md"
    {
      echo "---"
      echo "name: $name"
      printf 'description: "%s"\n' "${desc//\"/\\\"}"
      echo "---"
      echo
      echo "> Supporting files (\`references/\`, \`scripts/\`, \`hooks/\`) live in the sibling \`obsidian-second-brain\` skill directory (e.g. \`~/.claude/skills/obsidian-second-brain/\`). Resolve \`references/...\` and \`scripts/...\` paths there."
      echo
      command_body "$f"
    } > "$out"
  done
}

# Copy SKILL.md (the Claude Code skill manifest) verbatim.
_cc_copy_skill_manifest() {
  local src="$1" dst="$2"
  [[ -f "$src/SKILL.md" ]] && cp "$src/SKILL.md" "$dst/SKILL.md"
}

_cc_copy_references() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"
  cp -R "$src/." "$dst/"
}

_cc_copy_scripts() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"
  cp -R "$src/." "$dst/"
}

_cc_copy_hooks() {
  local src="$1" dst="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"
  cp -R "$src/." "$dst/"
}

_cc_emit_install_hint() {
  local dst="$1"
  cat > "$dst/INSTALL.md" <<'EOF'
# Install for Claude Code AND Claude Cowork

Both Claude surfaces read `~/.claude/skills/`; only Claude Code reads
`~/.claude/commands/`. Install the per-command skills so everything works in
both:

```bash
# From the repo root, after running `bash scripts/build.sh --platform claude-code`:
ln -sfn "$(pwd)/dist/claude-code" ~/.claude/skills/obsidian-second-brain
for s in "$(pwd)/dist/claude-code/skills/"*/; do
  ln -sfn "${s%/}" ~/.claude/skills/"$(basename "$s")"
done
```

Restart Claude Code / Cowork. Every command is now a skill: `/obsidian-daily`,
`/research`, etc. work in Claude Code, and Cowork discovers the same skills by
name and description.

Do NOT also symlink `dist/claude-code/commands/*.md` into `~/.claude/commands/`
- a command file and a skill with the same name both create `/name`, producing
duplicates. The `commands/` tree exists only for legacy installs; if you have
old symlinks there, remove them:

```bash
find ~/.claude/commands -maxdepth 1 -type l \
  -lname '*dist/claude-code/commands/*' -delete
```

## Cowork without local ~/.claude access

If Cowork on a machine cannot read `~/.claude/skills/` (e.g. managed setups),
zip any `dist/claude-code/skills/<name>/` folder and upload it in Cowork via
**Customize → Skills**. Uploaded skills are private to your account.
EOF
}
