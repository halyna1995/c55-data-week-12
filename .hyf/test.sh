#!/usr/bin/env bash
# Week 12 autograder: static analysis only.
# The DAG needs a running Astro/Airflow stack and a live Azure PostgreSQL
# connection that CI cannot reach, so this checks file presence and code
# patterns in dags/taxi_pipeline.py and the docs. The actual green run,
# backfill idempotency, and shared-Airflow deploy are reviewed by a teacher.
# Total points: 100. Passing score: 60.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
DAG="$REPO_ROOT/dags/taxi_pipeline.py"

source "$SCRIPT_DIR/grader_lib.sh"

cat > "$SCRIPT_DIR/score.json" <<'INIT'
{"score": 0, "pass": false, "passingScore": 60}
INIT

score=0
PASSING=60

# grep the DAG with '#'-comments stripped, so a "# TODO: run dbt via uvx"
# guide comment in the starter does not count as real student code.
daggrep() { sed -E 's/#.*$//' "$DAG" | grep -qE "$1"; }

file_has_content() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  grep -qvE '^[[:space:]]*$' "$f" 2>/dev/null || return 1
  return 0
}

# ── Level 1 (20 pts): required files exist ──────────────────────────────────
l1=0
required_files=(
  "dags/taxi_pipeline.py"
  "tests/test_dag_integrity.py"
  "requirements.txt"
  "RUNBOOK.md"
  "ASSIGNMENT_REPORT.md"
  "AI_ASSIST.md"
)
missing=0
for f in "${required_files[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    pass "found $f"
  else
    fail "missing required file: $f"
    missing=$((missing + 1))
  fi
done
[[ "$missing" -eq 0 ]] && l1=20
score=$((score + l1))
pass "Level 1: required files ($l1/20 pts)"

# ── Level 2 (15 pts): DAG is implemented, not a stub ────────────────────────
l2=0
if [[ -f "$DAG" ]]; then
  if daggrep "raise NotImplementedError"; then
    fail "dags/taxi_pipeline.py: raise NotImplementedError still present — the DAG is not implemented"
  else
    l2=$((l2 + 10)); pass "dags/taxi_pipeline.py: no NotImplementedError stubs left"
  fi
  if daggrep "@dag" && daggrep "@task|BashOperator"; then
    l2=$((l2 + 5)); pass "dags/taxi_pipeline.py: defines a @dag with tasks"
  else
    fail "dags/taxi_pipeline.py: no @dag decorator with @task/BashOperator tasks found"
  fi
else
  fail "dags/taxi_pipeline.py missing — cannot check DAG content"
fi
score=$((score + l2))
pass "Level 2: DAG implemented ($l2/15 pts)"

# ── Level 3 (20 pts): three sequential tasks ────────────────────────────────
l3=0
if [[ -f "$DAG" ]]; then
  tasks_found=0
  for t in "ingest" "dbt_run" "dbt_test"; do
    daggrep "$t" && tasks_found=$((tasks_found + 1))
  done
  if [[ "$tasks_found" -eq 3 ]]; then
    l3=$((l3 + 10)); pass "dags/taxi_pipeline.py: ingest, dbt_run, and dbt_test all present"
  else
    fail "dags/taxi_pipeline.py: only $tasks_found/3 expected tasks found (ingest, dbt_run, dbt_test)"
  fi
  if daggrep ">>"; then
    l3=$((l3 + 10)); pass "dags/taxi_pipeline.py: tasks are chained with >>"
  else
    fail "dags/taxi_pipeline.py: no >> dependency chain found"
  fi
fi
score=$((score + l3))
pass "Level 3: sequential tasks ($l3/20 pts)"

