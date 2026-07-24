#!/usr/bin/env bash
# grader_lib.sh — shared helpers for HYF Data Track autograders.
# Source this at the top of test.sh:
#   source "$(dirname "$0")/grader_lib.sh"
#
# Provides: pass(), fail(), warn(), blocker(), print_results(), write_score(),
# and a set of common static-analysis checks derived from recurring
# PR review patterns across cohort c55.
#
# blocker(): use for findings that must fail the PR regardless of points
# (leaked secrets, missing required evidence like screenshots). Behaves like
# fail() in the printed report, but forces write_score() to pass=false.

_grader_details=()
_grader_blocker=false

pass() { _grader_details+=("✓ PASS  $1"); }
fail() { _grader_details+=("✗ FAIL  $1"); }
warn() { _grader_details+=("⚠ WARN  $1"); }
blocker() { _grader_details+=("🚫 BLOCKER  $1"); _grader_blocker=true; }

print_results() {
  local header="${1:-Autograder Results}"
  echo ""
  echo "=== $header ==="
  for line in "${_grader_details[@]}"; do echo "  $line"; done
  echo ""
}

write_score() {
  # write_score <score> <passing> [<outfile>]
  local score="$1"
  local passing="$2"
  local outfile="${3:-$(dirname "${BASH_SOURCE[0]}")/score.json}"
  local pass_flag="false"
  [[ "$score" -ge "$passing" ]] && pass_flag="true"
  if [[ "$_grader_blocker" == true ]]; then
    pass_flag="false"
    echo "🚫 A blocker was found -- forcing pass=false regardless of score." >&2
  fi
  cat > "$outfile" << JSON
{
  "score": $score,
  "pass": $pass_flag,
  "passingScore": $passing
}
JSON
  echo "Score: $score / 100  (passing: $passing)  pass=$pass_flag"
}

# ── Common static-analysis checks ────────────────────────────────────────────
# Each function: returns 0 on pass, 1 on fail/warn (for caller logic).
# All feedback goes through pass()/fail()/warn() so it appears in print_results.

check_no_print_statements() {
  # Usage: check_no_print_statements <dir> [label]
  # Flags bare print() calls that should be logging calls.
  local dir="${1:-.}"
  local label="${2:-$dir}"
  local found
  found=$(grep -rn "^[[:space:]]*print(" "$dir" --include="*.py" 2>/dev/null | grep -v "# noqa" || true)
  if [[ -n "$found" ]]; then
    local count
    count=$(echo "$found" | wc -l | tr -d ' ')
    warn "$label: $count print() call(s) found — use logging.info/warning/error instead (see Week 1 Ch1)"
    return 1
  fi
  return 0
}

check_no_notimplemented() {
  # Usage: check_no_notimplemented <dir> [label]
  # Flags NotImplementedError stubs left in after implementation.
  local dir="${1:-.}"
  local label="${2:-$dir}"
  local found
  found=$(grep -rn "raise NotImplementedError" "$dir" --include="*.py" 2>/dev/null || true)
  if [[ -n "$found" ]]; then
    fail "$label: raise NotImplementedError still present — remove stubs before submitting"
    return 1
  fi
  return 0
}

check_no_relative_imports() {
  # Usage: check_no_relative_imports <dir> [label]
  # Flags `from .module import x` in scripts not inside a proper package.
  # Relative imports break the grader: python3 src/cleaner.py fails with
  # "attempted relative import with no known parent package".
  local dir="${1:-.}"
  local label="${2:-$dir}"
  local found
  found=$(grep -rn "^from \." "$dir" --include="*.py" 2>/dev/null || true)
  if [[ -n "$found" ]]; then
    fail "$label: relative import found (from .module) — use absolute: 'from src.module import x'"
    return 1
  fi
  return 0
}

check_no_logging_in_utils() {
  # Usage: check_no_logging_in_utils <utils_file>
  # utils.py should be pure helpers; logging config belongs in the entry point.
  local file="${1:-task-1/src/utils.py}"
  if [[ ! -f "$file" ]]; then return 0; fi
  if grep -qE "logging\.basicConfig|logging\.getLogger" "$file"; then
    warn "$file: logging.basicConfig/getLogger found — logging setup belongs in cleaner.py or the entry-point, not in utils"
    return 1
  fi
  return 0
}

check_gitignore_python() {
  # Usage: check_gitignore_python [<gitignore_path>]
  # Warns when Python cache patterns are absent from .gitignore.
  local gi="${1:-.gitignore}"
  if [[ ! -f "$gi" ]]; then
    warn ".gitignore is missing — add one so __pycache__/ and *.pyc are not committed"
    return 1
  fi
  local ok=true
  if ! grep -q "__pycache__" "$gi"; then
    warn ".gitignore missing __pycache__/ — Python bytecode cache dirs should not be committed"
    ok=false
  fi
  if ! grep -qE "^\*\.pyc$|^.*\*\.pyc" "$gi"; then
    warn ".gitignore missing *.pyc — compiled Python files should not be committed"
    ok=false
  fi
  if ! grep -qE "^\.env$|^\.env\b" "$gi"; then
    warn ".gitignore missing .env — secret files should not be committed"
    ok=false
  fi
  if [[ "$ok" = true ]]; then pass ".gitignore correctly excludes __pycache__/, *.pyc, and .env"; fi
}

