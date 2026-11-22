#!/usr/bin/env bash
# Compiles every ```zig block in a skill's SKILL.md against the local toolchain.
#
# Reports FAIL only for genuine API breakage. Wrapper artifacts (an unused local
# created by the harness, a name the documented snippet expected from its
# surroundings) are classified as skips, so a version bump shows real breakage:
# copy the skill directory, fix the APIs, run this until it is clean.
#
# Usage:
#   scripts/check-skill-examples.sh zig-0-17          # check one skill
#   scripts/check-skill-examples.sh --all             # check every skill
#   ZIG_CMD=/path/to/zig scripts/check-skill-examples.sh zig-0-18
#
# Exit code: number of failing blocks (0 = clean).

set -uo pipefail

ZIG_CMD="${ZIG_CMD:-zig}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v "$ZIG_CMD" &>/dev/null; then
    echo "ERROR: '$ZIG_CMD' not found. Set ZIG_CMD or add zig to PATH." >&2
    exit 1
fi

SKILLS=()
EXPLICIT=0
if [[ "${1:-}" == "--all" ]]; then
    while IFS= read -r skill_md; do
        SKILLS+=("$(dirname "$skill_md")")
    done < <(find "$REPO_ROOT" -mindepth 2 -maxdepth 2 -name SKILL.md | sort)
