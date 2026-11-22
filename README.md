# Zig Skills for AI Coding Assistants

Version-specific Zig skills for AI tools. These skills help assistants generate correct code for modern Zig instead of outdated examples from older releases.

## Available Skills

| Skill | Purpose | Target |
| --- | --- | --- |
| [zig-0-15](./zig-0-15/) | Zig 0.15 API guidance | Zig 0.15.x |
| [zig-0-16](./zig-0-16/) | Zig 0.16 API guidance and migration notes | Zig 0.16.0 |
| [zig-0-17](./zig-0-17/) | Zig 0.17 API guidance and migration notes | Zig 0.17.1 |
| [zig-tiger-style](./zig-tiger-style/) | TigerStyle Zig coding guidelines and best practices | All Zig versions |

## Install

### 1. Via `npx skills`

```bash
# Interactive selection (choose which skills and agents to install)
npx skills add zigcc/skills

# Or install a specific version directly
npx skills add zigcc/skills --skill zig-0-17
```

### 2. Manual Copy

Copy the target skill directory to your AI tool's skill directory:

```bash
# OpenCode (project local)
mkdir -p .opencode/skill && cp -r zig-0-17 .opencode/skill/

# OpenCode (global)
mkdir -p ~/.config/opencode/skill && cp -r zig-0-17 ~/.config/opencode/skill/

# Claude Code
mkdir -p .claude/skills && cp -r zig-0-17 .claude/skills/

# Koda (global)
mkdir -p ~/.koda/skills && cp -r zig-0-17 zig-tiger-style ~/.koda/skills/
```

If the skills are kept in a local checkout, refresh the installed copies after every edit:

```bash
for s in zig-0-15 zig-0-16 zig-0-17 zig-tiger-style; do
    rm -rf ~/.koda/skills/"$s" && cp -r "$s" ~/.koda/skills/
done
```

Koda loads skills at session start, so restart the session (start a new conversation) after installing.

## Verifying Examples

Every pinned skill claims its examples compile. `scripts/check-skill-examples.sh` enforces that
by extracting each ```zig block and building it with the local toolchain:

```bash
scripts/check-skill-examples.sh zig-0-17   # check one skill
scripts/check-skill-examples.sh --all      # check skills pinned to the local Zig version
ZIG_CMD=/path/to/zig-0.16/zig scripts/check-skill-examples.sh zig-0-16
```

Blocks that illustrate the pre-migration API (`// OLD`, `// avoid`, `❌ WRONG`), naming sketches
and `build.zig` fragments are reported as skips, not failures — they are not compilable by design.
A skill pinned to another Zig minor is skipped under `--all`, because its examples are only
verifiable against the toolchain they document.

## Preparing a New Zig Version

`scripts/new-skill.sh` copies the newest skill and rewrites its version identifiers, marking
every code block `TODO-VERIFY`. It copies structure only: no API content is invented.

```bash
scripts/new-skill.sh 0.18.0
```

Run it once the release exists and its notes are readable. Then read the release notes, resolve
every `TODO-VERIFY`, run the checker, and add the row to the table above.

## Usage

### In Project Rules (Recommended)

Pin your project to a specific Zig version in `CLAUDE.md` or `AGENTS.md` so the AI assistant always follows the correct APIs:

```markdown
# Zig Guidelines

- For Zig 0.17.x, follow `.claude/skills/zig-0-17/SKILL.md` (or `.opencode/skill/zig-0-17/SKILL.md`)
- For Zig 0.16.0, follow `.claude/skills/zig-0-16/SKILL.md` (or `.opencode/skill/zig-0-16/SKILL.md`)
- For Zig 0.15.x, follow `.claude/skills/zig-0-15/SKILL.md` (or `.opencode/skill/zig-0-15/SKILL.md`)
```

### Direct Invocation

- **OpenCode**: Use the slash command:
  ```text
  /skill zig-0-17
  ```
- **Claude Code**: The skill is detected automatically, or mention it in your prompt:
  ```text
  Please use the zig-0-17 skill to review this code.
  ```
- **Koda**: Skills from `~/.koda/skills` (global) or `.koda/skills` (project local) are discovered
  automatically; load one by name with the skill-reading tool or mention it in your prompt:
  ```text
  Use the zig-0-17 skill to review this code.
  ```
- **Prompt reference** (any tool supporting file context):
  ```text
  @file .claude/skills/zig-0-17/SKILL.md
  ```
