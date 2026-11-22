#!/usr/bin/env bash
# Scaffolds a new version-pinned skill directory from an existing one.
#
# Run this only once a real Zig release exists and its release notes are readable.
# It copies structure and substitutes version numbers; it does NOT invent API
# content. Every block that needs verification is marked TODO-VERIFY.
#
# Usage:
#   scripts/new-skill.sh 0.18.0          # scaffolds zig-0-18/ from the newest skill
#   scripts/new-skill.sh 0.18.0 0.17.1   # explicit source version
#
# After scaffolding:
#   1. Read https://ziglang.org/download/<version>/release-notes.html
#   2. Resolve every TODO-VERIFY marker
#   3. scripts/check-skill-examples.sh zig-0-18
#   4. Add a row to the README.md table and refresh installed copies
#
# Refuses to overwrite an existing directory.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="${1:-}"
BASE="${2:-}"

if [[ ! "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: scripts/new-skill.sh <major.minor.patch> [source version]" >&2
    echo "Example: scripts/new-skill.sh 0.18.0" >&2
    exit 2
fi

# Without an explicit source, take the highest existing zig-0-* directory.
if [[ -z "$BASE" ]]; then
    BASE="$(find "$REPO_ROOT" -maxdepth 1 -type d -name 'zig-[0-9]*-[0-9]*' -printf '%f\n' \
        | sed 's/^zig-//' | tr '-' '.' | sort -t. -k1,1n -k2,2n | tail -1)"
    # Keep the source's patch level as written in its own frontmatter, if present.
    declared=""
    source_md="$REPO_ROOT/zig-${BASE//./-}/SKILL.md"
    if [[ -f "$source_md" ]]; then
        declared="$(sed -n '/^metadata:/,/^---/p' "$source_md" \
            | sed -n 's/^ *version: *"\([0-9.]*\)".*/\1/p' | head -1)"
    fi
    if [[ "$declared" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        BASE="$declared"
    else
        BASE="${BASE}.0"
    fi
fi

if [[ ! "$BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: could not determine the source skill version (got '$BASE')." >&2
    exit 1
fi

BASE_MM="${BASE%.*}"
NEW_MM="${NEW%.*}"
BASE_DIR="zig-${BASE_MM//./-}"
NEW_DIR="zig-${NEW_MM//./-}"

if [[ ! -f "$REPO_ROOT/$BASE_DIR/SKILL.md" ]]; then
    echo "ERROR: source skill $BASE_DIR/SKILL.md not found." >&2
    exit 1
fi
if [[ -e "$REPO_ROOT/$NEW_DIR" ]]; then
    echo "ERROR: $NEW_DIR already exists; refusing to overwrite." >&2
    exit 1
fi

cp -r "$REPO_ROOT/$BASE_DIR" "$REPO_ROOT/$NEW_DIR"

python3 - "$REPO_ROOT/$NEW_DIR" "$NEW" "$BASE" "$NEW_DIR" <<'PYTHON'
import re
import sys
from pathlib import Path

skill_dir, new, base, new_dir = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
base_mm, new_mm = base.rsplit(".", 1)[0], new.rsplit(".", 1)[0]
base_dash, new_dash = base_mm.replace(".", "-"), new_mm.replace(".", "-")

# Literal replacement, longest form first, so 0.17.1 cannot become 0.18.0.1 and a
# dashed directory name cannot be rewritten through its dotted pattern.
PAIRS = [(base, new), (base_mm, new_mm), (base_dash, new_dash)]

for file in sorted(skill_dir.rglob("*")):
    if file.is_file():
        text = file.read_text()
        for old, replacement in PAIRS:
            text = text.replace(old, replacement)
        # The version guard compares a bare minor number, e.g. `MINOR -ge 17`.
        if file.name == "check-zig-version.sh":
            text = re.sub(
                r"(-ge\s+)%s\b" % base_mm.split(".")[1],
                "-ge %s" % new_mm.split(".")[1],
                text,
            )
        file.write_text(text)

path = skill_dir / "SKILL.md"
text = path.read_text()

# The inherited patch-release note describes the previous release, not this one.
text = re.sub(r"\n>[^\n]*is a bug-fix release on top of[^\n]*\n", "\n", text)
text = re.sub(r"\n>\s*\n>\s*\n", "\n", text)

note = (
    "> **TODO-VERIFY**\n"
    ">\n"
    f"> Scaffolded from `zig-{base_dash}`; the body below still documents the **{base}** API.\n"
    f"> Before publishing or enabling this skill, check every section against the {new}\n"
    "> release notes. Do not guess an API: when a section cannot be verified, delete it\n"
    "> rather than paraphrasing it. Remove this block once the examples are verified\n"
    f"> with `scripts/check-skill-examples.sh {new_dir}`.\n"
)
pattern = re.compile(r"(> \*\*Release Notes\*\*:.*?\n)")
if pattern.search(text):
    text = pattern.sub(lambda m: m.group(1) + "\n" + note, text, count=1)
else:
    text = text.replace("\n# ", f"\n{note}\n# ", 1)

marker = "// TODO-VERIFY against %s release notes\n" % new_mm
text = text.replace("```zig\n", "```zig\n" + marker)

path.write_text(text)
print(f"  frontmatter version -> {new}")
print(f"  TODO-VERIFY markers -> {text.count('TODO-VERIFY')}")
PYTHON

echo "Created $NEW_DIR/ from $BASE_DIR/"
echo
echo "Next:"
echo "  1. Read https://ziglang.org/download/${NEW}/release-notes.html"
echo "  2. Resolve every TODO-VERIFY marker in $NEW_DIR/SKILL.md"
echo "  3. scripts/check-skill-examples.sh $NEW_DIR"
echo "  4. Add a row for $NEW_DIR to the README.md table"