# ── Level 4 (20 pts): dbt via uvx + retries ─────────────────────────────────
l4=0
if [[ -f "$DAG" ]]; then
  if daggrep "uvx"; then
    l4=$((l4 + 10)); pass "dags/taxi_pipeline.py: dbt runs through uvx (works on the image's Python 3.14)"
  else
    fail "dags/taxi_pipeline.py: no uvx found — plain 'dbt' crashes on Python 3.14 (see Chapter 4)"
  fi
  if daggrep "retries"; then
    l4=$((l4 + 10)); pass "dags/taxi_pipeline.py: retry behaviour configured (retries=...)"
  else
    fail "dags/taxi_pipeline.py: no 'retries' found in default_args"
  fi
fi
score=$((score + l4))
pass "Level 4: uvx dbt + retries ($l4/20 pts)"

# ── Level 5 (15 pts): parameterized on the logical date, not wall clock ─────
l5=0
if [[ -f "$DAG" ]]; then
  if daggrep "\{\{ ?ds ?\}\}" || daggrep "logical_date" || daggrep "get_current_context"; then
    l5=$((l5 + 10)); pass "dags/taxi_pipeline.py: partition derived from the logical date"
  else
    fail "dags/taxi_pipeline.py: no {{ ds }} / logical_date / get_current_context found — partition must come from the run date"
  fi
  if daggrep "datetime\.now\(|datetime\.today\("; then
    warn "dags/taxi_pipeline.py: datetime.now()/today() found — make sure the PARTITION comes from the logical date, not wall-clock time (Gotcha #1)"
  fi
  if daggrep "catchup ?= ?False"; then
    l5=$((l5 + 5)); pass "dags/taxi_pipeline.py: catchup=False set"
  else
    fail "dags/taxi_pipeline.py: catchup=False not found — required for safe normal operation"
  fi
fi
score=$((score + l5))
pass "Level 5: parameterized runs ($l5/15 pts)"

# ── Level 6 (10 pts): docs filled in ────────────────────────────────────────
# Count TODO markers in visible markdown only. Starter HTML comments like
# <!-- Replace every TODO ... --> must not fail a filled-in runbook/AI log.
todo_count() {
  local f="$1"
  python3 - "$f" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
print(len(re.findall(r"TODO", text)))
PY
}
l6=0
runbook="$REPO_ROOT/RUNBOOK.md"
ai="$REPO_ROOT/AI_ASSIST.md"
if file_has_content "$runbook"; then
  rb_chars=$(wc -c < "$runbook" | tr -d ' ')
  rb_todo=$(todo_count "$runbook")
  if [[ "$rb_chars" -ge 400 && "$rb_todo" -eq 0 ]]; then
    l6=$((l6 + 5)); pass "RUNBOOK.md: filled in (${rb_chars} chars, no TODO left)"
  else
    fail "RUNBOOK.md: still a template (${rb_chars} chars, ${rb_todo} TODO marker(s)) — fill in all four sections"
  fi
else
  fail "RUNBOOK.md: empty"
fi
if file_has_content "$ai"; then
  ai_chars=$(wc -c < "$ai" | tr -d ' ')
  ai_todo=$(todo_count "$ai")
  if [[ "$ai_chars" -ge 400 && "$ai_todo" -eq 0 ]]; then
    l6=$((l6 + 5)); pass "AI_ASSIST.md: filled in (${ai_chars} chars, no TODO left)"
  else
    fail "AI_ASSIST.md: still a template (${ai_chars} chars, ${ai_todo} TODO marker(s))"
  fi
else
  fail "AI_ASSIST.md: empty"
fi
score=$((score + l6))
pass "Level 6: documentation ($l6/10 pts)"

# ── Report ──────────────────────────────────────────────────────────────────
print_results "Week 12 Autograder — Orchestrated Pipeline"
write_score "$score" "$PASSING" "$SCRIPT_DIR/score.json"
echo ""
echo "Reminder: the shared-Airflow deploy, the green run, and backfill"
echo "idempotency are Target-tier items a teacher reviews by hand — a high"
echo "static score here is necessary but not sufficient for Target."