elif [[ -n "${1:-}" ]]; then
    # Accept both a bare directory name and an absolute path.
    EXPLICIT=1
    if [[ "$1" = /* ]]; then
        SKILLS+=("${1%/}")
    else
        SKILLS+=("$REPO_ROOT/${1%/}")
    fi
else
    grep '^#' "${BASH_SOURCE[0]}" | grep -v '^#!' | sed 's/^# \{0,1\}//'
    exit 2
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Blocks that deliberately show the pre-migration API ("OLD"/"avoid") must NOT
# compile, so they are skipped rather than treated as failures.
read -r -d '' HARNESS <<'PYTHON'
import os
import re
import subprocess
import sys

path = sys.argv[1]
workdir = sys.argv[2]
zig = sys.argv[3]
lines = open(path).read().split("\n")

# Deliberately-wrong snippets illustrate the pre-migration API.
OLD = re.compile(r"//\s*(?:❌|WRONG|OLD\b|avoid\b)|COMPILE ERROR|deprecated|❌", re.I)
PLACEHOLDER = re.compile(r"^\s*(//|/\*|\.\.\.|<|\{ ?\.\.\.)")
# A name the snippet expected from its surroundings (build.zig step, allocator in
# scope). Supplying it is the harness's job, so its absence is not skill breakage.
UNDECLARED = re.compile(r"use of undeclared identifier '([A-Za-z_][A-Za-z0-9_]*)'")
ARTIFACT = re.compile(r"unused local (constant|variable|function)|unused function parameter")

# Verified against the pinned toolchain, so the harness itself cannot introduce
# a false failure through a stale idiom.
PRELUDE = {
    "gpa": "var __backing_gpa: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});\n",
    "allocator": "var __backing_alloc: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});\n",
    "arena": "var __backing_arena: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});\n",
}
POSTLUDE = {
    "gpa": "const gpa = &__backing_gpa;\n",
    "allocator": "const allocator = __backing_alloc.allocator();\n",
    "arena": "const arena = __backing_arena.allocator();\n",
}

blocks = []
i = 0
while i < len(lines):
    if re.match(r"^\s*```zig\s*$", lines[i]):
        start = j = i + 1
        while j < len(lines) and not re.match(r"^\s*```\s*$", lines[j]):
            j += 1
        blocks.append((start + 1, "\n".join(lines[start:j])))
        i = j
    i += 1


def compile_src(src, tag):
    src_path = os.path.join(workdir, f"{tag}.zig")
    with open(src_path, "w") as handle:
        handle.write(src)
    error = "unknown error"
    for cmd in (
        [zig, "ast-check", src_path],
        [zig, "build-obj", "--cache-dir", os.path.join(workdir, "cache"), src_path],
    ):
        # cwd=workdir so build-obj artifacts never land in the repository.
        proc = subprocess.run(cmd, capture_output=True, text=True, cwd=workdir)
        if proc.returncode == 0:
            return True, ""
        error = ((proc.stderr or "").strip() or error).replace(workdir + "/", "")
    return False, error


def candidates(code, tag):
    """Wrap a block so it compiles standalone without editing documented code."""
    std = "" if '@import("std")' in code else 'const std = @import("std");\n'
    standalone = re.search(r"^\s*(pub )?fn |^\s*test |^\s@test|\bcomptime\s*\{", code, re.M)
    indented = "\n".join("    " + line for line in code.split("\n"))
    bodies = [code] if standalone else [
        code,
        "pub fn main() !void {\n" + indented + "\n}\n",
        "test \"skill example\" {\n" + indented + "\n}\n",
    ]
    for offset, body in enumerate(bodies):
        yield f"{std}{body}", f"{tag}_{offset}"


def check(code, tag):
    """Returns (status, detail): status is ok / skip / fail."""
    supplied = []
    for _ in range(5):
        for body, name in candidates(code, tag):
            prefix = "".join(PRELUDE[n] + POSTLUDE[n] for n in supplied if n in PRELUDE)
            ok, error = compile_src(prefix + body, name)
            if ok or ARTIFACT.search(error):
                return "ok", ""
            missing = UNDECLARED.findall(error)
            if missing and missing[0] in PRELUDE and missing[0] not in supplied:
                supplied.append(missing[0])
                break
            if missing:
                return "skip", f"needs '{missing[0]}' from surrounding context"
        else:
            return "fail", error.split("\n")[0]
    return "skip", "needs surrounding context"


def is_illustrative(code):
    """Naming sketches and pseudo-code are not compilable by design."""
    if re.search(r"\{\s*\.\.\.\s*\}|<\s*[A-Za-z_]+\s*>", code):
        return True
    statements = [
        line.strip() for line in code.split("\n")
        if line.strip() and not PLACEHOLDER.match(line)
    ]
    if not statements:
        return True
    # A sketch lists bare expressions: no declaration anywhere and no statement
    # terminator, e.g. the division-intent and naming examples in zig-tiger-style.
    declared = re.search(r"\b(const|var|fn|test|struct|enum|union|defer|errdefer|comptime|pub)\b|@import", code)
    terminated = any(re.sub(r"//.*$", "", line).rstrip().endswith((";", "{", "}")) for line in statements)
    if not declared and not terminated:
        return True
    # A sketch line carries no statement punctuation at all.
    sketches = sum(1 for line in statements if not re.search(r"[;{}()=]", line.split("//")[0]))
    return sketches * 2 > len(statements)


passed = failed = skipped = 0
for index, (lineno, code) in enumerate(blocks):
    if OLD.search(code):
        skipped += 1
        continue
    if is_illustrative(code):
        skipped += 1
        print(f"  skip  L{lineno:<4} illustrative sketch, not compilable code")
        continue

    status, detail = check(code, f"b{index}")
    head = code.strip().split("\n")[0][:64]
    if status == "ok":
        passed += 1
    elif status == "skip":
        skipped += 1
        print(f"  skip  L{lineno:<4} {detail}: {head}")
    else:
        failed += 1
        print(f"  FAIL  L{lineno:<4} {head}")
        print(f"        {detail[:160]}")

print(f"  blocks: {len(blocks)}  ok: {passed}  skipped: {skipped}  failed: {failed}")
sys.exit(failed)
PYTHON

total_failures=0
checked=0
skipped_skills=0
local_minor="$($ZIG_CMD version | cut -d. -f1,2)"
for skill_dir in "${SKILLS[@]}"; do
    skill_md="$skill_dir/SKILL.md"
    if [[ ! -f "$skill_md" ]]; then
        echo "ERROR: no SKILL.md in $skill_dir" >&2
        exit 1
    fi
    name="$(basename "$skill_dir")"
    # A skill is only verifiable against the toolchain it is pinned to. Compiling
    # zig-0-15 examples with zig 0.17 reports breakage that is not a defect.
    pinned="$(sed -n '/^metadata:/,/^---/p' "$skill_md" | sed -n 's/^ *version: *"\([0-9]*\.[0-9]*\)\..*/\1/p' | head -1)"
    if [[ $EXPLICIT -eq 0 && -n "$pinned" && "$pinned" != "$local_minor" ]]; then
        echo "== $name (pinned to $pinned, local zig is $local_minor — not verifiable here)"
        skipped_skills=$((skipped_skills + 1))
        continue
    fi
    checked=$((checked + 1))
    name="$(basename "$skill_dir")"
    if [[ -x "$skill_dir/scripts/check-zig-version.sh" ]]; then
        declared="$(ZIG_CMD="$ZIG_CMD" bash "$skill_dir/scripts/check-zig-version.sh" 2>&1 | head -1)"
        echo "== $name ($declared)"
    else
        echo "== $name"
    fi
    python3 -c "$HARNESS" "$skill_md" "$WORKDIR" "$ZIG_CMD"
    failures=$?
    total_failures=$((total_failures + failures))
done

echo
if [[ $checked -eq 0 ]]; then
    echo "FAILED: no skill was checked (nothing matched the given path or --all)." >&2
    exit 1
fi
if [[ $total_failures -eq 0 ]]; then
    echo "OK: all verifiable skill examples compile with $($ZIG_CMD version)."
    if [[ $skipped_skills -gt 0 ]]; then
        echo "Note: $skipped_skills skill(s) are pinned to another Zig version; run this"
        echo "script with that toolchain in ZIG_CMD to verify them."
    fi
else
    echo "FAILED: $total_failures example block(s) do not compile with $($ZIG_CMD version)."
fi
exit $total_failures
