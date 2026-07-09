# Multi-Agent Support: Cowork skills, agent-neutral AGENTS.md, path-map seeding

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** (1) Claude support covers both Claude Code and Claude Cowork; (2) the generated vault `AGENTS.md` is agent-neutral (Codex, Claude Code, Cowork, Copilot, Gemini, ...); (3) seed scripts render `_system/path-map.yaml` from a template shipped in this repo. Then apply everything to the `ai-brain` vault and the local machine.

**Architecture:** The `claude-code` adapter additionally emits one native Agent Skill per command under `dist/claude-code/skills/<name>/SKILL.md` - installed into `~/.claude/skills/`, which **both** Claude Code and Claude Cowork read (Cowork does not read `~/.claude/commands/`). The `codex-cli` adapter's emitted `AGENTS.md` becomes a multi-agent operating manual: per-agent invocation section + routing tables/trigger phrases for agents without native skill discovery (format already proven by the hand-edited vault copy - this makes rebuilds stop regressing it). A new `templates/path-map.template.yaml` with `{{…}}` placeholders is rendered by `seed-macos.sh` / `seed-windows.ps1` into the vault when missing.

**Tech stack:** bash adapters (`adapters/*.sh`), PowerShell, pytest smoke tests (`tests/test_smoke.py`).

**Repos touched:**
- `~/work/obsidian-second-brain` (branch `ai/multi-agent-support`) - adapters, template, tests, docs
- `~/…/OneDrive-4wardPRO/_wip/AIOrg` - `scripts/seed-macos.sh`, `scripts/seed-windows.ps1`, `CLAUDE.md` (not a git repo)
- `~/work/ai-brain` - rebuild + copy + reconcile (has ~20 uncommitted files: the in-progress `.agents/skills` migration; this plan completes and commits that migration)
- Local `~/.claude` - replace 44 command symlinks with per-skill symlinks

---

## Task 1: Shared helper - fold triggers into description (DRY with codex adapter)

**Files:** Modify `adapters/lib.sh`, `adapters/codex-cli/adapter.sh`

- Add `compose_skill_description <file>` to `adapters/lib.sh`: returns the command's `description` frontmatter with `triggers_en` folded in (`… Triggers: a, b, c.`), defaulting when empty - extracted verbatim from `_codex_emit_skills` (adapters/codex-cli/adapter.sh:138-147).
- Replace that block in `_codex_emit_skills` with a call to the helper.
- Verify: `bash scripts/build.sh --platform codex-cli` → `dist/codex-cli/.agents/skills/obsidian-save/SKILL.md` unchanged vs before (diff a saved copy).
- Commit: `refactor: extract compose_skill_description into adapters/lib.sh`

## Task 2: claude-code adapter emits per-command skills (Cowork + Code)

**Files:** Modify `adapters/claude-code/adapter.sh`; test `tests/test_smoke.py`

- **Test first** (`test_claude_code_build_generates_per_command_skills`): build `claude-code`, assert `dist/claude-code/skills/obsidian-daily/SKILL.md` exists, frontmatter has `name: obsidian-daily` and a non-empty quoted `description` containing `Triggers:`; assert umbrella `SKILL.md` and `commands/obsidian-daily.md` still exist. Run → FAIL.
- Add `_cc_emit_skills "$src/commands" "$dst/skills"` to `adapter_build`: per command (respecting `should_include … claude-code`), write `skills/<name>/SKILL.md` with `name` + `description` (via `compose_skill_description`), then the command body **verbatim** (no tool-neutralization - Claude is the native dialect), prefixed by one support-files note:
  > Supporting files (`references/`, `scripts/`, `hooks/`) live in the sibling `obsidian-second-brain` skill directory (e.g. `~/.claude/skills/obsidian-second-brain/`). Resolve `references/...` and `scripts/...` paths there.
- Rewrite `_cc_emit_install_hint` (INSTALL.md): primary install is per-skill symlinks - works in **Claude Code and Claude Cowork** (both read `~/.claude/skills/`); `commands/` symlinks are legacy Claude-Code-only (do not install both - duplicate `/name`); for machines where `~/.claude/skills` isn't readable by Cowork, zip a skill folder and upload via Cowork → Customize → Skills.
- Run test → PASS. Commit: `feat(claude-code): emit per-command Agent Skills for Claude Code + Cowork`

## Task 3: Agent-neutral AGENTS.md from the codex-cli adapter

**Files:** Modify `adapters/lib.sh` (routing-table path format), `adapters/codex-cli/adapter.sh`, `adapters/copilot/adapter.sh` (INSTALL wording); test `tests/test_smoke.py`

- **Test first** (`test_codex_cli_agents_md_is_multi_agent`): build codex-cli; assert `AGENTS.md` does NOT contain "Codex CLI Operating Manual"; DOES contain "Claude Code", "Cowork", "GitHub Copilot", a routing-table row `` `.agents/skills/obsidian-save/SKILL.md` ``, and a "Trigger phrases" section. Run → FAIL.
- `emit_routing_table_grouped` / `_emit_one_category_section`: add optional 4th arg `path_suffix` (default `.md`); path cell becomes `<prefix>/<name><suffix>` so `.agents/skills` + `/SKILL.md` works; existing callers unaffected.
- Rewrite `_codex_emit_dispatcher`:
  - Title: `# Obsidian Second Brain — Agent Operating Manual`.
  - Intro: skills are N portable Agent Skills under `.agents/skills/<name>/SKILL.md` - the canonical, agent-neutral copy any agent can read.
  - **"How to invoke, per agent"** section: Codex CLI (`$<name>`, `/skills`, implicit); Claude Code & Claude Cowork (installed user skills `/name` preferred, else read the vault skill file); GitHub Copilot (no native discovery → routing tables); Gemini CLI & others (routing tables).
  - Keep: `_CLAUDE.md` first, AI-first rule (`.codex/references/ai-first-rules.md`), "do not invent skills", Scripts section.
  - Emit routing tables (`emit_routing_table_grouped "$src/commands" codex-cli ".agents/skills" "/SKILL.md"`) and trigger phrases (`emit_trigger_reference`), framed "for agents without native skill discovery".
  - Footer keeps the generated-by note + the preserved-vault-local-sections warning.