check_screenshot_is_png() {
  # Usage: check_screenshot_is_png <expected_path> [<wrong_ext_glob>]
  # Awards full credit for .png, warns (and still credits) for .jpg/.jpeg,
  # zero for missing. Matches the pattern flagged in c55 PR reviews.
  local expected_png="$1"
  local dir
  dir="$(dirname "$expected_png")"
  local base
  base="$(basename "$expected_png" .png)"

  if [[ -s "$expected_png" ]]; then
    pass "screenshot is $expected_png (.png format ✓)"
    return 0
  fi
  for ext in jpg jpeg; do
    if [[ -s "$dir/$base.$ext" ]]; then
      warn "screenshot is .$ext but should be .png — rename to $base.png (partial credit still given)"
      return 1
    fi
  done
  fail "screenshot missing: $expected_png not found"
  return 2
}

check_silent_zero_in_except() {
  # Usage: check_silent_zero_in_except <file>
  # Detects the pattern: try: x = compute() / except: x = 0
  # which silently corrupts data instead of skipping or raising.
  local file="$1"
  if [[ ! -f "$file" ]]; then return 0; fi
  local found
  found=$(python3 - "$file" 2>/dev/null << 'PY'
import ast, sys
try:
    tree = ast.parse(open(sys.argv[1]).read())
except SyntaxError:
    sys.exit(0)
for node in ast.walk(tree):
    if isinstance(node, ast.ExceptHandler):
        for stmt in node.body:
            if isinstance(stmt, ast.Assign):
                if isinstance(stmt.value, ast.Constant) and stmt.value.value == 0:
                    print(f"line {stmt.lineno}: '{ast.unparse(stmt)}' — sets field to 0 in except block (silent data corruption)")
PY
)
  if [[ -n "$found" ]]; then
    warn "$file: silent 0-assignment in except block — skip the row or raise instead of setting to 0:\n    $found"
    return 1
  fi
  return 0
}

check_exception_logged() {
  # Usage: check_exception_logged <dir>
  # Warns when except blocks log/print a message but don't include the
  # exception variable (e, err, exc), meaning the error type is lost.
  local dir="${1:-.}"
  local found
  found=$(python3 - "$dir" 2>/dev/null << 'PY'
import ast, os, sys
issues = []
for root, _, files in os.walk(sys.argv[1]):
    for fname in files:
        if not fname.endswith(".py"):
            continue
        path = os.path.join(root, fname)
        try:
            tree = ast.parse(open(path).read())
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.ExceptHandler):
                continue
            exc_var = node.name  # e.g. "e" in `except ValueError as e`
            if not exc_var:
                continue
            for stmt in node.body:
                for call in ast.walk(stmt):
                    if not isinstance(call, ast.Call):
                        continue
                    # Is it a logging.* or print call?
                    func = call.func
                    is_log = (isinstance(func, ast.Attribute) and
                              isinstance(func.value, ast.Name) and
                              func.value.id == "logging")
                    is_print = isinstance(func, ast.Name) and func.id == "print"
                    if not (is_log or is_print):
                        continue
                    # Does the call reference the exception variable?
                    src = ast.unparse(call)
                    if exc_var not in src:
                        issues.append(f"{path}:{call.lineno}: log message doesn't include exception variable '{exc_var}' — add it for easier debugging")
if issues:
    for i in issues[:3]:  # cap at 3 to keep output readable
        print(i)
PY
)
  if [[ -n "$found" ]]; then
    warn "exception variable not included in log message (harder to debug):\n    $found"
    return 1
  fi
  return 0
}

check_ruff() {
  # Usage: check_ruff <dir> [<select>]
  # Runs ruff on <dir> if available; warns on violations.
  # Default select: F401 (unused imports), E302 (missing blank lines).
  local dir="${1:-.}"
  local select="${2:-F401,E302,E303}"
  if ! command -v ruff &>/dev/null && ! python3 -m ruff --version &>/dev/null 2>&1; then
    return 0  # ruff not installed — skip silently
  fi
  local out
  out=$(python3 -m ruff check --select="$select" --output-format=text "$dir" 2>/dev/null || true)
  if [[ -n "$out" ]]; then
    local count
    count=$(echo "$out" | grep -c "\.py:" || true)
    warn "$dir: ruff found $count style issue(s) (unused imports / missing blank lines) — run 'ruff check $dir' to see details"
    return 1
  fi
  pass "$dir: no ruff style issues (F401/E302/E303)"
  return 0
}