- CLAUDE.md pointer (`_codex_emit_pointer_files`): heading `# Claude Code / Claude Cowork`, text names both.
- `adapters/copilot/adapter.sh` INSTALL hint: routing tables now regenerate on every build (no longer vault-hand-maintained).
- Run tests → PASS. Commit: `feat(codex-cli): emit agent-neutral multi-agent AGENTS.md with routing tables`

## Task 4: path-map template + seed-script rendering

**Files:** Create `templates/path-map.template.yaml` (fork); modify `AIOrg/scripts/seed-macos.sh`, `AIOrg/scripts/seed-windows.ps1`

- Template = current vault `_system/path-map.yaml` structure with placeholders:
  `{{MACOS_WORK_ROOT}}`, `{{MACOS_ONEDRIVE_ROOT}}`, `{{WINDOWS_WORK_ROOT}}`, `{{WINDOWS_ONEDRIVE_ROOT}}` (each root derived: `<work>/ai-brain`, `<work>/code`, `<work>/ai-skills`, `<work>/obsidian-second-brain`, `<onedrive>/projects`, `<onedrive>/_wip`, `<onedrive>/projects/_published`). Header comment: rendered by the seed scripts; hand-edit the vault copy afterwards if roots move.
- `seed-macos.sh`: new step after clone/sync - if `$BRAIN_ROOT/_system/path-map.yaml` missing: `mkdir -p _system`, render via `sed` with `MACOS_*` from `$WORK_ROOT`/`$ONEDRIVE_ROOT` (tilde-ified: `${WORK_ROOT/#$HOME/\~}`), `WINDOWS_*` defaults (`C:/work`, `%OneDriveCommercial%`). If present: `path-map: present — left untouched`. Honors `--dry-run`.
- `seed-windows.ps1`: mirror in PowerShell - `WINDOWS_*` from `$WorkRoot` (backslashes → `/`) and `%OneDriveCommercial%` literal when `$OneDriveRoot` came from that env var, else the actual path; `MACOS_*` defaults (`~/work`, `~/Library/CloudStorage/OneDrive-4wardPRO`). Honors `-DryRun`.
- Verify: `WORK_ROOT=/tmp/x scripts/seed-macos.sh --dry-run` prints the render step; run the render function against a scratch dir and diff output vs the vault's committed path-map (must match modulo comments).
- Commits: fork `feat: add path-map.yaml template for seed scripts`; AIOrg has no git - just save.

## Task 5: rebuild, test, refresh local ~/.claude install

- `bash scripts/build.sh` (all platforms) + `uv run pytest tests/ -q` → all pass.
- Remove the 44 `~/.claude/commands/*.md` symlinks that point into `dist/claude-code/commands` (only those - leave user-authored files).
- Symlink every `dist/claude-code/skills/<name>` → `~/.claude/skills/<name>` (skip if a non-link entry exists; report). Keep the existing umbrella `obsidian-second-brain` symlink.
- Verify: `ls -l ~/.claude/skills | wc -l` ≈ 44 + umbrella + ai-skills; no dangling symlinks (`find ~/.claude/skills ~/.claude/commands -xtype l`).
- Manual (Dani): restart Claude Code and Cowork; `/obsidian-daily` visible in both.

## Task 6: apply to the ai-brain vault (completes the pending migration)

Order matters - the dirty working tree holds the only copy of the vault-local AGENTS.md sections:

1. Save vault-local sections from the **current working-tree** `AGENTS.md` (AI Project Init Base Rules, Memory Protocol, Path resolution, Additional cross-agent skills) to a scratch file.
2. `cp -R dist/codex-cli/. ~/work/ai-brain/` and `cp -R dist/copilot/.github ~/work/ai-brain/`.
3. Re-insert the four vault-local sections into the new `AGENTS.md` (Init Base Rules + Memory Protocol after the intro; Path resolution + ai-skills sections before the footer).
4. Remove the obsolete `.codex/commands/` directory (superseded by `.agents/skills/`).
5. Review `git -C ~/work/ai-brain diff` + `status`; single commit: `Complete .agents/skills migration + multi-agent AGENTS.md (Claude Code/Cowork/Codex/Copilot/Gemini)`; push.

## Task 7: fork commit/push + AIOrg docs

- Fork: push `ai/multi-agent-support`.
- `AIOrg/CLAUDE.md`: update Seed Scripts section (step: render `_system/path-map.yaml` from `templates/path-map.template.yaml` when missing), the Updating-After-Tooling-Changes section (routing tables now regenerate - only the four vault-local sections still need re-applying; local Claude install is per-skill symlinks incl. Cowork), and Implementation Status (dated 2026-07-09).
- Delete this plan's scratch files.

**Out of scope / notes:** Cowork visibility can only be confirmed by opening Cowork after install (docs: Claude Desktop/Cowork reads `~/.claude/skills/`; zip-upload via Customize → Skills is the fallback). Windows seeding remains untested until run on a Windows machine.
