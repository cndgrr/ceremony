#!/usr/bin/env bash
# Contract tests for bin/ceremony-upgrade (issue #561). Constructed CONSUMER
# trees (ceremony `uses:` lines spread across .github/, plus decoy content
# that names the old version) and a constructed SOURCE tree standing in for
# ceremony at the target tag — a docs-sync manifest, its docs, and a
# CHANGELOG.md whose release headings ARE the ladder the command reads.
#
# Every row that must not write is asserted over a WHOLE-TREE fingerprint
# taken before and after, never over the files the tool would have touched:
# the build this rejects is the one that rewrites the refs, then discovers
# the migration, then refuses (#561's third must-fail build), and a
# per-file assertion is exactly what it passes.
#
# The network is a `curl` stub first on PATH whose DEFAULT MODE REFUSES,
# modelled on test/docs-sync.test.sh's. That default is load-bearing rather
# than decorative: with the stub in place for the whole file, every --source
# row below is a proof that the --source path opens no socket at all.
#
# set -u, not -e: failing commands are behavior for the harness to inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

SCRIPT="$ROOT/bin/ceremony-upgrade"
DOCS_SYNC="$ROOT/actions/docs-sync/docs-sync.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ln -s "$ROOT" "$TMP/ceremony tool"
SCRIPT_WITH_SPACE="$TMP/ceremony tool/bin/ceremony-upgrade"

# --- the source tree ----------------------------------------------------------
#
# A fake ceremony: a small manifest (deliberately NOT the real vendored set —
# a command that hardcoded the doc list instead of calling docs-sync would
# pass against the real one) and a CHANGELOG.md carrying the real ladder.
#
# THE LADDER'S VERSIONS ARE THE REAL ONES on purpose, unlike the doc set: the
# migration table in bin/ceremony-upgrade names real tags, so the intervals
# these rows exercise have to be the real intervals. The bodies are stubs;
# only the headings are read.
#
# ONE FIXTURE IS AN EXCEPTION, AND IT IS DELIBERATE (#610). `stepable` stands
# on a FABRICATED rung in a SECOND source tree ($SRC_SYNTH, built below),
# because the shape it protects — a refusal that emits a runnable
# `SHORTER MOVE:` — needs a released tag strictly BETWEEN the pin and an
# unmechanised first crossing, and mechanising 0.7.0 left no real interval
# with one: of the two crossable rows still unmechanised, nothing is released
# below 0.2.0 but 0.1.0, and no released tag lies between 0.2.0 and 0.3.0.
# The shape is not retired, because it re-arms whenever a release adds an
# unmechanised row. Every OTHER fixture still uses the real intervals, and
# the fabricated rung is kept out of $SRC on purpose: that ladder is shared,
# and a rung inserted here would falsify `ancient`'s next-tag-on-the-ladder
# row and silently move the intervals every other fixture exercises.
SRC="$TMP/src"
mkdir -p "$SRC/docs"
printf 'AGENTS.md\nRULES.md\n' >"$SRC/docs/VENDORED.txt"
printf '# router v1\n' >"$SRC/AGENTS.md"
printf '# rules v1\n' >"$SRC/RULES.md"

LADDER_TAGS="0.7.8 0.7.7 0.7.6 0.7.5 0.7.4 0.7.3 0.7.2 0.7.1 0.7.0 0.6.3 0.6.2 0.6.1 0.6.0 0.5.0 0.4.1 0.4.0 0.3.0 0.2.0 0.1.0"
{
  printf '# Changelog\n\n## Unreleased\n\n- nothing yet\n\n'
  for t in $LADDER_TAGS; do
    printf '## %s — 2026-01-01\n\n### Changed\n\n- a release\n\n' "$t"
  done
} >"$SRC/CHANGELOG.md"

# The guide the applied step reads, and the ONE place its caller stub comes
# from. The block is EXTRACTED FROM THIS REPOSITORY'S OWN docs/CONSUMERS.md
# rather than written out here: a fixture carrying its own copy of a published
# block is the second source of truth the step exists to avoid, and it goes
# stale silently the first time the real block moves. So the source tree
# standing in for ceremony at a tag publishes exactly what ceremony publishes.
sweep_stub_from_guide() {
  awk '/^And the complete sweep caller, .labels-sweep\.yml. beside it/ { armed = 1; next }
       armed && /^```yaml$/ { inblock = 1; next }
       inblock && /^```$/ { exit }
       inblock' "$ROOT/docs/CONSUMERS.md"
}
write_src_guide() { # $1 = source dir
  mkdir -p "$1/docs"
  {
    cat <<'MD'
# Consumers

And the complete sweep caller, `labels-sweep.yml` beside it — the hourly
cron lives HERE since #209, not on the labels caller:

```yaml
MD
    sweep_stub_from_guide
    printf '```\n'
  } >"$1/docs/CONSUMERS.md"
}
write_src_guide "$SRC"

# --- the SECOND source tree, with one fabricated rung -------------------------
#
# Built exactly like $SRC and differing from it in ONE thing: its ladder
# carries a rung, 0.2.5, that ceremony never released. It exists so `stepable`
# can keep testing a refusal that emits a RUNNABLE shorter move after
# mechanising 0.7.0 left that shape no real interval (#610) — see the
# exception on the convention above.
#
# WHY THE RUNG SITS WHERE IT DOES. The shape needs a released tag strictly
# between the pin and an unmechanised first crossing. 0.3.0 is a real,
# still-unmechanised row, and 0.2.0 and 0.3.0 are consecutive on the real
# ladder, so 0.2.5 is the one position that creates the interval: pinned at
# 0.2.0 and asked for 0.4.0, the first CROSSED migration row is 0.3.0 and the
# longest move that crosses none is 0.2.5. The fabricated tag is deliberately
# NOT a migration row itself — it is a released rung and nothing more, which
# is what makes it a legal destination.
#
# THIS LADDER IS NOT $SRC's, and must never be merged into it: $SRC is shared
# by every other fixture, and a rung added there would falsify `ancient`'s
# "the first crossed tag 0.2.0 is the next tag on the ladder" row and silently
# change the intervals the whole suite exercises.
SRC_SYNTH="$TMP/src-synth"
mkdir -p "$SRC_SYNTH/docs"
cp "$SRC/docs/VENDORED.txt" "$SRC_SYNTH/docs/VENDORED.txt"
cp "$SRC/AGENTS.md" "$SRC_SYNTH/AGENTS.md"
cp "$SRC/RULES.md" "$SRC_SYNTH/RULES.md"
SYNTH_LADDER_TAGS="0.7.8 0.7.7 0.7.6 0.7.5 0.7.4 0.7.3 0.7.2 0.7.1 0.7.0 0.6.3 0.6.2 0.6.1 0.6.0 0.5.0 0.4.1 0.4.0 0.3.0 0.2.5 0.2.0 0.1.0"
{
  printf '# Changelog\n\n## Unreleased\n\n- nothing yet\n\n'
  for t in $SYNTH_LADDER_TAGS; do
    printf '## %s — 2026-01-01\n\n### Changed\n\n- a release\n\n' "$t"
  done
} >"$SRC_SYNTH/CHANGELOG.md"
write_src_guide "$SRC_SYNTH"

# --- fixture builders ---------------------------------------------------------

# consumer <name> <ref> — a consumer tree pinned at <ref> in FIVE places
# across four files, including a nested composite action, so `find`'s
# recursion and the all-together rule are both exercised. It also carries
# three things that must NOT move:
#
#   * a commented-out pin line (docs/CONSUMERS.md snippets get pasted into
#     consumer workflows, and docs-sync excludes comments for the same
#     reason — where the two disagree about what a pin is, the mirror check
#     and the bump disagree about what the tree is pinned to);
#   * third-party `uses:` lines at their own refs;
#   * DECOYS — a README naming the version in prose and a CHANGELOG.md with
#     a `## <ref>` heading of the consumer's own. These are what `sed
#     's/<old>/<new>/g'` corrupts silently, and the byte assertions below
#     are what catch it.
consumer() {
  local dir="$TMP/$1" ref="$2"
  rm -rf "$dir"
  mkdir -p "$dir/.github/workflows" "$dir/.github/actions/vouch"
  cat >"$dir/.github/workflows/release.yml" <<EOF
name: release
on:
  push:
    branches: [main]
jobs:
  release:
    uses: heavy-duty/ceremony/.github/workflows/release.yml@$ref
    secrets: inherit
EOF
  cat >"$dir/.github/workflows/labels.yml" <<EOF
name: labels
on: [pull_request_target]
jobs:
  trigger:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
  # a documentation snippet someone pasted; a comment is not a pin
  #  uses: heavy-duty/ceremony/.github/workflows/labels-sweep.yml@0.0.1
EOF
  cat >"$dir/.github/workflows/ci.yml" <<EOF
name: ci
on: [pull_request]
jobs:
  guards:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: heavy-duty/ceremony/actions/docs-sync@$ref
      - uses: heavy-duty/ceremony/actions/refs-not-closing@$ref  # keep in step with the pin
EOF
  cat >"$dir/.github/actions/vouch/action.yml" <<EOF
name: vouch
runs:
  using: composite
  steps:
    - uses: heavy-duty/ceremony/actions/runner-isolated@$ref
      shell: bash
EOF
  # The decoys.
  printf '# consumer\n\nPinned to ceremony %s. See the %s notes.\n' "$ref" "$ref" >"$dir/README.md"
  printf '# Changelog\n\n## %s — 2026-02-02\n\n- our own release, nothing to do with ceremony\n' "$ref" >"$dir/CHANGELOG.md"
}

# The number of real pins consumer() writes. Named once: a row asserting "5"
# in prose while the builder writes 6 is a fixture that grades itself.
PIN_COUNT=5

# fingerprint <dir> — every regular file's path and content hash, sorted.
# Paths as well as hashes, so an ADDED or DELETED file moves the fingerprint
# too; a content-only digest would call a refusal that created .ceremony/
# byte-identical.
fingerprint() {
  (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r p; do
    printf '%s  %s\n' "$(sha256sum <"$p" | cut -d' ' -f1)" "$p"
  done)
}

# unchanged <desc> <dir> <cmd...> — run the command, then assert the tree is
# byte-identical to what it was before. The assertion is the WHOLE tree.
unchanged() {
  local desc="$1" dir="$2"
  shift 2
  local before after
  before="$(fingerprint "$dir")"
  "$@" >/dev/null 2>&1
  after="$(fingerprint "$dir")"
  if [ "$before" = "$after" ]; then
    echo "ok: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc — the tree changed:"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

# capture_run / replay_run — a write-capable command happens once, while any
# number of rows may inspect the one output and its one exit status.
capture_run() { # <outfile> <cmd...>
  local out="$1"
  shift
  "$@" >"$out" 2>&1
  printf '%s\n' "$?" >"$out.rc"
}
replay_run() { # <outfile>
  local out="$1"
  cat "$out"
  return "$(cat "$out.rc")"
}

# in_consumer <name> <args...> — run the command from inside a consumer tree,
# the way an operator runs it: from the root of the checkout.
in_consumer() {
  local dir="$1"
  shift
  (cd "$TMP/$dir" && bash "$SCRIPT" "$@")
}

in_consumer_with_script() {
  local dir="$1" script="$2"
  shift 2
  (cd "$TMP/$dir" && bash "$script" "$@")
}

in_consumer_docs_sync() {
  local dir="$1"
  shift
  (cd "$TMP/$dir" && bash "$DOCS_SYNC" "$@")
}

# refs <name> — every ceremony ref in the tree, one per line, so a row can
# assert that ALL of them moved (or that none did).
refs() {
  grep -rhoE 'heavy-duty/ceremony[^@[:space:]]*@[A-Za-z0-9._-]+' "$TMP/$1/.github" |
    sed -E 's/^.*@//' | LC_ALL=C sort | uniq -c | sed 's/^ *//'
}

# --- the curl stub ------------------------------------------------------------
#
# Default mode refuses, which is what makes every --source row a proof that
# the --source path opens no socket (test/docs-sync.test.sh, #393).
#
# It also LOGS THE URL of every call, which is the only way to grade one thing
# --source cannot express: with a local source tree standing in for ceremony,
# "the guide at the crossed tag" and "the guide at the target" are the same
# bytes, so a build that read the wrong ref passes every --source row. On the
# fetch path the two are different URLs, and the log is what says which one
# was asked for.
mkdir -p "$TMP/stub"
cat >"$TMP/stub/curl" <<'STUB'
#!/usr/bin/env bash
out=""
url=""
prev=""
for arg in "$@"; do
  [ "$prev" = "-o" ] && out="$arg"
  case "$arg" in https://*) url="$arg" ;; esac
  prev="$arg"
done
[ -z "${CURL_STUB_LOG:-}" ] || printf '%s\n' "$url" >>"$CURL_STUB_LOG"
case "${CURL_STUB:-none}" in
  ok)
    case "$url" in
      *docs/CONSUMERS.md) cp "${CURL_STUB_GUIDE:-$CURL_STUB_BODY}" "$out" ;;
      *) cp "$CURL_STUB_BODY" "$out" ;;
    esac
    printf '200'
    ;;
  404)
    printf '404'
    exit 22
    ;;
  503)
    printf '503'
    exit 22
    ;;
  *)
    echo "curl stub: refusing — this code path must not reach the network (curl $*)" >&2
    printf '000'
    exit 99
    ;;
esac
STUB
chmod +x "$TMP/stub/curl"
PATH="$TMP/stub:$PATH"
export PATH

# ============================================================================
# The happy path — one adjacent move
# ============================================================================

consumer happy 0.7.6

check "--check reports the move and every pinned file" 0 "0.7.6 -> 0.7.7, $PIN_COUNT ceremony ref(s)" \
  in_consumer happy --check --source "$SRC" 0.7.7
check "--check names the release caller" 0 ".github/workflows/release.yml  @0.7.6" \
  in_consumer happy --check --source "$SRC" 0.7.7
check "--check names the nested composite action" 0 ".github/actions/vouch/action.yml  @0.7.6" \
  in_consumer happy --check --source "$SRC" 0.7.7
check "--check says it wrote nothing" 0 "--check changes nothing" \
  in_consumer happy --check --source "$SRC" 0.7.7
unchanged "--check leaves the whole tree byte-identical" "$TMP/happy" \
  in_consumer happy --check --source "$SRC" 0.7.7

# check is the DEFAULT, exactly as in docs-sync — a row of its own, because
# "the default is check" is the difference between a preview and a rewrite.
check "no mode flag defaults to --check" 0 "--check changes nothing" \
  in_consumer happy --source "$SRC" 0.7.7
unchanged "the default mode leaves the tree byte-identical" "$TMP/happy" \
  in_consumer happy --source "$SRC" 0.7.7

check "--check refuses to look like it moved anything" 0 "" \
  in_consumer happy --source "$SRC" 0.7.7
check_absent "--check never claims to have rewritten a ref" 0 "rewrote" \
  in_consumer happy --source "$SRC" 0.7.7

# The plan's own file count. It used to be the number of YAML files SCANNED,
# not the number carrying a pin — a plan line that says "N ref(s) in M
# file(s)" where M is neither. This fixture has 5 refs in 4 files under 6
# YAML files, so all three numbers differ and the row can only pass for the
# right reason.
check "--check announces the refs and the files that carry them" 0 \
  "$PIN_COUNT ceremony ref(s) in 4 file(s) under .github/" \
  in_consumer happy --source "$SRC" 0.7.7

check "--fix rewrites the refs" 0 "rewrote $PIN_COUNT ceremony ref(s) in 4 file(s) to @0.7.7" \
  in_consumer happy --fix --source "$SRC" 0.7.7
# Its own fixture: `happy` has already moved by now, so this row would take
# the "already at" branch and pass while asserting nothing about a rewrite.
consumer verified 0.7.6
check "--fix verifies the tree against the plan before it hands off" 0 \
  "verified the tree against the plan" \
  in_consumer verified --fix --source "$SRC" 0.7.7
check "all $PIN_COUNT refs are at the target and none is left behind" 0 "$PIN_COUNT 0.7.7" \
  refs happy
check_absent "no ref is left at the old tag" 0 "0.7.6" \
  refs happy
check "the mirror is current after --fix, so docs-sync --check passes" 0 "is an exact mirror" \
  in_consumer_docs_sync happy --check --source "$SRC"

# The sed build. These two decoys are what a tree-wide substitution destroys,
# and nothing else in the suite would notice.
check "the consumer's README still names its own old version" 0 "Pinned to ceremony 0.7.6" \
  cat "$TMP/happy/README.md"
check "the consumer's own CHANGELOG heading is untouched" 0 "## 0.7.6 — 2026-02-02" \
  cat "$TMP/happy/CHANGELOG.md"
# Third-party refs and the commented-out pin are not this command's business.
check "a third-party uses: keeps its own ref" 0 "actions/checkout@v4" \
  cat "$TMP/happy/.github/workflows/ci.yml"
check "a commented-out pin line is not a pin and does not move" 0 "labels-sweep.yml@0.0.1" \
  cat "$TMP/happy/.github/workflows/labels.yml"
check "a trailing comment on a pin line survives the rewrite" 0 "refs-not-closing@0.7.7  # keep in step with the pin" \
  cat "$TMP/happy/.github/workflows/ci.yml"

# --- idempotence --------------------------------------------------------------

check "a second --fix reports nothing to do" 0 "nothing to do — the pin was already at 0.7.7" \
  in_consumer happy --fix --source "$SRC" 0.7.7
unchanged "a second --fix leaves the tree byte-identical to the first's" "$TMP/happy" \
  in_consumer happy --fix --source "$SRC" 0.7.7
check "--check at the current pin says so and stops" 0 "already at 0.7.7" \
  in_consumer happy --check --source "$SRC" 0.7.7

# ============================================================================
# All or none
# ============================================================================

consumer mixed 0.7.6
# One file dragged forward by hand — the shape a partial bump leaves behind.
sed -i 's|actions/docs-sync@0.7.6|actions/docs-sync@0.7.7|' "$TMP/mixed/.github/workflows/ci.yml"

check "a tree with two ceremony refs is refused" 1 "not all at one ref" \
  in_consumer mixed --check --source "$SRC" 0.7.7
check "the refusal names the differing file" 1 ".github/workflows/ci.yml  @0.7.7" \
  in_consumer mixed --check --source "$SRC" 0.7.7
check "the refusal reports every ref it found" 1 "Every ceremony ref found ($PIN_COUNT" \
  in_consumer mixed --check --source "$SRC" 0.7.7
unchanged "the mixed-ref refusal leaves the tree byte-identical (--check)" "$TMP/mixed" \
  in_consumer mixed --check --source "$SRC" 0.7.7
unchanged "the mixed-ref refusal leaves the tree byte-identical (--fix)" "$TMP/mixed" \
  in_consumer mixed --fix --source "$SRC" 0.7.7

# ============================================================================
# The refusal — the one to get right
# ============================================================================

consumer ancient 0.1.0
runnable_step_lines() {
  local name="$1" target="$2"
  in_consumer "$name" --check --source "$SRC" "$target" 2>&1 |
    sed -n '/^  SHORTER MOVE:/p'
}
in_consumer_with_override() {
  local name="$1"
  (
    cd "$TMP/$name" || return
    CEREMONY_UPGRADE_MIGRATIONS_DONE=1 \
      bash "$SCRIPT" --check --source "$SRC" 0.3.0
  )
}

check "a move crossing migrations is refused" 1 "crosses 6 migration(s)" \
  in_consumer ancient --check --source "$SRC" 0.7.7
check "every migration refusal names the hand-only boundary" 1 "THE CROSSING IS HAND-ONLY" \
  in_consumer ancient --check --source "$SRC" 0.7.7
check "the hand-only boundary says the pin, not the tree, defines the crossed set" 1 \
  "read from the pin on the ladder, never from the tree" \
  in_consumer ancient --check --source "$SRC" 0.7.7
check_absent "the dead then-re-run remedy is absent from migration refusals" 1 "then re-run" \
  in_consumer ancient --check --source "$SRC" 0.7.7
unchanged "the migration refusal leaves the WHOLE tree byte-identical (--check)" "$TMP/ancient" \
  in_consumer ancient --check --source "$SRC" 0.7.7
# The partial-write build: refs rewritten, migration discovered, then refuse.
# It passes every message assertion above and only this row rejects it.
unchanged "the migration refusal leaves the WHOLE tree byte-identical (--fix)" "$TMP/ancient" \
  in_consumer ancient --fix --source "$SRC" 0.7.7
check "not one ref moved under the refusal" 0 "$PIN_COUNT 0.1.0" \
  refs ancient

# Every crossed tag, IN ORDER. The order is the assertion: a reader working
# through a hand migration does them oldest first, and a set printed in hash
# order is a list of things to do in an order that will not work.
crossed_tags() {
  in_consumer ancient --check --source "$SRC" 0.7.7 2>&1 |
    sed -nE 's/^  ([0-9]+\.[0-9]+\.[0-9]+) — docs.*/\1/p' | tr '\n' ' '
}
check "every crossed tag is named, in ladder order" 0 "0.2.0 0.3.0 0.4.1 0.5.0 0.6.0 0.7.0 " \
  crossed_tags
# 0.1.0 is a table row and the consumer is standing ON it: the half-open
# interval is what keeps it out of the list, and this row is what would
# notice if the interval ever closed at the current pin.
check_absent "the tag the consumer already stands on is not listed" 0 "0.1.0" \
  crossed_tags

# Each with its section, so the reader has somewhere to go.
check "0.2.0 carries its CONSUMERS.md section" 1 '0.2.0 — docs/CONSUMERS.md § "Bootstrap a new repo"' \
  in_consumer ancient --check --source "$SRC" 0.7.7
check "0.5.0 carries its CONSUMERS.md section" 1 '0.5.0 — docs/CONSUMERS.md § "Labels automation"' \
  in_consumer ancient --check --source "$SRC" 0.7.7
check "0.6.0 carries its CONSUMERS.md section" 1 '0.6.0 — docs/CONSUMERS.md § "Doctrine mirror"' \
  in_consumer ancient --check --source "$SRC" 0.7.7

# The refusal says what it WOULD have done, so the reader can tell it is
# about the migrations and not about the refs.
check "the refusal reports the ref count it would have rewritten" 1 "rewrite $PIN_COUNT ceremony ref(s) from @0.1.0 to @0.7.7" \
  in_consumer ancient --check --source "$SRC" 0.7.7
check "the refusal lists the files it would have rewritten" 1 ".github/workflows/labels.yml  @0.1.0" \
  in_consumer ancient --check --source "$SRC" 0.7.7
check "the refusal says the tree is unchanged" 1 "THE TREE IS UNCHANGED" \
  in_consumer ancient --check --source "$SRC" 0.7.7
check "the oldest pin has no shorter move before its first crossed tag" 1 \
  "NO SHORTER MOVE: the first crossed tag 0.2.0 is the next tag on the ladder" \
  in_consumer ancient --check --source "$SRC" 0.7.7
check_absent "a no-shorter-move refusal carries no runnable step line" 0 "SHORTER MOVE:" \
  runnable_step_lines ancient 0.7.7

# A real shorter move exists only BELOW the first crossed tag. Extract the
# suggestion from the refusal and execute that exact tag: hard-coding the
# second invocation would test our expectation twice while never proving the
# command's own line is performable (#588).
#
# THIS IS THE ONE FIXTURE ON THE FABRICATED LADDER (#610). It used to run
# 0.6.1 -> 0.7.8 with 0.7.0 as its first crossing; mechanising 0.7.0 left no
# real interval expressing the shape, so it moved to $SRC_SYNTH rather than
# being dropped or re-based. Its first crossed tag is still a REAL
# unmechanised row (0.3.0) — only the rung the remedy names is fabricated,
# which is the whole point: the emitted line must be runnable, and a
# destination that does not exist on the ladder could not be run.
consumer stepable 0.2.0
suggested_step() {
  suggested_step_line | sed -nE 's/.* ([0-9]+\.[0-9]+\.[0-9]+)$/\1/p'
}
suggested_step_line() {
  in_consumer_with_script stepable "$SCRIPT_WITH_SPACE" \
    --check --source "$SRC_SYNTH" 0.4.0 2>&1 | sed -n 's/^  SHORTER MOVE: //p'
}
run_suggested_step() {
  local suggested_line
  suggested_line="$(suggested_step_line)"
  [ -n "$suggested_line" ] || return 97
  (cd "$TMP/stepable" && bash -c "$suggested_line")
}
check "the first crossed tag is named on a stepable move" 1 "FIRST CROSSED TAG: 0.3.0" \
  in_consumer stepable --check --source "$SRC_SYNTH" 0.4.0
check "the shorter move line names the rung below the first crossing" 0 "0.2.5" \
  suggested_step
check "the extracted shorter move is accepted by the command" 0 \
  "no migration between 0.2.0 and 0.2.5" run_suggested_step
# ...and the row above cannot tell WHERE that line came from. It grades the
# command's output, so a runner that hard-codes 0.2.5 produces the same
# output and keeps it green — which is the mutation #610 B10 names as the
# thing that must red ("hard-coding stepable's second invocation rather than
# extracting the emitted line"). "The line the command emitted is the line
# that ran" is a property of the RUNNER, so it is read off the runner's body.
# Bounded by the function's own braces: replacing it with a direct
# invocation removes the opening line, the extract goes empty, and the two
# positive rows red rather than passing on nothing.
suggested_step_runner() {
  sed -n '/^run_suggested_step() {$/,/^}$/p' "$ROOT/test/ceremony-upgrade.test.sh"
}
check "the stepable remedy runner captures the line the command emitted" 0 \
  "suggested_line=\"\$(suggested_step_line)\"" suggested_step_runner
check "the stepable remedy runner executes the captured line" 0 \
  "bash -c \"\$suggested_line\"" suggested_step_runner
check_absent "the stepable remedy runner names no destination of its own" 0 \
  "0.2.5" suggested_step_runner
check_absent "a stepable refusal does not claim there is no shorter move" 1 "NO SHORTER MOVE:" \
  in_consumer stepable --check --source "$SRC_SYNTH" 0.4.0
check_absent "the stepable refusal contains no dead then-re-run remedy" 1 "then re-run" \
  in_consumer stepable --check --source "$SRC_SYNTH" 0.4.0
unchanged "the stepable refusal leaves the WHOLE tree byte-identical (--check)" "$TMP/stepable" \
  in_consumer stepable --check --source "$SRC_SYNTH" 0.4.0
unchanged "the stepable refusal leaves the WHOLE tree byte-identical (--fix)" "$TMP/stepable" \
  in_consumer stepable --fix --source "$SRC_SYNTH" 0.4.0
# B11's guard, asserted rather than assumed: the fabricated rung lives in the
# second tree ONLY. A rung leaking into $SRC would leave the suite green while
# silently moving every other fixture's intervals, so the ladder $SRC actually
# published is read back here.
check_absent "the shared source ladder carries no fabricated rung" 1 "0.2.5" \
  grep '^## 0\.2\.5 ' "$SRC/CHANGELOG.md"
check "the fabricated rung is published by the synthetic source" 0 "## 0.2.5" \
  grep '^## 0\.2\.5 ' "$SRC_SYNTH/CHANGELOG.md"

# The first crossed tag is the next rung. Falling back to the current tag
# would emit a command that exits zero while doing nothing, so this branch
# must carry only the explicit wall and never a runnable step line (#588).
#
# RE-BASED FROM 0.6.3 -> 0.7.0 WHEN 0.7.0 GAINED ITS STEP (#610). The shape
# needs the target to BE the first crossed tag and the next ladder rung after
# the pin, which survives on a real interval: 0.2.0 and 0.3.0 are consecutive
# and 0.3.0 stays unmechanised. NOT 0.1.0 -> 0.2.0, and the reason is recorded
# so it is not re-litigated: 0.2.0 is the likeliest next mint on this ladder,
# so parking here would cost this fixture a second re-base one issue later,
# and that crossing is the one `ancient` already keys on — two fixtures dying
# on one future mint is worse than one each. `in_consumer_with_override`'s
# hard-coded target moved with it, above; leaving it at 0.7.0 would have kept
# that row green while it tested a mechanised crossing instead of a hand-only
# one.
consumer atwall 0.2.0
check "the at-wall refusal names its first crossed tag" 1 "FIRST CROSSED TAG: 0.3.0" \
  in_consumer atwall --check --source "$SRC" 0.3.0
check "the at-wall refusal says no shorter move exists" 1 \
  "NO SHORTER MOVE: the first crossed tag 0.3.0 is the next tag on the ladder" \
  in_consumer atwall --check --source "$SRC" 0.3.0
check_absent "the at-wall refusal carries no runnable step line" 0 "SHORTER MOVE:" \
  runnable_step_lines atwall 0.3.0
check_absent "the at-wall refusal contains no dead then-re-run remedy" 1 "then re-run" \
  in_consumer atwall --check --source "$SRC" 0.3.0
unchanged "the at-wall refusal leaves the WHOLE tree byte-identical (--check)" "$TMP/atwall" \
  in_consumer atwall --check --source "$SRC" 0.3.0
unchanged "the at-wall refusal leaves the WHOLE tree byte-identical (--fix)" "$TMP/atwall" \
  in_consumer atwall --fix --source "$SRC" 0.3.0

# --- 0.4.1 in particular ------------------------------------------------------
#
# The destructive one. A generic "a migration is owed" does not discharge it,
# so each of the four acts is its own row: a message that named the split but
# forgot the cron MOVE is how a consumer ends up double-sweeping.
consumer split 0.4.0
check "crossing 0.4.1 names the two-caller split" 1 "TWO-CALLER SPLIT" \
  in_consumer split --check --source "$SRC" 0.5.0
check "crossing 0.4.1 names the labels-sweep.yml addition" 1 "labels-sweep.yml" \
  in_consumer split --check --source "$SRC" 0.5.0
check "crossing 0.4.1 says the cron MOVES, never copies" 1 "move, never copy" \
  in_consumer split --check --source "$SRC" 0.5.0
check "crossing 0.4.1 names double sweeps as the cost of copying" 1 "DOUBLE SWEEPS" \
  in_consumer split --check --source "$SRC" 0.5.0
check "crossing 0.4.1 names the actions: write grant" 1 "grant actions: write" \
  in_consumer split --check --source "$SRC" 0.5.0
check "crossing 0.4.1 names what breaks without it" 1 "RED ON EVERY PR AND ISSUE EVENT" \
  in_consumer split --check --source "$SRC" 0.5.0

# The interval is HALF-OPEN at the current pin: standing ON 0.4.1 and moving
# up must not re-fire the migration this consumer has already done. A closed
# interval passes every row above and refuses every consumer forever.
#
# THE EXIT CODE ON THESE TWO MOVED 1 -> 0 WHEN 0.5.0 GAINED A STEP (#600), and
# nothing else about them did: the crossed count is still one and it is still
# 0.5.0's, the split is still not re-listed, and both are still read off a
# half-open interval. What changed is what happens to the one tag inside it —
# it is performed now rather than refused — so the row that used to be graded
# by a refusal's exit code is graded by a completion's.
consumer onsplit 0.4.1
check "the interval is half-open at the current pin" 0 "crosses 1 migration(s)" \
  in_consumer onsplit --check --source "$SRC" 0.5.0
check_absent "0.4.1 is not re-listed when the consumer already stands on it" 0 "TWO-CALLER SPLIT" \
  in_consumer onsplit --check --source "$SRC" 0.5.0
# ...and the one tag in that interval is the one the pin has NOT crossed. A
# closed interval would put 0.4.1 in the slice too, and 0.4.1 has a step of its
# own — so the failure this row now guards against is a re-run of the split on
# a consumer that already did it, which no exit code alone would show.
check "the tag inside that interval is 0.5.0 and no other" 0 \
  "0.5.0 is an APPLIED STEP, so this run performs 0.4.1 -> 0.5.0 and stops there" \
  in_consumer onsplit --check --source "$SRC" 0.5.0

# ...and CLOSED at the target: arriving AT a migration tag is crossing it.
consumer arrive 0.4.0
check "arriving at a migration tag fires it" 1 "TWO-CALLER SPLIT" \
  in_consumer arrive --check --source "$SRC" 0.4.1
check "arriving at the next migration rung has no shorter move" 1 \
  "NO SHORTER MOVE: the first crossed tag 0.4.1 is the next tag on the ladder" \
  in_consumer arrive --check --source "$SRC" 0.4.1
check_absent "the next-rung migration refusal carries no step line" 0 "SHORTER MOVE:" \
  runnable_step_lines arrive 0.4.1

# A move that crosses nothing is not refused, and this is the row that keeps
# the table from being "refuse everything".
consumer clean 0.7.1
check "a move crossing no migration is allowed" 0 "no migration between 0.7.1 and 0.7.6" \
  in_consumer clean --check --source "$SRC" 0.7.6

# ============================================================================
# Four faults, four messages
# ============================================================================
#
# Each row asserts its own text AND the absence of the other three, because a
# branch that prints every diagnostic on every fault satisfies a
# positive-only suite while sending its reader to audit four things for one
# fault (#393).

# --- fault 1: no pin ----------------------------------------------------------
mkdir -p "$TMP/bare/.github/workflows"
printf 'name: ci\non: [push]\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n' \
  >"$TMP/bare/.github/workflows/ci.yml"
check "a tree with no pin is refused" 1 "FAULT — no ceremony pin" \
  in_consumer bare --check --source "$SRC" 0.7.7
check "the no-pin message names bootstrap as a later child of #560" 1 "later child of #560" \
  in_consumer bare --check --source "$SRC" 0.7.7
check "the no-pin message says the tool is not broken" 1 "not a sign that this command is broken" \
  in_consumer bare --check --source "$SRC" 0.7.7
check_absent "the no-pin message is not the not-a-released-tag message" 1 "is not a released tag" \
  in_consumer bare --check --source "$SRC" 0.7.7
check_absent "the no-pin message is not the crossed-migration message" 1 "crosses" \
  in_consumer bare --check --source "$SRC" 0.7.7
unchanged "the no-pin refusal writes nothing" "$TMP/bare" \
  in_consumer bare --fix --source "$SRC" 0.7.7

# --- fault 2: the current ref is not a released tag ---------------------------
consumer onbranch main
check "a branch pin is refused" 1 "FAULT — the current pin 'main' is not a released tag" \
  in_consumer onbranch --check --source "$SRC" 0.7.7
check "the branch-pin message says why it cannot be graded" 1 "cannot be placed on it" \
  in_consumer onbranch --check --source "$SRC" 0.7.7
check_absent "the branch-pin message is not the no-pin message" 1 "no ceremony pin" \
  in_consumer onbranch --check --source "$SRC" 0.7.7
check_absent "the branch-pin message is not the target-missing message" 1 "does not exist upstream" \
  in_consumer onbranch --check --source "$SRC" 0.7.7
unchanged "the branch-pin refusal writes nothing" "$TMP/onbranch" \
  in_consumer onbranch --fix --source "$SRC" 0.7.7

consumer onsha 8f1c2d3e4b5a69708192a3b4c5d6e7f809a1b2c3
check "a commit-SHA pin is refused as unplaceable too" 1 "is not a released tag" \
  in_consumer onsha --check --source "$SRC" 0.7.7

# --- fault 3: the target tag does not exist -----------------------------------
check "an unreleased target tag is refused" 1 "FAULT — the target tag '0.9.9' does not exist upstream" \
  in_consumer happy --check --source "$SRC" 0.9.9
check_absent "the target-missing message is not the current-pin message" 1 "the current pin" \
  in_consumer happy --check --source "$SRC" 0.9.9
unchanged "the target-missing refusal writes nothing" "$TMP/happy" \
  in_consumer happy --fix --source "$SRC" 0.9.9

# A branch is not a target either — same fault, and it must say so rather
# than grading a move onto something with no place on the ladder.
check "a branch as the target is refused" 1 "does not exist upstream" \
  in_consumer happy --check --source "$SRC" main

# --- fault 4: the crossed migration -------------------------------------------
# (asserted in full above; this row is the fourth message's absence check)
check_absent "the crossed-migration message is not the no-pin message" 1 "no ceremony pin" \
  in_consumer ancient --check --source "$SRC" 0.7.7

# ============================================================================
# The fifth refusal — a downgrade (beyond #561's four, disclosed on the PR)
# ============================================================================

check "a backwards move is refused" 1 "FAULT — that is a DOWNGRADE" \
  in_consumer happy --check --source "$SRC" 0.5.0
check "the downgrade message says why there is no hand procedure" 1 "written forwards" \
  in_consumer happy --check --source "$SRC" 0.5.0
unchanged "the downgrade refusal writes nothing" "$TMP/happy" \
  in_consumer happy --fix --source "$SRC" 0.5.0

# ============================================================================
# Argument handling
# ============================================================================

check "no target tag is a usage error" 1 "no target tag" \
  in_consumer happy --check --source "$SRC"
check "two target tags are refused" 1 "two target tags given" \
  in_consumer happy --check --source "$SRC" 0.7.6 0.7.7
check "an unknown flag is refused" 1 "unknown argument" \
  in_consumer happy --check --source "$SRC" --wat 0.7.7
check "--force is not an accepted override" 1 "unknown argument" \
  in_consumer happy --check --source "$SRC" --force 0.7.7
check_absent "the usage text advertises no override" 1 "--force" \
  in_consumer happy --check --source "$SRC"
check "an override-shaped environment variable cannot bypass fault 6" 1 \
  "THE CROSSING IS HAND-ONLY" in_consumer_with_override atwall
check "--source with no directory is refused" 1 "--source needs a directory" \
  in_consumer happy --check --source
check "a missing --source directory is refused" 1 "no such directory" \
  in_consumer happy --check --source "$TMP/nope" 0.7.7
# A ref is bounded to git-ref characters BEFORE it is written into a workflow
# file: the substitution lands in a file, and a metacharacter there is a
# rewrite nobody wrote.
check "a target with shell metacharacters is refused before anything is read" 1 "refusing target" \
  in_consumer happy --check --source "$SRC" '0.7.7 & rm -rf /'
check "a target starting with a hyphen is not read as a flag" 1 "unknown argument" \
  in_consumer happy --check --source "$SRC" -0.7.7

# ============================================================================
# The tree is only touched through docs-sync, and only where it should be
# ============================================================================

# A symlinked workflow carrying a pin is REFUSED, not silently skipped: a
# `find -type f` enumeration walks straight past it, leaving a ref behind and
# turning "all or none" into a claim the tool did not check.
consumer linked 0.7.6
mv "$TMP/linked/.github/workflows/ci.yml" "$TMP/linked/.github/workflows/ci-real.yml"
ln -s ci-real.yml "$TMP/linked/.github/workflows/ci.yml"
check "a symlinked file carrying a pin is refused" 1 "is a symlink and carries a ceremony pin" \
  in_consumer linked --check --source "$SRC" 0.7.7

# ============================================================================
# The fetch path — the ladder without --source
# ============================================================================
#
# Every row above ran with the refusing curl stub first on PATH and passed,
# which is the proof that --source opens no socket. These rows drive the
# other path deliberately.

CURL_STUB_BODY="$SRC/CHANGELOG.md"
export CURL_STUB_BODY

consumer happyfetch 0.7.6
consumer ancientfetch 0.1.0
run_fetch() {
  local dir="$1" stub="$2"
  shift 2
  (cd "$TMP/$dir" && CURL_STUB="$stub" bash "$SCRIPT" "$@")
}

check "the fetched ladder grades an ordinary move" 0 "0.7.6 -> 0.7.7" \
  run_fetch happyfetch ok --check 0.7.7
check "the fetched ladder refuses a crossed migration too" 1 "crosses 6 migration(s)" \
  run_fetch ancientfetch ok --check 0.7.7
unchanged "a refusal on the fetch path writes nothing either" "$TMP/ancientfetch" \
  run_fetch ancientfetch ok --fix 0.7.7
check "a 404 is the target-missing fault, named as such" 1 "does not exist upstream" \
  run_fetch happyfetch 404 --check 0.9.9
check "a 5xx is transient and says the tag is not in doubt" 1 "transient" \
  run_fetch happyfetch 503 --check 0.7.7
check "the transient 5xx remedy still says re-run" 1 "re-run" \
  run_fetch happyfetch 503 --check 0.7.7
check_absent "a 5xx does not accuse the tag" 1 "does not exist upstream" \
  run_fetch happyfetch 503 --check 0.7.7
unchanged "a failed fetch writes nothing" "$TMP/happyfetch" \
  run_fetch happyfetch 503 --fix 0.7.7
# The stub's default mode refuses and exits 99, so this row is the proof that
# the assertion behind every --source row above is a real one: take --source
# away and the network is genuinely what the command reaches for.
check "without --source the command really does reach for the network" 1 "" \
  run_fetch happyfetch none --check 0.7.7

# The guide and executable are one consumer-facing contract. Keep this on
# the single refusal-table row so an unrelated legitimate "then re-run"
# elsewhere in the guide cannot satisfy or fail the repair (#588).
migration_refusal_guide_row() {
  grep -F '| **the move crosses a migration**' "$ROOT/docs/CONSUMERS.md"
}
check "the guide says a migration crossing is hand-only" 0 "crossing is hand-only" \
  migration_refusal_guide_row
check "the guide includes the ref move in the hand crossing" 0 \
  "move the ceremony refs to that tag in the same commit" migration_refusal_guide_row
check "the guide bounds a shorter move below the first crossing" 0 \
  "between the current pin and that first crossing" migration_refusal_guide_row
check_absent "the guide's migration refusal row drops the dead remedy" 0 "then re-run" \
  migration_refusal_guide_row

# ============================================================================
# The migration table tracks docs/CONSUMERS.md
# ============================================================================
#
# A RATCHET, NOT A PROOF. The table is carried by the command (#561 G5), so
# nothing keeps it current except a reader remembering — and the note that
# ships without its row is the silent damage the whole command exists to
# prevent. This row re-derives the tag set from the prose and fails when a
# note names a tag no row carries. It scans UNWRAPPED paragraphs, because a
# note whose version and whose "and later" fall on either side of a line
# break is invisible to a line-local grep, and that is exactly the note that
# would be missed.
#
# It cannot prove the scan complete: a note phrased in a way this regex does
# not match passes silently. It can only ensure that the notes it CAN see are
# all covered, which is one direction of the risk and the cheap one.
# availability_tags — every X.Y.Z that docs/CONSUMERS.md declares something
# AVAILABLE at, in the sense G5 names: the literal "available" within the 100
# characters before the version, and "and later" directly after it.
#
# THE 100-CHARACTER WINDOW IS THE ASSERTION, not a tuning knob. Matching on
# "the paragraph contains 'available'" was the first shape of this scan and
# it was wrong in the one way that matters: `docs/CONSUMERS.md`'s Labels
# automation block runs from the 0.3.0 note past the 0.7.7 one without a
# blank line, so a paragraph test read #501's "At `0.7.7` and later" — which
# says where an existing notice PRINTS — as an availability note, purely
# because an unrelated sentence upstream of it used the word.
#
# The text is unwrapped first: a note whose version and whose "and later"
# fall on either side of a line break is invisible to a line-local grep, and
# `0.7.0`'s and `0.1.0`'s are both exactly that (which is why #561's own body
# counts ten notes where an unwrapped scan finds more).
#
# One note is deliberately not a row, and bin/ceremony-upgrade's table
# comment names it: #501's 0.7.7, excluded by this window, and by #561's
# happy path moving 0.7.6 -> 0.7.7 and requiring it to succeed.
#
# #559's was the other, and the 0.7.8 cut ended that: its "available at
# **unreleased** and later" had no tag to key a row on, the release cleared
# the marker to `0.7.8`, and this scan found the tag before any row carried
# it — which is the ratchet firing as designed, not a regression.
availability_tags() {
  awk '
    /^[[:space:]]*$/ { if (p != "") { print p; p = "" }; next }
    { p = p " " $0 }
    END { if (p != "") print p }
  ' "$ROOT/docs/CONSUMERS.md" |
    awk '
      {
        s = $0
        while (match(s, /[0-9]+\.[0-9]+\.[0-9]+`?[ ]+and later/)) {
          before = substr(s, 1, RSTART - 1)
          if (length(before) > 100) {
            before = substr(before, length(before) - 99)
          }
          if (before ~ /available/) {
            tok = substr(s, RSTART, RLENGTH)
            sub(/`?[ ]+and later/, "", tok)
            print tok
          }
          s = substr(s, RSTART + RLENGTH)
        }
      }
    ' | LC_ALL=C sort -u
}

table_gap() {
  local tag
  while IFS= read -r tag; do
    grep -q "^  \"$tag|" "$ROOT/bin/ceremony-upgrade" ||
      printf 'UNCOVERED %s\n' "$tag"
  done < <(availability_tags)
  echo "scanned"
}
check_absent "every availability tag in docs/CONSUMERS.md carries a migration row" 0 "UNCOVERED" \
  table_gap
check "the table-gap row ran rather than exiting early" 0 "scanned" table_gap

# ...and the scan is NOT VACUOUS. A regex that silently matched nothing
# satisfies the row above forever, which is the shape #525 hit: a weakened
# check passes the suite and proves nothing. The floor is the tags the issue
# itself enumerates, so this row fails if the prose moves out from under the
# scan as well as if the scan breaks.
tags_line() { availability_tags | tr '\n' ' '; }
check "the prose scan finds the tags #561's own table names" 0 "0.2.0 0.3.0 0.4.1 0.5.0 0.6.0" \
  tags_line
check "the prose scan finds every tag the migration table carries" 0 "0.1.0 0.2.0 0.3.0 0.4.1 0.5.0 0.6.0 0.7.0" \
  tags_line

# ============================================================================
# Round 1 — the writes are the plan
#
# Every row below is a defect the panel reproduced at cf3d80b, and none of
# the 88 rows above it would have caught any of them. They share one shape:
# --check announced a plan and --fix did something else, at exit 0.
# ============================================================================

# --- a sibling repository is not this repository (claude-bot §1) -------------
#
# The rewrite used to match `heavy-duty/ceremony([^@ \t]*)?@`, a SUPERSET of
# PIN_RE with the anchoring '/' missing, so any repo whose name merely STARTS
# with `ceremony` was rewritten — never enumerated, never reported, never part
# of the all-or-none comparison. The org has no such sibling today; its own
# naming precedent (rig/rig-templates, bulldozer/bulldozer-examples) is that
# it produces them.
#
# This is the sed build at one line's width: a third-party action pinned to a
# tag that has nothing to do with ceremony, moved to a ceremony tag, in a file
# the operator was told carried one pin.
consumer sibling 0.7.6
cat >>"$TMP/sibling/.github/workflows/ci.yml" <<'YAML'
      - uses: heavy-duty/ceremony-templates/actions/foo@v1
      - uses: heavy-duty/ceremonyzilla@v2
YAML

check "a sibling-named repo is not counted as a pin" 0 \
  "0.7.6 -> 0.7.7, $PIN_COUNT ceremony ref(s) in 4 file(s)" \
  in_consumer sibling --check --source "$SRC" 0.7.7
check "--fix moves the real pins in the sibling fixture" 0 \
  "rewrote $PIN_COUNT ceremony ref(s)" \
  in_consumer sibling --fix --source "$SRC" 0.7.7
sibling_refs() { grep -oE 'heavy-duty/ceremony[A-Za-z-]*[^ ]*@[A-Za-z0-9._-]+' "$TMP/sibling/.github/workflows/ci.yml"; }
check "the sibling repo keeps its own ref through --fix" 0 \
  "heavy-duty/ceremony-templates/actions/foo@v1" sibling_refs
check "a sibling repo with no path keeps its ref too" 0 \
  "heavy-duty/ceremonyzilla@v2" sibling_refs
check_absent "no sibling ref was moved to the ceremony tag" 0 \
  "ceremony-templates/actions/foo@0.7.7" sibling_refs
check "the real pin in that same file did move" 0 \
  "heavy-duty/ceremony/actions/docs-sync@0.7.7" sibling_refs

# --- the dedup key that collided (claude-bot §2) -----------------------------
#
# `tr '/' '_'` is not injective: 'a/b.yml' and 'a_b.yml' keyed to the same
# stamp, so the second file was skipped, the run wrote one of the two files it
# had just announced, and said `done` at exit 0. That is all-or-none broken in
# the direction that is not a refusal — a half-applied move the operator is
# told is complete, and one the NEXT run then refuses as a mixed tree.
consumer collide 0.7.6
mkdir -p "$TMP/collide/.github/workflows/a"
printf 'jobs:\n  x:\n    uses: heavy-duty/ceremony/.github/workflows/one.yml@0.7.6\n' \
  >"$TMP/collide/.github/workflows/a/b.yml"
printf 'jobs:\n  y:\n    uses: heavy-duty/ceremony/.github/workflows/two.yml@0.7.6\n' \
  >"$TMP/collide/.github/workflows/a_b.yml"

check "--check counts both halves of the colliding path pair" 0 \
  "0.7.6 -> 0.7.7, $((PIN_COUNT + 2)) ceremony ref(s) in 6 file(s)" \
  in_consumer collide --check --source "$SRC" 0.7.7
check "--fix moves both halves of the colliding path pair" 0 \
  "rewrote $((PIN_COUNT + 2)) ceremony ref(s) in 6 file(s) to @0.7.7" \
  in_consumer collide --fix --source "$SRC" 0.7.7
check_absent "no ref is left behind under a colliding key" 0 "0.7.6" refs collide
check "every ref in the colliding fixture is at the target" 0 \
  "$((PIN_COUNT + 2)) 0.7.7" refs collide

# --- the byte outside the pin line (claude-bot §4) ---------------------------
#
# awk's `print` terminates every record, so a workflow file that ended without
# a newline came back one byte longer. #561 G8 says this command touches
# nothing outside the `uses:` line, and that byte is outside it.
consumer nonewline 0.7.6
printf 'jobs:\n  z:\n    uses: heavy-duty/ceremony/.github/workflows/three.yml@0.7.6' \
  >"$TMP/nonewline/.github/workflows/tail.yml"
final_byte_is_newline() {
  if [ "$(tail -c 1 "$TMP/nonewline/.github/workflows/tail.yml" | wc -l)" -eq 0 ]; then
    echo "no-final-newline"
  else
    echo "final-newline"
  fi
}
check "the fixture really does lack a final newline before the run" 0 \
  "no-final-newline" final_byte_is_newline
check "--fix moves the pin in the file that has no final newline" 0 \
  "rewrote $((PIN_COUNT + 1)) ceremony ref(s)" \
  in_consumer nonewline --fix --source "$SRC" 0.7.7
check "the missing final newline is still missing after --fix" 0 \
  "no-final-newline" final_byte_is_newline
check "the pin in that file moved all the same" 0 \
  "three.yml@0.7.7" \
  cat "$TMP/nonewline/.github/workflows/tail.yml"

# --- the transaction across the docs-sync call (codex-bot, blocking) ---------
#
# `every check runs before any write` was true of this command and false of
# the pair. docs-sync's scaffold refusal — `markers are duplicated|unbalanced`
# — fires INSIDE its fix loop, after the mirror and the root AGENTS.md stub
# are written. Sequence a pin rewrite in front of it and an otherwise-valid
# adjacent move leaves the consumer pinned forward at the target with a
# half-written mirror and none of the hand edits a pin implies: exactly the
# half-upgraded tree this command exists to make unrepresentable.
#
# A source tree of its own, because naming a guarded scaffold changes what
# docs-sync demands of EVERY consumer above.
# --- the 0.7.0 step: a crossing that asks the tree for nothing --------------
#
# 0.5.0's class exactly (#610). The premise is that release.yml's
# workflow_call interface is unchanged in name and requiredness across this
# tag, so a caller valid below it is valid at it — which makes "the plan
# writes no byte" a claim about the artifact rather than about the note. The
# two plan rows are separate on purpose: a plan that announces the crossing
# without pointing at the guide is a plan a consumer cannot act on.
consumer rcpath 0.6.3
check "0.7.0 is announced as an applied step" 0 \
  "0.7.0 is an APPLIED STEP, so this run performs 0.6.3 -> 0.7.0 and stops there" \
  in_consumer rcpath --check --source "$SRC" 0.7.0
check "the 0.7.0 check prints a plan" 0 "THE PLAN" \
  in_consumer rcpath --check --source "$SRC" 0.7.0
check "the 0.7.0 plan says the crossing asks this tree for no edit" 0 \
  "no edit to this tree: 0.7.0 asks it for nothing" \
  in_consumer rcpath --check --source "$SRC" 0.7.0
check "the 0.7.0 plan names the guide section" 0 \
  'docs/CONSUMERS.md § "The artifact hook"' \
  in_consumer rcpath --check --source "$SRC" 0.7.0
check_absent "the 0.7.0 plan is not a fault" 0 "FAULT" \
  in_consumer rcpath --check --source "$SRC" 0.7.0
check_absent "the 0.7.0 plan is not hand-only" 0 "THE CROSSING IS HAND-ONLY" \
  in_consumer rcpath --check --source "$SRC" 0.7.0
unchanged "the 0.7.0 check writes nothing" "$TMP/rcpath" \
  in_consumer rcpath --check --source "$SRC" 0.7.0

# B5 — the workflows are listed BEFORE the run, so the assertion is against
# what this consumer actually had rather than against a hard-coded set. A step
# that wrote a file, deleted one, or changed a byte that is not the pin shows
# up in one of the two diffs below.
RCPATH_WF_BEFORE="$TMP/rcpath-workflows-before"
RCPATH_WF_BODY_BEFORE="$TMP/rcpath-workflows-body-before"
workflow_set() { (cd "$TMP/rcpath" && find .github/workflows -type f | sort); }
workflow_bodies() { (cd "$TMP/rcpath" && find .github/workflows -type f | sort | xargs cat); }
workflow_set >"$RCPATH_WF_BEFORE"
workflow_bodies >"$RCPATH_WF_BODY_BEFORE"

RCPATH_RUN="$TMP/rcpath-run"
capture_run "$RCPATH_RUN" in_consumer rcpath --fix --source "$SRC" 0.7.0
check "the 0.7.0 crossing completes" 0 \
  "0.6.3 -> 0.7.0 done, including the applied step for 0.7.0" \
  replay_run "$RCPATH_RUN"
check "the 0.7.0 crossing exits zero" 0 "0" cat "$RCPATH_RUN.rc"
check "the completed crossing advances every ref" 0 "$PIN_COUNT 0.7.0" \
  refs rcpath
check "the completed crossing re-syncs the mirror" 0 "router v1" \
  cat "$TMP/rcpath/.ceremony/AGENTS.md"
workflow_set_diff() {
  diff "$RCPATH_WF_BEFORE" <(workflow_set) && echo "same-workflow-set"
}
workflow_body_diff() {
  diff \
    <(sed 's|ceremony/\(.*\)@0\.6\.3|ceremony/\1@0.7.0|' "$RCPATH_WF_BODY_BEFORE") \
    <(workflow_bodies) && echo "identical-but-for-the-pin"
}
check "the crossing leaves the workflow set unchanged" 0 "same-workflow-set" \
  workflow_set_diff
check "the crossing changes no workflow byte but the pin" 0 \
  "identical-but-for-the-pin" workflow_body_diff

SRC_SCAF="$TMP/src-scaffold"
cp -pPR "$SRC" "$SRC_SCAF"
mkdir -p "$SRC_SCAF/.github"
printf '.github/pull_request_template.md\n' >"$SRC_SCAF/docs/SCAFFOLDED.txt"
printf '## Checklist\n\n- [ ] a thing\n' >"$SRC_SCAF/.github/pull_request_template.md"

# --- the 0.7.8 step: the plan names the byte docs-sync already writes -------

consumer scaffold-created 0.7.7
check "0.7.8 is announced as an applied step" 0 \
  "0.7.8 is an APPLIED STEP, so this run performs 0.7.7 -> 0.7.8 and stops there" \
  in_consumer scaffold-created --check --source "$SRC_SCAF" 0.7.8
check "the 0.7.8 plan names the guarded-scaffold edit" 0 \
  "edit .github/pull_request_template.md — add or refresh the guarded-scaffold block" \
  in_consumer scaffold-created --check --source "$SRC_SCAF" 0.7.8
check "the 0.7.8 plan names the writer" 0 \
  "mirror re-sync at the end of this run writes it through docs-sync --fix" \
  in_consumer scaffold-created --check --source "$SRC_SCAF" 0.7.8
check "the 0.7.8 plan names the guide section" 0 \
  'docs/CONSUMERS.md § "The guarded scaffold — ceremony owns a block, you own the rest"' \
  in_consumer scaffold-created --check --source "$SRC_SCAF" 0.7.8
check_absent "the 0.7.8 plan is not a fault" 0 "FAULT" \
  in_consumer scaffold-created --check --source "$SRC_SCAF" 0.7.8
check_absent "the 0.7.8 plan is not hand-only" 0 "THE CROSSING IS HAND-ONLY" \
  in_consumer scaffold-created --check --source "$SRC_SCAF" 0.7.8

SCAFFOLD_CREATED_RUN="$TMP/scaffold-created-run"
capture_run "$SCAFFOLD_CREATED_RUN" \
  in_consumer scaffold-created --fix --source "$SRC_SCAF" 0.7.8
check "the 0.7.8 crossing completes" 0 \
  "0.7.7 -> 0.7.8 done, including the applied step for 0.7.8" \
  replay_run "$SCAFFOLD_CREATED_RUN"
check "the completed crossing advances every ref" 0 "$PIN_COUNT 0.7.8" \
  refs scaffold-created
check "the completed crossing re-syncs the mirror" 0 "router v1" \
  cat "$TMP/scaffold-created/.ceremony/AGENTS.md"
check "the completed crossing creates the scaffold block" 0 \
  "<!-- ceremony:pr-template:start -->" \
  cat "$TMP/scaffold-created/.github/pull_request_template.md"
check "the created scaffold carries the source bytes" 0 "a thing" \
  cat "$TMP/scaffold-created/.github/pull_request_template.md"
check "the created scaffold closes its owned block" 0 \
  "<!-- ceremony:pr-template:end -->" \
  cat "$TMP/scaffold-created/.github/pull_request_template.md"

consumer scaffold-appended 0.7.7
printf 'Our own template.\n\nDeployment notes stay ours.\n' \
  >"$TMP/scaffold-appended/.github/pull_request_template.md"
SCAFFOLD_APPEND_BEFORE="$TMP/scaffold-appended-before"
cp "$TMP/scaffold-appended/.github/pull_request_template.md" "$SCAFFOLD_APPEND_BEFORE"
SCAFFOLD_APPENDED_RUN="$TMP/scaffold-appended-run"
capture_run "$SCAFFOLD_APPENDED_RUN" \
  in_consumer scaffold-appended --fix --source "$SRC_SCAF" 0.7.8
check "the existing-template crossing completes" 0 \
  "0.7.7 -> 0.7.8 done, including the applied step for 0.7.8" \
  replay_run "$SCAFFOLD_APPENDED_RUN"
template_prefix_survives() {
  local bytes
  bytes="$(wc -c <"$SCAFFOLD_APPEND_BEFORE")"
  head -c "$bytes" "$TMP/scaffold-appended/.github/pull_request_template.md" |
    cmp -s "$SCAFFOLD_APPEND_BEFORE" - && echo "pre-existing-bytes-survive"
}
check "appending the block preserves every pre-existing byte" 0 \
  "pre-existing-bytes-survive" template_prefix_survives
check "the block is appended to the existing template" 0 "a thing" \
  cat "$TMP/scaffold-appended/.github/pull_request_template.md"

consumer scaffold-broken 0.7.7
printf 'Our own template.\n\n<!-- ceremony:pr-template:start -->\n\nnever closed\n' \
  >"$TMP/scaffold-broken/.github/pull_request_template.md"
SCAFFOLD_BROKEN_BEFORE="$(fingerprint "$TMP/scaffold-broken")"
SCAFFOLD_BROKEN_RUN="$TMP/scaffold-broken-run"
capture_run "$SCAFFOLD_BROKEN_RUN" \
  in_consumer scaffold-broken --fix --source "$SRC_SCAF" 0.7.8
check "an unbalanced marker reaches the docs-sync refusal" 1 \
  "cannot fix .github/pull_request_template.md" replay_run "$SCAFFOLD_BROKEN_RUN"
check "the refused 0.7.8 crossing reports its rollback" 1 "rolled back" \
  replay_run "$SCAFFOLD_BROKEN_RUN"
scaffold_broken_unchanged() {
  [ "$SCAFFOLD_BROKEN_BEFORE" = "$(fingerprint "$TMP/scaffold-broken")" ] &&
    echo "byte-identical-after-rollback"
}
check "the refused 0.7.8 crossing is byte-identical after rollback" 0 \
  "byte-identical-after-rollback" scaffold_broken_unchanged
check "the rollback keeps every ref at 0.7.7" 0 "$PIN_COUNT 0.7.7" \
  refs scaffold-broken
check_absent "the rollback leaves no mirror behind" 1 "router v1" \
  cat "$TMP/scaffold-broken/.ceremony/AGENTS.md"

# One start marker and no end: `unbalanced`, which docs-sync refuses rather
# than guessing where the consumer's own bytes resume.
consumer broken-marker 0.7.6
printf 'Our own template.\n\n<!-- ceremony:pr-template:start -->\n\nnever closed\n' \
  >"$TMP/broken-marker/.github/pull_request_template.md"

check "the docs-sync refusal reaches the operator" 1 \
  "cannot fix .github/pull_request_template.md" \
  in_consumer broken-marker --fix --source "$SRC_SCAF" 0.7.7
check "a refused move says the tree was rolled back" 1 \
  "rolled back" \
  in_consumer broken-marker --fix --source "$SRC_SCAF" 0.7.7

# A FRESH FIXTURE FOR THE FINGERPRINT ROW, and it is the difference between a
# measurement and a coincidence. `unchanged` takes its `before` from whatever
# the rows above left behind — so against a build that does not roll back, the
# two rows above have ALREADY moved the pins and written the mirror, and this
# row would compare a half-upgraded tree with itself and pass. Rebuilding puts
# the run that must write nothing on a tree that has never been written to.
consumer broken-marker 0.7.6
printf 'Our own template.\n\n<!-- ceremony:pr-template:start -->\n\nnever closed\n' \
  >"$TMP/broken-marker/.github/pull_request_template.md"
unchanged "a docs-sync refusal mid-fix leaves the WHOLE tree byte-identical" \
  "$TMP/broken-marker" \
  in_consumer broken-marker --fix --source "$SRC_SCAF" 0.7.7
check "the pins did not move under a rolled-back run" 0 "$PIN_COUNT 0.7.6" \
  refs broken-marker
check_absent "the rolled-back run left no ref at the target" 0 "0.7.7" \
  refs broken-marker
# The mirror is the other half of what a partial write leaves: docs-sync had
# already added .ceremony/ and the root AGENTS.md stub by the time it refused.
mirror_state() {
  if [ -e "$TMP/broken-marker/.ceremony" ] || [ -e "$TMP/broken-marker/AGENTS.md" ]; then
    echo "mirror-partially-written"
  else
    echo "no-mirror"
  fi
}
check "the rolled-back run left no half-written mirror either" 0 "no-mirror" \
  mirror_state

# RESTORE, NOT DELETE. The row above only proves the rollback removes what the
# run created — a rollback that simply `rm -rf`'d the territory would pass it,
# and would destroy the mirror of every consumer that already had one. This
# fixture arrives with a STALE .ceremony/ and a root AGENTS.md the repo has
# since edited, both of which docs-sync would have rewritten before it refused,
# and both of which must come back byte for byte.
consumer had-mirror 0.7.6
printf 'Our own template.\n\n<!-- ceremony:pr-template:start -->\n\nnever closed\n' \
  >"$TMP/had-mirror/.github/pull_request_template.md"
mkdir -p "$TMP/had-mirror/.ceremony"
printf '# router, as of the OLD pin\n' >"$TMP/had-mirror/.ceremony/AGENTS.md"
printf '# rules, as of the OLD pin\n' >"$TMP/had-mirror/.ceremony/RULES.md"
printf 'stale, and not in the manifest\n' >"$TMP/had-mirror/.ceremony/GONE.md"
printf '# our own router stub, edited by us\n' >"$TMP/had-mirror/AGENTS.md"

unchanged "a rollback restores a mirror that was already there" \
  "$TMP/had-mirror" \
  in_consumer had-mirror --fix --source "$SRC_SCAF" 0.7.7
check "the pre-existing mirror came back with its old bytes" 0 \
  "as of the OLD pin" cat "$TMP/had-mirror/.ceremony/AGENTS.md"
check "the orphan docs-sync would have deleted came back too" 0 \
  "not in the manifest" cat "$TMP/had-mirror/.ceremony/GONE.md"
check "the consumer's own root AGENTS.md came back untouched" 0 \
  "edited by us" cat "$TMP/had-mirror/AGENTS.md"

# The fixture is not vacuous: with the marker closed, the SAME move over the
# SAME source tree succeeds and writes the scaffold. Without this row the one
# above passes for a tree that could never have been upgraded at all.
consumer good-marker 0.7.6
printf 'Our own template.\n\n<!-- ceremony:pr-template:start -->\nold\n<!-- ceremony:pr-template:end -->\n' \
  >"$TMP/good-marker/.github/pull_request_template.md"
check "the same move over the same source succeeds with the marker closed" 0 \
  "0.7.6 -> 0.7.7 done" \
  in_consumer good-marker --fix --source "$SRC_SCAF" 0.7.7
check "the guarded scaffold really was written on the successful run" 0 \
  "a thing" cat "$TMP/good-marker/.github/pull_request_template.md"
check "a successful run does not claim a rollback" 0 "$PIN_COUNT 0.7.7" \
  refs good-marker

# --- the write territory is a declaration, so it gets a ratchet --------------
#
# bin/ceremony-upgrade snapshots .github/, .ceremony/ and the root's regular
# files, and restores exactly those on a failure. That set is DECLARED rather
# than derived from docs/VENDORED.txt and docs/SCAFFOLDED.txt, because a
# second reader of docs-sync's manifests is the two-readers-disagree bug this
# round is about. So the declaration is ratcheted here instead: the day a
# scaffold path lands outside those roots, ceremony's own CI says so, before
# any consumer runs a --fix whose rollback would silently miss it.
#
# The mirror needs no row — docs-sync writes every manifest path under
# .ceremony/ by construction — but the root AGENTS.md stub and every
# SCAFFOLDED.txt path are real paths in a consumer tree.
outside_territory() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      .github/* | .ceremony/*) ;;
      */*) printf 'OUTSIDE %s\n' "$f" ;;
      *) ;; # a bare name is a regular file at the root, which is snapshotted
    esac
  done <"$ROOT/docs/SCAFFOLDED.txt"
  echo "scanned"
}
check_absent "every guarded scaffold path is inside the snapshotted territory" 0 \
  "OUTSIDE" outside_territory
check "the territory scan ran rather than exiting early" 0 "scanned" outside_territory
# Not vacuous: the manifest is non-empty, so the loop above had something to
# grade. A SCAFFOLDED.txt that emptied out would satisfy the row forever.
check "docs/SCAFFOLDED.txt names at least one path to grade" 0 \
  ".github/pull_request_template.md" cat "$ROOT/docs/SCAFFOLDED.txt"

# ============================================================================
# The applied step — 0.4.1's two-caller split (#597)
# ============================================================================
#
# THE INPUTS ARE THE REAL CONSUMERS, measured 2026-09-02 from each board's live
# `.github/workflows/labels.yml`, and they are the whole reason this step is
# not a `sed`: neither file resembles the published stub. Both carry
# repo-specific prose comments, different trigger type lists, different
# permission blocks, and a `*/15` cadence that is not the stub's hourly one. A
# step written against the stub's bytes fails on both of them, and a step that
# substitutes text corrupts whichever one it does not fail on.

# barbershop_caller <ref> — heavy-duty/martin-reyes-barbershop's own labels
# caller, verbatim but for the pin: a schedule and a bare workflow_dispatch
# each carrying a trailing hand comment, six permissions including
# `actions: read` with inline comments of its own, and an `issues:` trigger.
barbershop_caller() {
  cat <<EOF
# The ceremony's labels automation: additive path-based \`scope:*\` labels, plus
# reconciliation of PR state, blockers, handoff and stale status.
#
# Run its \`workflow_dispatch\` ONCE after this merges — that bootstraps the whole
# taxonomy on a fresh repo, \`release\` included.
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}] # advisory; the handoff label is the real wake
  workflow_dispatch:                 # bootstraps missing labels on a fresh repo
  pull_request_target:
    types: [opened, reopened, ready_for_review, converted_to_draft, synchronize, labeled, unlabeled, review_requested, review_request_removed]
  issues:
    types: [opened, edited, assigned, unassigned, labeled, unlabeled, closed, reopened]
permissions:
  contents: read
  issues: write
  pull-requests: write
  # This repo is PRIVATE, so none of these three reads are implied — without
  # them the failure appears as an empty \`state:*\` axis on the board rather than
  # a red run, which is the harder symptom to notice.
  checks: read     # statusCheckRollup read for PR state
  statuses: read   # mergeability/commit-status rollup read
  actions: read    # checkSuite.workflowRun read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}

# cast_caller <ref> — heavy-duty/cast's own labels caller, verbatim but for the
# pin. Three permissions and NO \`actions:\` key at all, no \`issues:\` trigger,
# and the same */15 cadence.
cast_caller() {
  cat <<EOF
name: labels
# The automation LABELS.md promises, now implemented upstream: scope labeling
# and the state reconciler live in the reusable workflow this caller pins. Cast
# keeps the triggers and permissions (a called workflow cannot define them),
# its path map in .github/labeler.yml, and its panel + scope taxonomy in
# .github/labels.conf.
on:
  schedule: [{cron: "*/15 * * * *"}] # advisory; the handoff label is the real wake
  workflow_dispatch:                 # bootstraps missing labels on a fresh repo
  pull_request_target:
    types: [opened, reopened, ready_for_review, converted_to_draft, synchronize, labeled, unlabeled]
permissions:
  contents: read
  issues: write
  pull-requests: write
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}

# split_consumer <name> <ref> <caller-fn> — consumer() with its labels caller
# replaced by a real one, plus a SIBLING workflow of the consumer's own that
# carries its own schedule and its own bare workflow_dispatch. That sibling is
# the fixture for the file-wide-substitution build: a step that removes a cron
# by pattern rather than by the line it enumerated takes this file's with it.
split_consumer() {
  local name="$1" ref="$2" fn="$3"
  consumer "$name" "$ref"
  "$fn" "$ref" >"$TMP/$name/.github/workflows/labels.yml"
  cat >"$TMP/$name/.github/workflows/nightly.yml" <<'EOF'
name: nightly
on:
  schedule: [{cron: "0 3 * * *"}]
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: make nightly
EOF
}

sweep_of() { cat "$TMP/$1/.github/workflows/labels-sweep.yml"; }
caller_of() { cat "$TMP/$1/.github/workflows/labels.yml"; }
# The files carrying a top-level-ish `schedule:` key, bracketed so a superset
# cannot satisfy the row: this is the double-sweep assertion, and it is only
# an assertion if it can fail by finding one file too many.
schedule_sites() {
  printf '[%s]\n' "$(
    grep -rlE '^[[:space:]]*schedule:' "$TMP/$1/.github/workflows" |
      sed "s|$TMP/$1/||" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
  )"
}
occurrences() { grep -cF -e "$2" "$TMP/$1"; }

# --- A1, A2, A5, A6: the happy path -----------------------------------------

split_consumer bshop 0.3.0 barbershop_caller

# A5 first, on the untouched tree: --check prints the whole plan and writes
# nothing. Running it after the --fix below would grade the wrong tree.
check "--check names the applied step and the tag it stops at" 0 \
  "0.4.1 is an APPLIED STEP, so this run performs 0.3.0 -> 0.4.1 and stops there" \
  in_consumer bshop --check --source "$SRC" 0.4.1
check "--check names the file the step would create" 0 \
  "create .github/workflows/labels-sweep.yml" \
  in_consumer bshop --check --source "$SRC" 0.4.1
check "--check names the cron relocation and the cadence it preserves" 0 \
  'the cron RELOCATED from .github/workflows/labels.yml line 8, cadence unchanged: [{cron: "*/15 * * * *"}]' \
  in_consumer bshop --check --source "$SRC" 0.4.1
check "--check names the bare workflow_dispatch deletion" 0 \
  "the bare workflow_dispatch: key, which the sweep caller declares" \
  in_consumer bshop --check --source "$SRC" 0.4.1
check "--check names the actions: write grant as a line rewrite" 0 \
  "actions: write, the trigger job's dispatch being a write" \
  in_consumer bshop --check --source "$SRC" 0.4.1
# The plan shows the BYTES, both sides. This rewrite replaces the consumer's
# own trailing comment as well as the value — a note explaining a read grant
# is false beside a write one — and a reader who is only told "the grant is
# rewritten" cannot tell beforehand that their prose is going with it.
check "--check shows the exact line the rewrite replaces" 0 \
  "-   actions: read    # checkSuite.workflowRun read" \
  in_consumer bshop --check --source "$SRC" 0.4.1
check "--check shows the exact line it would write there" 0 \
  "+   actions: write   # the trigger job's dispatch of the sweep caller" \
  in_consumer bshop --check --source "$SRC" 0.4.1
check "--check names the mirror re-sync" 0 "then re-sync the doctrine mirror" \
  in_consumer bshop --check --source "$SRC" 0.4.1
check "--check names the pin the run would leave behind" 0 \
  "THIS RUN LEAVES THE PIN AT 0.4.1" \
  in_consumer bshop --check --source "$SRC" 0.4.1
unchanged "--check over an applied step leaves the whole tree byte-identical" \
  "$TMP/bshop" in_consumer bshop --check --source "$SRC" 0.4.1

# A6's baseline, taken before the run that must not move these files.
NIGHTLY_BEFORE="$(sha256sum <"$TMP/bshop/.github/workflows/nightly.yml")"

check "the applied step completes a move that ends at the crossed tag" 0 \
  "0.3.0 -> 0.4.1 done, including the applied step for 0.4.1" \
  in_consumer bshop --fix --source "$SRC" 0.4.1
check "every ref moved to the crossed tag, the created caller included" 0 \
  "$((PIN_COUNT + 1)) 0.4.1" refs bshop
check_absent "no ref is left at the old pin" 0 "0.3.0" refs bshop

# A1 — the sweep caller is the guide's stub at the crossed tag.
check "the sweep caller exists and carries the pin substituted" 0 \
  "uses: heavy-duty/ceremony/.github/workflows/labels-sweep.yml@0.4.1" \
  sweep_of bshop
check "the sweep caller declares the bootstrap choice input" 0 \
  "        type: choice" sweep_of bshop
check "the bootstrap input keeps its yes default" 0 \
  '        default: "yes"' sweep_of bshop
check "the sweep caller carries the consumer's OWN cadence, relocated" 0 \
  '  schedule: [{cron: "*/15 * * * *"}]' sweep_of bshop
check_absent "the stub's own hourly cadence was not written over it" 0 \
  '0 * * * *' sweep_of bshop
check "the sweep caller keeps the stub's actions: read" 0 \
  "  actions: read " sweep_of bshop

# A1 — the labels caller. The cron and the bare dispatch are GONE, not
# commented out and not emptied.
check_absent "the labels caller no longer declares a schedule" 0 "schedule:" \
  caller_of bshop
check_absent "the labels caller no longer declares a bare workflow_dispatch" 0 \
  "workflow_dispatch:" caller_of bshop
check "the labels caller now grants actions: write" 0 "  actions: write" \
  caller_of bshop
# The blind-append build ends with BOTH keys — YAML GitHub rejects at parse
# time, and a board that stops. The key appears once, with one value.
check "the actions key appears exactly once" 0 "1" occurrences bshop/.github/workflows/labels.yml "actions:"
check_absent "the old actions: read grant is gone" 0 "actions: read" caller_of bshop
check "the labels caller keeps its own trigger list untouched" 0 \
  "types: [opened, edited, assigned, unassigned, labeled, unlabeled, closed, reopened]" \
  caller_of bshop
check "the labels caller keeps its own permission comments" 0 \
  "# This repo is PRIVATE" caller_of bshop

# A2 — THE DOUBLE-SWEEP CASE, ASSERTED AS AN ABSENCE. Every other row here
# passes against a build that COPIES the cron instead of moving it: the sweep
# caller exists, carries the right cadence, the pin moved, actions: write
# landed. Only this one fails, and what it catches is the damage the guide
# capitalises — every tick firing both callers into one labels-reconcile
# group, displacement going UP, the fix reading as the bug getting worse.
#
# The sibling below is A6's, and it is why this row names the files rather
# than counting to one: the consumer's own nightly workflow has a schedule of
# its own that nothing in this plan may touch, so "exactly once in the tree"
# and "the sibling survives" cannot both be literally true. Naming the sites
# keeps both must-fail builds rejected — a copied cron adds the labels caller
# to this list, and a file-wide substitution removes the sibling from it.
check "the cron MOVED: the only ceremony caller carrying a schedule is the sweep one" 0 \
  "[.github/workflows/labels-sweep.yml .github/workflows/nightly.yml]" \
  schedule_sites bshop

# A6 — nothing outside the plan moved.
nightly_now() { sha256sum <"$TMP/bshop/.github/workflows/nightly.yml"; }
check "the consumer's own scheduled workflow is byte-identical" 0 \
  "$NIGHTLY_BEFORE" nightly_now
check "the consumer's README still names its own old version" 0 \
  "Pinned to ceremony 0.3.0" cat "$TMP/bshop/README.md"
check "the consumer's own CHANGELOG heading is untouched" 0 \
  "## 0.3.0 — 2026-02-02" cat "$TMP/bshop/CHANGELOG.md"
check "the mirror is current after the step, so docs-sync --check passes" 0 \
  "is an exact mirror" in_consumer_docs_sync bshop --check --source "$SRC"

# --- A4: the step stops at the first crossed tag ----------------------------
#
# The build this rejects applies 0.4.1 and KEEPS GOING, refusing at 0.5.0 with
# the refs already past 0.4.1 — the half-upgraded consumer the whole command
# exists to make unrepresentable.
split_consumer bshoplong 0.3.0 barbershop_caller
# The plan rows run BEFORE the --fix below: afterwards this tree stands at
# 0.4.1 and the same command grades a different move, so a row placed after it
# would assert nothing about a partial one.
check "the run says which pin it will leave the tree at" 1 \
  "THIS RUN LEAVES THE PIN AT 0.4.1" \
  in_consumer bshoplong --check --source "$SRC" 0.7.8
check "the run says what remains beyond it" 1 \
  "REMAINING: 0.4.1 -> 0.7.8 is not performed by this run" \
  in_consumer bshoplong --check --source "$SRC" 0.7.8
check "the run names the next migration between them" 1 \
  "The next migration between them is 0.5.0" \
  in_consumer bshoplong --check --source "$SRC" 0.7.8
check_absent "a partial move never reports the requested move as done" 1 \
  "0.3.0 -> 0.7.8 done" in_consumer bshoplong --check --source "$SRC" 0.7.8
unchanged "the partial-move plan writes nothing either" "$TMP/bshoplong" \
  in_consumer bshoplong --check --source "$SRC" 0.7.8
# --- B3, B4: two runs climb two rungs, one rung each (#600) -----------------
#
# THE RUNS ARE CAPTURED, NOT RE-RUN. Every other block in this file re-invokes
# the command per row, which is free while the row is a --check or a refusal.
# Here the rows grade a SEQUENCE — run one's output, then run two's — and a
# `check` that re-invoked --fix would climb a third rung under the row below
# it. So each run happens exactly once and the rows replay what it said.
RUN1="$TMP/bshoplong-run1"
capture_run "$RUN1" in_consumer bshoplong --fix --source "$SRC" 0.7.8

check "a move past the crossed tag performs only the first step" 1 \
  "0.3.0 -> 0.4.1 done, including the applied step for 0.4.1" \
  replay_run "$RUN1"
check "every ref stops at the first crossed tag" 0 "$((PIN_COUNT + 1)) 0.4.1" \
  refs bshoplong
check_absent "no ref ran on to the requested target" 0 "0.7.8" refs bshoplong
# B4 — ONE RUN NEVER CLIMBS TWO RUNGS, and this is the first release in which
# that build is reachable: with 0.5.0 mechanised too, a step that chained
# would perform both and report a move to 0.5.0 at exit non-zero, passing
# every row above. The `-> 0.5.0 done` absence covers both spellings a chainer
# could print (0.3.0 -> and 0.4.1 ->), and the ref assertion is the tree's own
# answer to the same question.
check_absent "run one leaves no ref at the second rung" 0 "0.5.0" refs bshoplong
check_absent "run one reports no completed move to the second rung" 1 \
  "-> 0.5.0 done" replay_run "$RUN1"
check_absent "run one reports no completed move to the requested target" 1 \
  "0.3.0 -> 0.7.8 done" replay_run "$RUN1"
check "run one names the second rung as what comes next, not as done" 1 \
  "The next migration between them is 0.5.0" replay_run "$RUN1"

# B3 — the second run, and the first time a step ever follows a step. The
# sweep caller run one created is a file run two did not plan to touch, and
# the only thing that may move in it is the pin the ref pass rewrites.
SWEEP_AFTER_RUN1="$TMP/bshoplong-sweep-run1"
sweep_of bshoplong >"$SWEEP_AFTER_RUN1"

RUN2="$TMP/bshoplong-run2"
capture_run "$RUN2" in_consumer bshoplong --fix --source "$SRC" 0.7.8

check "the next run from the new pin performs the second rung" 1 \
  "0.4.1 -> 0.5.0 done, including the applied step for 0.5.0" replay_run "$RUN2"
check "the second rung names the third as what comes next" 1 \
  "The next migration between them is 0.6.0" replay_run "$RUN2"
check "the second run leaves the pin at the second rung" 1 \
  "THIS RUN LEAVES THE PIN AT 0.5.0" replay_run "$RUN2"
check_absent "the second run does not report the requested move as done either" 1 \
  "0.7.8 done" replay_run "$RUN2"
check "every ref now reads the second rung, the created caller included" 0 \
  "$((PIN_COUNT + 1)) 0.5.0" refs bshoplong
check_absent "no ref is left at the first rung" 0 "0.4.1" refs bshoplong
# The sweep caller is run one's file with its pin moved and NOTHING else: run
# two writes no consumer byte, so a build whose second step reached for this
# file — re-writing the stub, re-relocating a cron, appending a second with: —
# fails here even though every ref assertion above would still pass.
sweep_run1_repinned() { sed 's|labels-sweep\.yml@0\.4\.1|labels-sweep.yml@0.5.0|' "$SWEEP_AFTER_RUN1"; }
sweep_diff_run1_to_run2() {
  diff <(sweep_run1_repinned) <(sweep_of bshoplong) && echo "identical-but-for-the-pin"
}
check "run two moved the sweep caller's pin and not one other byte of it" 0 \
  "identical-but-for-the-pin" sweep_diff_run1_to_run2

# C1 — the third run, and the first release in which three applied steps can
# be climbed one per invocation (#605 H9). 0.6.0 writes no consumer byte of
# its own, so the caller created by run one may differ only in its pin again.
SWEEP_AFTER_RUN2="$TMP/bshoplong-sweep-run2"
sweep_of bshoplong >"$SWEEP_AFTER_RUN2"

RUN3="$TMP/bshoplong-run3"
capture_run "$RUN3" in_consumer bshoplong --fix --source "$SRC" 0.7.8

check "the third run performs the third rung" 1 \
  "0.5.0 -> 0.6.0 done, including the applied step for 0.6.0" replay_run "$RUN3"
check "the third run leaves the pin at the third rung" 1 \
  "THIS RUN LEAVES THE PIN AT 0.6.0" replay_run "$RUN3"
check "the third rung names 0.7.0 as what comes next" 1 \
  "The next migration between them is 0.7.0" replay_run "$RUN3"
check_absent "the third run does not report the requested move as done" 1 \
  "0.7.8 done" replay_run "$RUN3"
check "every ref now reads the third rung, the created caller included" 0 \
  "$((PIN_COUNT + 1)) 0.6.0" refs bshoplong
check_absent "no ref is left at the second rung" 0 "0.5.0" refs bshoplong
sweep_run2_repinned() { sed 's|labels-sweep\.yml@0\.5\.0|labels-sweep.yml@0.6.0|' "$SWEEP_AFTER_RUN2"; }
sweep_diff_run2_to_run3() {
  diff <(sweep_run2_repinned) <(sweep_of bshoplong) && echo "identical-but-for-the-pin"
}
check "run three moved the sweep caller's pin and not one other byte of it" 0 \
  "identical-but-for-the-pin" sweep_diff_run2_to_run3

# The FOURTH rung, which exists because 0.7.0 gained a step (#610): the tag
# run three named as what comes next is now climbable, so this consumer walks
# 0.3.0 -> 0.4.1 -> 0.5.0 -> 0.6.0 -> 0.7.0 one rung per invocation. The block
# keeps the two properties it exists for — no run climbs two rungs, and a run
# writes no consumer byte it did not plan — and 0.7.0 writing none is exactly
# what the sweep-caller diff measures here.
SWEEP_AFTER_RUN3="$TMP/bshoplong-sweep-run3"
sweep_of bshoplong >"$SWEEP_AFTER_RUN3"

RUN4="$TMP/bshoplong-run4"
capture_run "$RUN4" in_consumer bshoplong --fix --source "$SRC" 0.7.8

check "the fourth run performs the fourth rung" 1 \
  "0.6.0 -> 0.7.0 done, including the applied step for 0.7.0" replay_run "$RUN4"
check "the fourth run leaves the pin at the fourth rung" 1 \
  "THIS RUN LEAVES THE PIN AT 0.7.0" replay_run "$RUN4"
check_absent "the fourth run does not report the requested move as done" 1 \
  "0.7.8 done" replay_run "$RUN4"
check "every ref now reads the fourth rung, the created caller included" 0 \
  "$((PIN_COUNT + 1)) 0.7.0" refs bshoplong
check_absent "no ref is left at the third rung" 0 "0.6.0" refs bshoplong
sweep_run3_repinned() { sed 's|labels-sweep\.yml@0\.6\.0|labels-sweep.yml@0.7.0|' "$SWEEP_AFTER_RUN3"; }
sweep_diff_run3_to_run4() {
  diff <(sweep_run3_repinned) <(sweep_of bshoplong) && echo "identical-but-for-the-pin"
}
check "run four moved the sweep caller's pin and not one other byte of it" 0 \
  "identical-but-for-the-pin" sweep_diff_run3_to_run4

# --- A3: an unmechanised first crossed tag still refuses, unchanged ---------
#
# cast at 0.1.0 is the honest measurement of what this issue does NOT buy: its
# first crossed tag is 0.2.0, which has no step, so the tag mechanised here is
# not reached and the refusal is the one that shipped before it existed.
split_consumer castold 0.1.0 cast_caller
check "an unmechanised first crossed tag refuses the whole move" 1 \
  "crosses 3 migration(s)" in_consumer castold --check --source "$SRC" 0.4.1
check "the refusal names the unmechanised tag it stops at" 1 \
  "FIRST CROSSED TAG: 0.2.0" in_consumer castold --check --source "$SRC" 0.4.1
check "the refusal still says the crossing is hand-only" 1 \
  "THE CROSSING IS HAND-ONLY" in_consumer castold --check --source "$SRC" 0.4.1
check_absent "no applied step is announced for an unmechanised tag" 1 \
  "APPLIED STEP" in_consumer castold --check --source "$SRC" 0.4.1
check_absent "no anchoring complaint is made about a tree never analysed" 1 \
  "CANNOT RUN ON THIS TREE" in_consumer castold --check --source "$SRC" 0.4.1
check_absent "a mechanised tag deeper in the interval does not leak a step" 1 \
  "THE PLAN" in_consumer castold --check --source "$SRC" 0.4.1
unchanged "the unmechanised refusal leaves the WHOLE tree byte-identical (--check)" \
  "$TMP/castold" in_consumer castold --check --source "$SRC" 0.4.1
unchanged "the unmechanised refusal leaves the WHOLE tree byte-identical (--fix)" \
  "$TMP/castold" in_consumer castold --fix --source "$SRC" 0.4.1

# --- D5: the consumer's own routing rides onto the new caller ---------------

named_caller() {
  cat <<EOF
name: board
on:
  schedule: [{cron: "17 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  issues: write
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
    with: { runner: '["self-hosted","ci-runner"]' }
EOF
}
split_consumer named 0.3.0 named_caller
check "a caller not named labels carries its name onto the sweep caller" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer named --fix --source "$SRC" 0.4.1
# Both keys on ONE flow mapping: the guide says not to repeat `with:`, and a
# routing value that is itself a quoted JSON list is why the reader splitting
# that mapping has to know about quotes and brackets.
check "the sweep caller carries the name and the runner in one with: mapping" 0 \
  "    with: { pr_workflow_name: 'board', runner: '[\"self-hosted\",\"ci-runner\"]' }" \
  sweep_of named
check "the routed sweep caller keeps the consumer's own cadence" 0 \
  '  schedule: [{cron: "17 * * * *"}]' sweep_of named

# The insert path: cast's permission block has no `actions:` key at all, so
# the grant is an insertion rather than a rewrite. A step that only knows how
# to rewrite silently leaves that board's trigger job red on every event.
split_consumer noactions 0.3.0 cast_caller
check "--check calls the missing grant an insertion, not a rewrite" 0 \
  "insert after line" in_consumer noactions --check --source "$SRC" 0.4.1
check "a permissions block with no actions key gains one" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer noactions --fix --source "$SRC" 0.4.1
check "the inserted grant is actions: write" 0 "  actions: write" caller_of noactions
check "the actions key appears exactly once after an insert" 0 "1" \
  occurrences noactions/.github/workflows/labels.yml "actions:"
check "the keys the block already had are still there" 0 "  pull-requests: write" \
  caller_of noactions

# The routing read looks at the whole job, not the line after the pin. A
# caller writing `secrets: inherit` between its `uses:` and its `with:` is
# ordinary, and the failure a reader that stopped early produces is the silent
# one: no routing carried, and nothing said about it.
secrets_caller() {
  cat <<EOF
name: board
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
    secrets: inherit
    with: { runner: '"ubuntu-22.04"' }
EOF
}
split_consumer secretsfirst 0.3.0 secrets_caller
check "routing is carried past an intervening job key" 0 "0.3.0 -> 0.4.1 done" \
  in_consumer secretsfirst --fix --source "$SRC" 0.4.1
check "the runner behind secrets: inherit still reached the sweep caller" 0 \
  "    with: { pr_workflow_name: 'board', runner: '\"ubuntu-22.04\"' }" \
  sweep_of secretsfirst

# ...and a comment at the on: block's own indent does not end the scan that
# looks for a dispatch's inputs. This tree must still refuse.
commented_inputs_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  # why this board keeps a dispatch of its own
    inputs:
      why:
        type: string
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer commentedinputs 0.3.0 commented_inputs_caller
check "a comment does not hide a dispatch's inputs from the refusal" 1 \
  "dispatch inputs with it" in_consumer commentedinputs --check --source "$SRC" 0.4.1
unchanged "the commented-inputs refusal writes nothing" "$TMP/commentedinputs" \
  in_consumer commentedinputs --fix --source "$SRC" 0.4.1

# ...and a `with:` written ABOVE the `uses:` is the same failure with the
# order reversed (claude-bot §1). A job is a YAML mapping and its keys are
# unordered, so this file is as ordinary as the one above; a scan that starts
# at the pin line reads no routing, says nothing about reading none, and skips
# the sweep_workflow guard on the way past. The consumer's sweep then runs on
# the default runner — on a runner-isolated board, on no runner at all.
withfirst_caller() {
  cat <<EOF
name: board
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    with: { runner: '["self-hosted"]' }
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer withfirst 0.3.0 withfirst_caller
check "--check names routing declared above the pin line" 0 \
  "the routing this tree already declares" \
  in_consumer withfirst --check --source "$SRC" 0.4.1
check "a with: above the uses: is still the job's routing" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer withfirst --fix --source "$SRC" 0.4.1
check "the runner declared before the pin reached the sweep caller" 0 \
  "    with: { pr_workflow_name: 'board', runner: '[\"self-hosted\"]' }" \
  sweep_of withfirst

# The same ordering with the guard behind it: a consumer already routing the
# trigger job at a sweep caller of its own name must still be refused, and a
# scan that never reaches the `with:` never reaches the guard either.
sweepfirst_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    with: { sweep_workflow: board-sweep.yml }
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer sweepfirst 0.3.0 sweepfirst_caller
check "a sweep_workflow declared above the pin still refuses" 1 \
  "sweep caller named board-sweep.yml" \
  in_consumer sweepfirst --check --source "$SRC" 0.4.1
unchanged "the routed-elsewhere refusal writes nothing" "$TMP/sweepfirst" \
  in_consumer sweepfirst --fix --source "$SRC" 0.4.1

# --- a labels caller carrying a SECOND ceremony pin -------------------------
#
# The ref pass rewrites every enumerated pin in the file; the step's plan
# named one of them. A walker told about one line sees the other as a change
# the plan never named — the rollback is right, but the run tells the operator
# this is a bug in ceremony-upgrade and asks them to report it, for a tree
# they are entitled to have (claude-bot §2). The suite's own consumer() puts
# two ceremony pins in ci.yml, so a multi-pin file is nothing unusual.
twopin_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: heavy-duty/ceremony/actions/docs-sync@$ref
EOF
}
split_consumer twopins 0.3.0 twopin_caller
check "a second ceremony pin in the labels caller does not fault the step" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer twopins --fix --source "$SRC" 0.4.1
check "both ceremony pins in that file moved to the crossed tag" 0 \
  "$((PIN_COUNT + 2)) 0.4.1" refs twopins
check "the second pin is at the crossed tag too" 0 \
  "      - uses: heavy-duty/ceremony/actions/docs-sync@0.4.1" caller_of twopins
check_absent "the multi-pin caller still lost its schedule" 0 "schedule:" \
  caller_of twopins
check "the multi-pin caller still gained the grant" 0 "  actions: write" \
  caller_of twopins
# The FALSE DIAGNOSIS is the damage, and it is asserted as an absence on a
# fixture of its own — a second --fix over the tree above would be a different
# move against a tree already at the crossed tag. What this rejects is the run
# printing ceremony's own "this is a bug in ceremony-upgrade … please report
# it" over a shape ceremony handles.
split_consumer twopinsagain 0.3.0 twopin_caller
check_absent "no fault is announced over a tree the command handles" 0 \
  "FAULT" in_consumer twopinsagain --fix --source "$SRC" 0.4.1
split_consumer twopinsonce 0.3.0 twopin_caller
check_absent "and the operator is not sent to file a ceremony bug" 0 \
  "Please report it against" in_consumer twopinsonce --fix --source "$SRC" 0.4.1

# --- D5: a workflow name is a YAML scalar, and it is encoded as one ---------
#
# `name: "labels: private"` is a valid workflow name. Carried raw into the
# flow mapping the sweep caller is routed with, the colon opens a nested
# mapping and what the consumer gets is not a differently-named sweep caller
# but an unparseable one (codex-bot §3).
quoted_name_caller() {
  cat <<EOF
name: "labels: private # board"
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer quotedname 0.3.0 quoted_name_caller
check "a quoted name carrying punctuation is carried, not refused" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer quotedname --fix --source "$SRC" 0.4.1
check "the name is written as a quoted scalar the flow mapping can hold" 0 \
  "    with: { pr_workflow_name: 'labels: private # board' }" \
  sweep_of quotedname
check_absent "the raw scalar is not what landed" 0 \
  "pr_workflow_name: labels: private" sweep_of quotedname
# The quote style that has no escapes but the doubled quote is the one that
# cannot be got wrong, so a name carrying one is doubled rather than dropped.
apostrophe_name_caller() {
  cat <<EOF
name: "the board's labels"
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer aponame 0.3.0 apostrophe_name_caller
check "a name carrying an apostrophe is carried, not refused" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer aponame --fix --source "$SRC" 0.4.1
check "a name carrying an apostrophe is escaped by doubling it" 0 \
  "    with: { pr_workflow_name: 'the board''s labels' }" \
  sweep_of aponame
# ...and the ordinary name is quoted too, because there is no plain path left
# to take. What the sweep caller is handed has to be the consumer's name AND
# its type, and a plain scalar decides the second one by what the characters
# happen to look like (codex-bot, round 2).
check "an ordinary name is quoted as well, there being no plain path" 0 \
  "    with: { pr_workflow_name: 'board', runner: '\"ubuntu-22.04\"' }" \
  sweep_of secretsfirst

# A NAME YAML WOULD RESOLVE AS SOMETHING OTHER THAN A STRING. `name: "true"`
# is a legal workflow name; written plain into the flow mapping it comes back
# a boolean, and `labels-sweep.yml` declares pr_workflow_name `type: string`.
# The consumer is then handed neither their name nor its type — by a step
# whose whole job at this key is to carry the one it read.
# The name comes from $implicit_name, the pin from split_consumer's own $ref,
# so one fixture builder serves every implicit-typed name below.
implicit_name_caller() {
  cat <<EOF
name: "$implicit_name"
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
implicit_name="true"
split_consumer booname 0.3.0 implicit_name_caller
check "a name YAML would read as a boolean is carried, not refused" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer booname --fix --source "$SRC" 0.4.1
check "a boolean-looking name is quoted into the flow mapping" 0 \
  "    with: { pr_workflow_name: 'true' }" sweep_of booname
check_absent "the bare boolean is not what landed" 0 \
  "pr_workflow_name: true" sweep_of booname
implicit_name="123"
split_consumer numname 0.3.0 implicit_name_caller
check "a name YAML would read as an integer is carried too" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer numname --fix --source "$SRC" 0.4.1
check "an integer-looking name is quoted into the flow mapping" 0 \
  "    with: { pr_workflow_name: '123' }" sweep_of numname
check_absent "the bare integer is not what landed" 0 \
  "pr_workflow_name: 123" sweep_of numname

# THE TYPE IS ASSERTED BY A PARSER, not by the bytes. The rows above grade
# what this step wrote; these grade what a YAML reader makes of it, which is
# the thing the consumer's board actually depends on. yq is the suite's
# existing instrument for that (test/labels-scope.test.sh, #130) —
# preinstalled on ubuntu-latest, optional locally, and never silently skipped
# in CI because ci.yml sets CEREMONY_REQUIRE_YQ.
if command -v yq >/dev/null 2>&1; then
  # The job key is not hardcoded: the stub names it, and this reads back
  # whatever the published block calls it.
  carried_tag() { yq '.jobs | to_entries | .[0].value.with.pr_workflow_name | tag' "$TMP/$1/.github/workflows/labels-sweep.yml"; }
  carried_name() { yq '.jobs | to_entries | .[0].value.with.pr_workflow_name' "$TMP/$1/.github/workflows/labels-sweep.yml"; }
  check "the carried name parses back as a string, not a boolean" 0 \
    "!!str" carried_tag booname
  check "and reads back as the name the caller declared" 0 \
    "true" carried_name booname
  check "an integer-looking name parses back as a string too" 0 \
    "!!str" carried_tag numname
  check "and reads back as the digits the caller declared" 0 \
    "123" carried_name numname
  # Not vacuous: the same probe on a name nobody could mistake for a scalar
  # of another type still says !!str, so the two rows above are graded by a
  # probe that is reading the emitted file and not returning a constant.
  check "the punctuated name parses back as a string as well" 0 \
    "!!str" carried_tag quotedname
  check "and round-trips to the caller's own name byte for byte" 0 \
    "labels: private # board" carried_name quotedname
elif [ -n "${CEREMONY_REQUIRE_YQ:-}" ]; then
  echo "FAIL: CEREMONY_REQUIRE_YQ is set but yq is missing — the carried-name type cases did not run"
  FAIL=$((FAIL + 1))
else
  echo "SKIP: yq not found — the carried-name type cases not exercised"
fi

# --- A7: every shape the step cannot anchor is a refusal --------------------
#
# Each of these is a tree where a best guess is available and wrong. The
# refusal is the ORDINARY crossed-migration refusal — the hand procedure is
# still the answer for this tree — plus a section naming what could not be
# anchored, so the reader is not sent to audit the whole file for it.

split_consumer sweeppresent 0.3.0 barbershop_caller
# No ceremony pin in it: the fixture is about the file EXISTING, and a pin
# here would make the row pass on the mixed-refs fault instead.
printf 'name: labels-sweep\non: {workflow_dispatch: {}}\njobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' \
  >"$TMP/sweeppresent/.github/workflows/labels-sweep.yml"
check "an existing sweep caller is a refusal, not a merge" 1 \
  "already exists. This step creates the sweep" \
  in_consumer sweeppresent --check --source "$SRC" 0.4.1
check "that refusal is still the crossed-migration refusal" 1 \
  "THE CROSSING IS HAND-ONLY" in_consumer sweeppresent --check --source "$SRC" 0.4.1
unchanged "the existing-sweep-caller refusal writes nothing" "$TMP/sweeppresent" \
  in_consumer sweeppresent --fix --source "$SRC" 0.4.1
# The shorter move is the LAST line before the tree verdict, so on a step
# refusal it reads as the recommended exit when the hand procedure above it
# is the one that crosses the tag (claude-bot). It keeps its bytes — a reader
# and this suite both grep them — and gains a sentence saying what it is not.
check "a step refusal still emits its shorter move" 1 \
  "SHORTER MOVE:" in_consumer sweeppresent --check --source "$SRC" 0.4.1
check "and says that move stops below the shape that refused" 1 \
  "stops BELOW the shape named above rather than crossing it" \
  in_consumer sweeppresent --check --source "$SRC" 0.4.1
check "naming the tag the hand procedure is still owed for" 1 \
  "The hand procedure is what crosses 0.4.1." \
  in_consumer sweeppresent --check --source "$SRC" 0.4.1
# Not vacuous, and this is the conditional: a refusal that reached no step —
# an ordinary crossed migration with a shorter move of its own — carries the
# line without the sentence, because there is no shape above it to stop below.
check_absent "an ordinary crossed migration's shorter move carries no such note" 1 \
  "stops BELOW the shape named above" \
  in_consumer stepable --check --source "$SRC" 0.7.8

twoschedule_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  schedule: [{cron: "0 * * * *"}]
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer twoschedules 0.3.0 twoschedule_caller
check "two schedule keys are a refusal rather than a pick" 1 \
  "declares 'schedule:' 2 times" \
  in_consumer twoschedules --check --source "$SRC" 0.4.1
unchanged "the two-schedule refusal writes nothing" "$TMP/twoschedules" \
  in_consumer twoschedules --fix --source "$SRC" 0.4.1

inputs_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
    inputs:
      why:
        description: why this board is being swept by hand
        type: string
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer dispatchinputs 0.3.0 inputs_caller
check "a workflow_dispatch carrying inputs is not silently deleted" 1 \
  "would delete the" in_consumer dispatchinputs --check --source "$SRC" 0.4.1
check "that refusal names the consumer's own dispatch inputs" 1 \
  "dispatch inputs with it" in_consumer dispatchinputs --check --source "$SRC" 0.4.1
unchanged "the dispatch-inputs refusal writes nothing" "$TMP/dispatchinputs" \
  in_consumer dispatchinputs --fix --source "$SRC" 0.4.1
check "the consumer's dispatch input is still there afterwards" 0 \
  "      why:" caller_of dispatchinputs

noperms_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer noperms 0.3.0 noperms_caller
check "a caller with no permissions block is a refusal" 1 \
  "has no top-level 'permissions:' block" \
  in_consumer noperms --check --source "$SRC" 0.4.1
check "that refusal says why the block is not created" 1 \
  "sets every unnamed one to none" \
  in_consumer noperms --check --source "$SRC" 0.4.1
unchanged "the no-permissions refusal writes nothing" "$TMP/noperms" \
  in_consumer noperms --fix --source "$SRC" 0.4.1

# A CALLER WHOSE ONLY TRIGGERS ARE THE TWO THIS STEP RELOCATES (claude-bot
# §1). Both keys are triggers, so performing the plan on this tree leaves
# `on:` with no value: actionlint's "string should not be empty", a file
# GitHub rejects, and with it the trigger job that dispatches the sweep
# caller the same run just created. It is the one way this step reaches exit
# 0 having broken a board, and it gets there by doing exactly what the plan
# said, so it joins the refusals rather than being fixed up afterwards.
onlytriggers_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
permissions:
  contents: read
  issues: write
  pull-requests: write
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer onlytriggers 0.3.0 onlytriggers_caller
check "a caller left with no trigger at all is a refusal" 1 \
  "declares nothing but what this step relocates" \
  in_consumer onlytriggers --check --source "$SRC" 0.4.1
check "that refusal names both keys it would have taken" 1 \
  "the 'schedule:' at line 3 and the bare 'workflow_dispatch:' at line 4" \
  in_consumer onlytriggers --check --source "$SRC" 0.4.1
check "and says what the emptied on: block would be" 1 \
  "one GitHub cannot parse" \
  in_consumer onlytriggers --check --source "$SRC" 0.4.1
check "it is still the ordinary crossed-migration refusal" 1 \
  "THE CROSSING IS HAND-ONLY" in_consumer onlytriggers --check --source "$SRC" 0.4.1
unchanged "the no-trigger-left refusal writes nothing" "$TMP/onlytriggers" \
  in_consumer onlytriggers --fix --source "$SRC" 0.4.1
# The `done` that build reaches is what the refusal replaces, so its absence
# is asserted too: a guard that refused and then carried on would satisfy
# every row above.
check_absent "no such tree is reported as migrated" 1 \
  "0.3.0 -> 0.4.1 done" in_consumer onlytriggers --fix --source "$SRC" 0.4.1
# NOT VACUOUS, and this is the row that keeps the guard a guard: the same
# caller with ONE more trigger completes, because something survives the
# deletions. A guard counting the keys it deletes rather than the keys that
# remain would refuse here too and take every real consumer with it — both
# measured ones carry pull_request_target.
onetrigger_caller() {
  onlytriggers_caller | sed 's/^  workflow_dispatch:$/  workflow_dispatch:\n  pull_request_target:\n    types: [opened]/'
}
split_consumer onetrigger 0.3.0 onetrigger_caller
check "one surviving trigger is enough for the step to run" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer onetrigger --fix --source "$SRC" 0.4.1
check "and the trigger that survived is still there" 0 \
  "  pull_request_target:" caller_of onetrigger
check "while the relocated cadence reached the sweep caller" 0 \
  '  schedule: [{cron: "*/15 * * * *"}]' sweep_of onetrigger
# The dispatch-only half of the same count: with no bare workflow_dispatch to
# delete, one surviving key is the schedule alone — which is deleted — so the
# arithmetic has to read one deletion, not two.
sched_only_caller() {
  onlytriggers_caller | sed '/^  workflow_dispatch:$/d'
}
split_consumer schedonly 0.3.0 sched_only_caller
check "a schedule-only caller is a refusal on the same count" 1 \
  "declares nothing but what this step relocates" \
  in_consumer schedonly --check --source "$SRC" 0.4.1
check_absent "and it does not name a dispatch it never found" 1 \
  "bare 'workflow_dispatch:' at line" \
  in_consumer schedonly --check --source "$SRC" 0.4.1
unchanged "the schedule-only refusal writes nothing" "$TMP/schedonly" \
  in_consumer schedonly --fix --source "$SRC" 0.4.1

blockwith_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
    with:
      runner: '"ubuntu-22.04"'
EOF
}
split_consumer badwith 0.3.0 blockwith_caller
check "a with: block the step cannot read is a refusal" 1 \
  "writes 'with:' as a block" in_consumer badwith --check --source "$SRC" 0.4.1
check "that refusal says it will not carry routing it did not understand" 1 \
  "single-line flow mapping" in_consumer badwith --check --source "$SRC" 0.4.1
unchanged "the unreadable-with refusal writes nothing" "$TMP/badwith" \
  in_consumer badwith --fix --source "$SRC" 0.4.1

# The OTHER spelling of the sweep caller. GitHub reads `.yaml` in
# .github/workflows/ as readily as `.yml`, and this file's own enumeration
# already knows both — so an operator who wrote labels-sweep.yaml by hand and
# then reached for the command got a second sweep caller written beside it at
# exit 0. Two callers, both scheduled: DOUBLE SWEEPS, which is the damage this
# tag is first on the ladder to prevent (claude-bot §3).
split_consumer sweepyaml 0.3.0 barbershop_caller
printf 'name: labels-sweep\non: {workflow_dispatch: {}}\njobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' \
  >"$TMP/sweepyaml/.github/workflows/labels-sweep.yaml"
check "a sweep caller spelled .yaml is a refusal too" 1 \
  ".github/workflows/labels-sweep.yaml already exists" \
  in_consumer sweepyaml --check --source "$SRC" 0.4.1
unchanged "the .yaml-sweep-caller refusal writes nothing" "$TMP/sweepyaml" \
  in_consumer sweepyaml --fix --source "$SRC" 0.4.1
sweep_files() {
  printf '[%s]\n' "$(
    find "$TMP/$1/.github/workflows" -name 'labels-sweep.*' -printf '%f\n' |
      LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'
  )"
}
check "no second sweep caller was written beside the one already there" 0 \
  "[labels-sweep.yaml]" sweep_files sweepyaml

# --- the permission grant has exactly two anchored shapes -------------------
#
# `actions: read` to rewrite, or no `actions:` key to insert after. A step
# reading only the LINE the key is on substitutes whatever value is there and
# leaves a duplicate key duplicated (codex-bot §2), so the value is read and
# every other shape refuses with the value it found named.
# The pin comes from split_consumer's own `ref`, as every builder here does;
# the grant's value comes from $ACTIONS_VALUE, set beside each fixture.
actions_valued_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: $ACTIONS_VALUE
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
ACTIONS_VALUE="none"
split_consumer actionsnone 0.3.0 actions_valued_caller
check "a grant this step did not write is not overwritten" 1 \
  "already grants 'actions: none'" \
  in_consumer actionsnone --check --source "$SRC" 0.4.1
check "that refusal says which two shapes it does anchor" 1 \
  "rewrites an 'actions: read' grant, or inserts the key where" \
  in_consumer actionsnone --check --source "$SRC" 0.4.1
unchanged "the foreign-grant refusal writes nothing" "$TMP/actionsnone" \
  in_consumer actionsnone --fix --source "$SRC" 0.4.1

# A write already granted by hand is the same refusal, and deliberately so:
# treating it as satisfied is a third shape this step does not have, and the
# hand that granted it is the one that knows why.
ACTIONS_VALUE="write"
split_consumer actionswrite 0.3.0 actions_valued_caller
check "a write already granted by hand is left alone, not rewritten" 1 \
  "already grants 'actions: write'" \
  in_consumer actionswrite --check --source "$SRC" 0.4.1
unchanged "the already-granted refusal writes nothing" "$TMP/actionswrite" \
  in_consumer actionswrite --fix --source "$SRC" 0.4.1

# A QUOTED `read` IS THE SAME REFUSAL, and the case the message has to work
# hardest for: YAML resolves `'read'` and `read` alike, so a sentence saying
# the grant differs from the one this step rewrites shows the reader the same
# four bytes on both sides of it (claude-bot). The refusal is the
# conservative call and stays; what it says is that the comparison is on the
# bytes.
ACTIONS_VALUE="'read'"
split_consumer actionsquoted 0.3.0 actions_valued_caller
check "a quoted read grant is a refusal, not a rewrite" 1 \
  "already grants 'actions: 'read''" \
  in_consumer actionsquoted --check --source "$SRC" 0.4.1
check "and the refusal says the comparison is on the bytes" 1 \
  "THE VALUE IS COMPARED AS WRITTEN" \
  in_consumer actionsquoted --check --source "$SRC" 0.4.1
check "it names the shape that makes the sentence read oddly" 1 \
  "a quoted 'read' is not the" \
  in_consumer actionsquoted --check --source "$SRC" 0.4.1
unchanged "the quoted-read refusal writes nothing" "$TMP/actionsquoted" \
  in_consumer actionsquoted --fix --source "$SRC" 0.4.1
# Not vacuous: that clause belongs to this refusal and not to every
# diagnostic the command prints, so the plain crossed-migration refusal —
# which reaches no step at all — must not carry it.
check_absent "the byte-comparison note belongs to the grant refusal alone" 1 \
  "THE VALUE IS COMPARED AS WRITTEN" \
  in_consumer ancient --check --source "$SRC" 0.7.7

twoactions_caller() {
  cat <<EOF
name: labels
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer twoactions 0.3.0 twoactions_caller
check "two actions keys are a refusal rather than a rewrite of the last" 1 \
  "block declares 'actions:' 2" \
  in_consumer twoactions --check --source "$SRC" 0.4.1
unchanged "the duplicate-grant refusal writes nothing" "$TMP/twoactions" \
  in_consumer twoactions --fix --source "$SRC" 0.4.1

# A double-quoted name carrying a backslash is the one name shape that
# refuses: reading it means implementing YAML's double-quoted escapes, and a
# step that guessed would tell the sweep caller the wrong name for the board.
escaped_name_caller() {
  cat <<EOF
name: "labels \\"private\\""
on:
  schedule: [{cron: "*/15 * * * *"}]
  workflow_dispatch:
  pull_request_target:
    types: [opened]
permissions:
  contents: read
  actions: read
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@$ref
EOF
}
split_consumer escapedname 0.3.0 escaped_name_caller
check "a name this step cannot decode is a refusal, not a guess" 1 \
  "backslash escape" in_consumer escapedname --check --source "$SRC" 0.4.1
unchanged "the undecodable-name refusal writes nothing" "$TMP/escapedname" \
  in_consumer escapedname --fix --source "$SRC" 0.4.1

# --- A8: the stub has one source, and the step really reads it --------------
#
# The grep is the structural half — no copy of the block under bin/, and the
# occurrences are the ones this repository already had. The altered-source row
# is the behavioural half: point the step at a guide whose block has been
# changed and the changed bytes must land in the consumer, which no embedded
# default and no cached copy can produce.
sweep_stub_sites() {
  printf '[%s]\n' "$(git -C "$ROOT" grep -lF 'name: labels-sweep' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
}
check "the caller stub is declared in the guide, the reusable, the dogfood caller and the fixtures" 0 \
  "[.github/workflows/labels-sweep.yml .github/workflows/self-labels-sweep.yml docs/CONSUMERS.md test/ceremony-upgrade.test.sh test/fixtures/incubator-callers/.github/workflows/labels-sweep.yml]" \
  sweep_stub_sites
bin_stub_copies() {
  printf '[%s]\n' "$(git -C "$ROOT" grep -lF 'name: labels-sweep' -- bin | tr '\n' ' ' | sed 's/ $//')"
}
check "no copy of the caller stub ships under bin/" 0 "[]" bin_stub_copies

SRC_ALTERED="$TMP/src-altered"
cp -pPR "$SRC" "$SRC_ALTERED"
sed -i 's|^  # A manual full-board sweep\..*$|  # ALTERED IN THE SOURCE GUIDE, and only there.|' \
  "$SRC_ALTERED/docs/CONSUMERS.md"
split_consumer altered 0.3.0 barbershop_caller
check "the step writes the guide it was pointed at" 0 "0.3.0 -> 0.4.1 done" \
  in_consumer altered --fix --source "$SRC_ALTERED" 0.4.1
check "the altered guide's bytes are the ones that landed" 0 \
  "  # ALTERED IN THE SOURCE GUIDE, and only there." sweep_of altered
check_absent "the unaltered comment did not come from anywhere else" 0 \
  "A manual full-board sweep" sweep_of altered

# ...and a source tree whose guide has no such block fails loudly rather than
# falling back to a default. This is the row that would catch an embedded copy
# added later "just in case the read fails".
SRC_NOSTUB="$TMP/src-nostub"
cp -pPR "$SRC" "$SRC_NOSTUB"
printf '# Consumers\n\nnothing published here.\n' >"$SRC_NOSTUB/docs/CONSUMERS.md"
split_consumer nostub 0.3.0 barbershop_caller
check "a guide with no sweep-caller stub is a loud failure" 1 \
  "carries no sweep-caller stub" \
  in_consumer nostub --check --source "$SRC_NOSTUB" 0.4.1
check "that failure says there is no copy to fall back to" 1 \
  "will not write one it did not read" \
  in_consumer nostub --check --source "$SRC_NOSTUB" 0.4.1
unchanged "a missing stub writes nothing" "$TMP/nostub" \
  in_consumer nostub --fix --source "$SRC_NOSTUB" 0.4.1

# The tag the guide is read AT, graded where it is observable. The move asked
# for is 0.3.0 -> 0.7.8 and the crossed tag is 0.4.1, so the ladder is fetched
# at the target and the caller stub at the crossing — two different refs in
# one run. A build that read the stub at the target, or at a default branch,
# writes a consumer the bytes of a tag the crossing is not about.
split_consumer fetchguide 0.3.0 barbershop_caller
CURL_STUB_GUIDE="$SRC/docs/CONSUMERS.md"
export CURL_STUB_GUIDE
guide_urls() {
  local log="$TMP/curl-urls"
  : >"$log"
  (
    cd "$TMP/fetchguide" || return
    CURL_STUB=ok CURL_STUB_LOG="$log" bash "$SCRIPT" --check 0.7.8
  ) >/dev/null 2>&1
  grep 'CONSUMERS.md' "$log" || echo "no-guide-fetch"
}
check "the caller stub is fetched at the CROSSED tag" 0 \
  "https://raw.githubusercontent.com/heavy-duty/ceremony/0.4.1/docs/CONSUMERS.md" \
  guide_urls
check_absent "it is not fetched at the target that was asked for" 0 \
  "/0.7.8/docs/CONSUMERS.md" guide_urls
check_absent "and never from a branch" 0 "/main/docs/CONSUMERS.md" guide_urls

# --- A9: the rollback holds over the enlarged territory ---------------------
#
# The step writes two files the ref rewrite never touched, and docs-sync runs
# AFTER both. A rollback that only restores what the ref pass wrote leaves the
# sweep caller behind — a consumer whose board now has two callers, one of
# them pinned to a ref its own labels caller is not at.
write_src_guide "$SRC_SCAF"
split_consumer rollback 0.3.0 barbershop_caller
printf 'Our own template.\n\n<!-- ceremony:pr-template:start -->\n\nnever closed\n' \
  >"$TMP/rollback/.github/pull_request_template.md"
unchanged "a docs-sync refusal after an applied step rolls the WHOLE tree back" \
  "$TMP/rollback" in_consumer rollback --fix --source "$SRC_SCAF" 0.4.1
sweep_state() {
  if [ -e "$TMP/rollback/.github/workflows/labels-sweep.yml" ]; then
    echo "sweep-caller-left-behind"
  else
    echo "no-sweep-caller"
  fi
}
check "the rolled-back run left no sweep caller behind" 0 "no-sweep-caller" sweep_state
check "the rolled-back run left the cron where it was" 0 \
  '  schedule: [{cron: "*/15 * * * *"}] # advisory; the handoff label is the real wake' \
  caller_of rollback
check "the rolled-back run left the old permission grant alone" 0 \
  "  actions: read    # checkSuite.workflowRun read" caller_of rollback
check "the pins did not move under the rolled-back step" 0 "$PIN_COUNT 0.3.0" \
  refs rollback
check "the run said it rolled back" 1 "rolled back" \
  in_consumer rollback --fix --source "$SRC_SCAF" 0.4.1
# Not vacuous: with the marker closed the SAME move over the SAME source tree
# succeeds, so the row above is measuring a rollback and not an impossibility.
split_consumer rollback-ok 0.3.0 barbershop_caller
printf 'Our own template.\n\n<!-- ceremony:pr-template:start -->\nold\n<!-- ceremony:pr-template:end -->\n' \
  >"$TMP/rollback-ok/.github/pull_request_template.md"
check "the same move over the same source succeeds with the marker closed" 0 \
  "0.3.0 -> 0.4.1 done" in_consumer rollback-ok --fix --source "$SRC_SCAF" 0.4.1
check "and that run really did write the sweep caller" 0 \
  "labels-sweep.yml@0.4.1" sweep_of rollback-ok

# ============================================================================
# The applied step — 0.5.0, the crossing that asks this tree for nothing (#600)
# ============================================================================
#
# The ladder's second tag, and the first whose whole work is what the command
# already does for every move. That makes the assertions the inverse of
# 0.4.1's: there, the question was whether the announced bytes landed; here it
# is whether ANY byte landed that was not the pin.

# github_hashes <name> — every regular file under the consumer's .github/,
# path and content hash. The PATHS as well as the hashes, so a file this
# crossing created or deleted moves the list too.
github_hashes() {
  (cd "$TMP/$1" && find .github -type f | LC_ALL=C sort | while IFS= read -r p; do
    printf '%s  %s\n' "$(sha256sum <"$p" | cut -d' ' -f1)" "$p"
  done)
}
github_paths() {
  printf '[%s]\n' "$(
    (cd "$TMP/$1" && find .github \( -type f -o -type l \) | LC_ALL=C sort) |
      tr '\n' ' ' | sed 's/ $//'
  )"
}

# --- B1: the crossing completes and writes nothing under .github/ -----------
#
# The fixture is the POST-SPLIT barbershop shape at 0.4.1 — the tree the rung
# below this one leaves a consumer at — built by running that rung rather than
# hand-written, so what this row grades is the state the command itself
# produces and not a fixture author's idea of it.
split_consumer panelrows 0.3.0 barbershop_caller
check "the fixture is built by the rung below this one" 0 "0.3.0 -> 0.4.1 done" \
  in_consumer panelrows --fix --source "$SRC" 0.4.1

# --- B2: the plan, before the run that would make it stale ------------------
#
# plan_block — everything printed under THE PLAN, its own heading through the
# mirror line that closes it. The rows below grade the WHOLE block rather than
# grepping it, because the defect this criterion is written against prints
# nothing: `printf '%s\n' "${step_plan[@]}"` over an empty array emits a blank
# line, and a step that was an empty function passes every other row here.
plan_block() { # <name> <target>
  in_consumer "$1" --check --source "$SRC" "$2" 2>&1 |
    sed -n '/: THE PLAN$/,/then re-sync the doctrine mirror/p'
}
# Bracketed, so "not blank" is a positive assertion about a specific line
# rather than a substring that a blank line would also satisfy.
plan_line() { # <name> <target> <n> — the nth line after THE PLAN
  printf '[%s]\n' "$(plan_block "$1" "$2" | sed -n "$(($3 + 1))p")"
}
plan_blank_lines() { printf '[%s]\n' "$(plan_block "$1" "$2" | grep -c '^[[:space:]]*$')"; }

check "--check names 0.5.0 as an applied step and the tag it stops at" 0 \
  "0.5.0 is an APPLIED STEP, so this run performs 0.4.1 -> 0.5.0 and stops there" \
  in_consumer panelrows --check --source "$SRC" 0.5.0
check "the plan says the tag asks this tree for nothing" 0 \
  "no edit to this tree: 0.5.0 asks it for nothing" \
  in_consumer panelrows --check --source "$SRC" 0.5.0
check "the plan names the guide section that says why" 0 \
  'docs/CONSUMERS.md § "Labels automation" is where that is stated' \
  in_consumer panelrows --check --source "$SRC" 0.5.0
check "the plan says the row it does not write is optional and yours" 0 \
  "a reviewer set being yours to choose" \
  in_consumer panelrows --check --source "$SRC" 0.5.0
# THE EMPTY-ARRAY PRINT, ASSERTED DIRECTLY. Two lines are graded because the
# criterion's "immediately following THE PLAN" and the position the blank line
# actually lands at are not the same line: line 1 is the ref rewrite the
# generic plan always prints, and line 2 is the first of step_plan[] — the one
# an empty step turns into a blank. Both are pinned to their exact bytes.
check "the line immediately following THE PLAN is not blank" 0 \
  "[    rewrite $((PIN_COUNT + 1)) ceremony ref(s) from @0.4.1 to @0.5.0]" \
  plan_line panelrows 0.5.0 1
check "the step's own first plan line is not the empty-array blank" 0 \
  "[    no edit to this tree: 0.5.0 asks it for nothing. The tag makes the]" \
  plan_line panelrows 0.5.0 2
check "no line of the plan is blank" 0 "[0]" plan_blank_lines panelrows 0.5.0
unchanged "--check over a step that writes nothing writes nothing" \
  "$TMP/panelrows" in_consumer panelrows --check --source "$SRC" 0.5.0

# ...and now the crossing itself.
GH_BEFORE="$TMP/panelrows-github-before"
github_hashes panelrows >"$GH_BEFORE"
PATHS_BEFORE="$(github_paths panelrows)"

# Captured once, for the same reason the two-run climb above is: the rows
# grade one crossing, and a `check` that re-ran --fix would grade a second
# invocation over a tree the first one already moved.
CROSSING="$TMP/panelrows-crossing"
capture_run "$CROSSING" in_consumer panelrows --fix --source "$SRC" 0.5.0

check "the crossing completes and ends where it was asked to" 0 \
  "0.4.1 -> 0.5.0 done, including the applied step for 0.5.0" replay_run "$CROSSING"
check "the run that completes its whole move names the pin it leaves" 0 \
  "THIS RUN LEAVES THE PIN AT 0.5.0" replay_run "$CROSSING"
check_absent "and owes no remainder, the requested target being the crossed tag" 0 \
  "REMAINING:" replay_run "$CROSSING"
check "every ref reads the crossed tag afterwards" 0 "$((PIN_COUNT + 1)) 0.5.0" \
  refs panelrows
check_absent "no ref is left at the pin the run started from" 0 "0.4.1" refs panelrows

# THE CHANGED SET IS NAMED, NOT COUNTED (#597 A2, on the inverse claim). A row
# reading "5 files changed" is satisfied by five wrong files; the list is
# sorted, bracketed and exhaustive, so a superset — a step that helpfully
# wrote a panel[<login>]= row into .github/labels.conf, say — fails it, and so
# does a subset.
changed_github() {
  printf '[%s]\n' "$(
    diff "$GH_BEFORE" <(github_hashes panelrows) |
      sed -n 's/^[<>] [0-9a-f]*  //p' | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//'
  )"
}
check "the files that moved under .github/ are exactly the ref-carrying ones" 0 \
  "[.github/actions/vouch/action.yml .github/workflows/ci.yml .github/workflows/labels-sweep.yml .github/workflows/labels.yml .github/workflows/release.yml]" \
  changed_github
paths_now() { github_paths panelrows; }
check "no path under .github/ was created or deleted" 0 "$PATHS_BEFORE" paths_now
check "the labels caller keeps the grant the rung below wrote" 0 \
  "  actions: write" caller_of panelrows
check "the mirror is current after a step that wrote no tree edit" 0 \
  "is an exact mirror" in_consumer_docs_sync panelrows --check --source "$SRC"

# --- C2: 0.6.0's two-clause plan and mirror-only crossing (#605) -----------
#
# This source differs from the general fixture on purpose: RELEASES.md is in
# this tag's manifest, while the generic source is deliberately small. The
# crossing must learn that path from its own migration prose and leave the
# manifest to docs-sync, its only reader.
SRC_060="$TMP/src-060"
cp -pPR "$SRC" "$SRC_060"
printf 'RELEASES.md\n' >>"$SRC_060/docs/VENDORED.txt"
printf '# releases from the source tag\n' >"$SRC_060/RELEASES.md"

consumer doctrine060 0.5.0
check "0.6.0 is announced as an applied step" 0 \
  "0.6.0 is an APPLIED STEP, so this run performs 0.5.0 -> 0.6.0 and stops there" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check "the 0.6.0 check prints a plan" 0 "THE PLAN" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check_absent "the applied 0.6.0 check is not a fault" 0 "FAULT" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check_absent "the applied 0.6.0 check is not hand-only" 0 "THE CROSSING IS HAND-ONLY" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check "the plan names RELEASES.md as the crossing's edit" 0 \
  "edit .ceremony/RELEASES.md" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check "the plan names the existing mirror re-sync as its writer" 0 \
  "mirror re-sync at the end of this run" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check "the plan names docs-sync --fix as that mirror writer" 0 \
  "writes it through docs-sync --fix" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check "the mirror plan line names its guide section" 0 \
  'docs/CONSUMERS.md § "Doctrine mirror"' \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check "the separate plan clause says refs-not-closing becomes available" 0 \
  "refs-not-closing becomes available at this tag" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check "the refs clause says this command writes no caller" 0 \
  "this command writes no" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check "the refs clause joins that no-write promise to the optional caller" 0 \
  "caller for it; adopting .github/workflows/refs-guard.yml is your call" \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
check "the refs clause names the bootstrap guide section" 0 \
  'docs/CONSUMERS.md § "Bootstrap a new repo"' \
  in_consumer doctrine060 --check --source "$SRC_060" 0.6.0
unchanged "the 0.6.0 check leaves the whole tree byte-identical" \
  "$TMP/doctrine060" in_consumer doctrine060 --check --source "$SRC_060" 0.6.0

WORKFLOWS_060_BEFORE="$(github_paths doctrine060)"
CROSSING_060="$TMP/doctrine060-crossing"
capture_run "$CROSSING_060" \
  in_consumer doctrine060 --fix --source "$SRC_060" 0.6.0

check "the 0.6.0 crossing completes" 0 \
  "0.5.0 -> 0.6.0 done, including the applied step for 0.6.0" \
  replay_run "$CROSSING_060"
check "the completed crossing advances every ref" 0 "$PIN_COUNT 0.6.0" \
  refs doctrine060
check_absent "the completed crossing leaves no ref at 0.5.0" 0 "0.5.0" \
  refs doctrine060
check "docs-sync wrote RELEASES.md with the source tag's bytes" 0 \
  "# releases from the source tag" cat "$TMP/doctrine060/.ceremony/RELEASES.md"
check "the completed 0.6.0 mirror is exact" 0 "is an exact mirror" \
  in_consumer_docs_sync doctrine060 --check --source "$SRC_060"
check_absent "the completed crossing writes no refs-guard caller" 0 \
  "refs-guard.yml" github_paths doctrine060
paths_060_now() { github_paths doctrine060; }
check "the completed crossing leaves the workflow path set unchanged" 0 \
  "$WORKFLOWS_060_BEFORE" paths_060_now

# --- B5: a tag with no step still refuses, byte for byte --------------------
#
# MEASURED, NOT ARGUED. The claim is that this build changed nothing about an
# unmechanised crossing, and the only reading of that claim which cannot be
# satisfied by a sentence is the merged tree's own output beside this one's:
# `git archive` of 1c2ffd1 (#597's merge, the commit this issue is minted
# against) into a directory, one identical fixture each side, `diff` empty.
MERGED="$TMP/merged-1c2ffd1"
mkdir -p "$MERGED"
git -C "$ROOT" archive 1c2ffd1 | tar -x -C "$MERGED"
merged_script_present() {
  [ -x "$MERGED/bin/ceremony-upgrade" ] && echo "merged-tree-extracted"
}
check "the merged tree this is measured against was extracted" 0 \
  "merged-tree-extracted" merged_script_present

split_consumer castmerged 0.1.0 cast_caller
split_consumer castnow 0.1.0 cast_caller
refusal_from() { # <script> <fixture>
  (cd "$TMP/$2" && bash "$1" --check --source "$SRC" 0.5.0) 2>&1
}
refusal_diff() {
  diff \
    <(refusal_from "$MERGED/bin/ceremony-upgrade" castmerged) \
    <(refusal_from "$SCRIPT" castnow) &&
    echo "byte-identical-to-the-merged-tree"
}
check "the unmechanised refusal is byte-identical to the merged tree's" 0 \
  "byte-identical-to-the-merged-tree" refusal_diff
check "and it is a refusal, at the tag with no step" 1 "FIRST CROSSED TAG: 0.2.0" \
  refusal_from "$SCRIPT" castnow
check_absent "no applied step is announced for it" 1 "APPLIED STEP" \
  refusal_from "$SCRIPT" castnow
check_absent "and the tag mechanised here does not leak into it" 1 \
  "asks it for nothing" refusal_from "$SCRIPT" castnow
unchanged "the unmechanised refusal still leaves the tree byte-identical (--check)" \
  "$TMP/castnow" in_consumer castnow --check --source "$SRC" 0.5.0
unchanged "the unmechanised refusal still leaves the tree byte-identical (--fix)" \
  "$TMP/castnow" in_consumer castnow --fix --source "$SRC" 0.5.0
# NOT VACUOUS, and this is the row that says so. The comparison above is only
# evidence if it can come out the other way, so the SAME comparison is run
# over the one move whose behaviour this build changes — 0.4.1 -> 0.5.0, which
# the merged tree refuses and this one performs. A `diff` that reported
# "identical" for both is a `diff` measuring nothing.
consumer onsplitmerged 0.4.1
consumer onsplitnow 0.4.1
stepped_output_from() { # <script> <fixture>
  (cd "$TMP/$2" && bash "$1" --check --source "$SRC" 0.5.0) 2>&1
}
stepped_diff() {
  if diff \
    <(stepped_output_from "$MERGED/bin/ceremony-upgrade" onsplitmerged) \
    <(stepped_output_from "$SCRIPT" onsplitnow) >/dev/null; then
    echo "same-as-merged"
  else
    echo "differs-from-merged"
  fi
}
check "the comparison can tell the two trees apart where behaviour moved" 0 \
  "differs-from-merged" stepped_diff
check "and the merged tree is the one that refuses that move" 1 \
  "FIRST CROSSED TAG: 0.5.0" \
  stepped_output_from "$MERGED/bin/ceremony-upgrade" onsplitmerged

# --- B8: the CRLF grant refusal names line endings (#600 E8(a)) ------------
#
# A caller written with CRLF endings refuses correctly and always did — the
# value read at the `actions:` line is `read` followed by a carriage return,
# which is not the bare `read` this step rewrites. What shipped was a message
# printing those same four visible bytes on both sides of a sentence saying
# they differ, so the reader is told to compare `actions: read` with
# `actions: read` and find it.
#
# THE FIXTURE IS THE `named` CALLER AND NOT THE BARBERSHOP ONE, which is a
# measured fact about the reach of this reading rather than a fixture
# preference. Barbershop's grant line carries a trailing hand comment, and
# `yaml_uncomment` breaks at the `#` — so the carriage return, which sits after
# that comment, is dropped with it and that caller's value compares equal.
# What CRLF actually reaches is a grant line with nothing after the value,
# which is cast's shape and this one's.
split_consumer crlf 0.3.0 named_caller
sed -i 's/$/\r/' "$TMP/crlf/.github/workflows/labels.yml"
crlf_grant_line() {
  printf '[%s]\n' "$(sed -n '/actions:/p' "$TMP/crlf/.github/workflows/labels.yml" | cat -v)"
}
check "the CRLF fixture's grant line really carries the carriage return" 0 \
  '[  actions: read^M]' crlf_grant_line
check "a CRLF caller still refuses" 1 \
  "THE APPLIED STEP FOR 0.4.1 CANNOT RUN ON THIS TREE" \
  in_consumer crlf --check --source "$SRC" 0.4.1
check "the refusal renders the carriage return instead of hiding it" 1 \
  "already grants 'actions: read\\r'." \
  in_consumer crlf --check --source "$SRC" 0.4.1
check "and it says the two values differ in their line endings" 1 \
  "THE TWO VALUES DIFFER ONLY IN THEIR LINE ENDINGS" \
  in_consumer crlf --check --source "$SRC" 0.4.1
check "it names the remedy in the reader's own file" 1 \
  "to LF endings and run this again" \
  in_consumer crlf --check --source "$SRC" 0.4.1
# The defect itself, as an absence: the message must never print the invisible
# carriage return as a bare word. Stripping its escaped rendering reds this row.
check_absent "the message never prints the invisible byte as a bare read" 1 \
  "already grants 'actions: read'." \
  in_consumer crlf --check --source "$SRC" 0.4.1
unchanged "the CRLF refusal leaves the tree byte-identical (--check)" \
  "$TMP/crlf" in_consumer crlf --check --source "$SRC" 0.4.1
unchanged "the CRLF refusal leaves the tree byte-identical (--fix)" \
  "$TMP/crlf" in_consumer crlf --fix --source "$SRC" 0.4.1
# ...and the clause is keyed on the line ending and nothing else: a caller
# that really did grant something different gets the ordinary refusal, with no
# claim about line endings it would send its reader chasing.
split_consumer grantnone 0.3.0 barbershop_caller
sed -i 's/^  actions: read .*$/  actions: none/' "$TMP/grantnone/.github/workflows/labels.yml"
check "a genuinely different grant still refuses on its value" 1 \
  "already grants 'actions: none'." \
  in_consumer grantnone --check --source "$SRC" 0.4.1
check_absent "and says nothing about line endings, which are not its problem" 1 \
  "DIFFER ONLY IN THEIR LINE ENDINGS" \
  in_consumer grantnone --check --source "$SRC" 0.4.1

# --- B9: the with: indent is the stub's own (#600 E8(b)) -------------------
#
# Every other assumption this step makes about the published block is an exact
# count that dies loudly. The `with:` was appended at a hard-coded four spaces
# because that is what the block happens to indent its job keys at — the same
# assumption with no guard on it, and a latch for whoever moves that block
# rather than a live defect while 0.4.1's stub is frozen.
SRC_INDENT="$TMP/src-indent"
cp -pPR "$SRC" "$SRC_INDENT"
awk '
  /^jobs:$/ { injobs = 1; print; next }
  injobs && /^```$/ { injobs = 0; print; next }
  injobs && NF { print "  " $0; next }
  { print }
' "$SRC/docs/CONSUMERS.md" >"$SRC_INDENT/docs/CONSUMERS.md"
stub_job_indent() { # <source dir> — the indent of the stub's sweep `uses:`
  printf '[%s]\n' "$(
    awk '/^And the complete sweep caller/ { a = 1; next }
         a && /^```yaml$/ { b = 1; next }
         b && /^```$/ { exit }
         b && /@<pinned-tag>/ { match($0, /^ */); print substr($0, 1, RLENGTH); exit }' "$1/docs/CONSUMERS.md" |
      tr ' ' '.'
  )"
}
altered_indent() { stub_job_indent "$SRC_INDENT"; }
shipped_indent() { stub_job_indent "$SRC"; }
# The fixture grades itself first: a re-indent that silently matched nothing
# would leave both sources at four spaces and every row below would pass on a
# build that still hard-codes them.
check "the shipped stub indents its sweep job keys at four" 0 "[....]" shipped_indent
check "the re-indented source really is at six" 0 "[......]" altered_indent

split_consumer indented 0.3.0 named_caller
check "the step runs against a re-indented stub" 0 "0.3.0 -> 0.4.1 done" \
  in_consumer indented --fix --source "$SRC_INDENT" 0.4.1
check "the with: lands at the stub's own indent, not a constant" 0 \
  "      with: { pr_workflow_name: 'board', runner: '[\"self-hosted\",\"ci-runner\"]' }" \
  sweep_of indented
# The indent as a value of its own, because the substring reading cannot serve
# here: a six-space `with:` line CONTAINS the four-space one, so an absence
# assertion about the old constant passes on the very line it was meant to
# reject. Measured as the whole leading run, dots for spaces.
with_indent_of() { # <fixture>
  printf '[%s]\n' "$(sweep_of "$1" | sed -n 's/^\( *\)with: {.*/\1/p' | tr ' ' '.')"
}
check "the with: indent is the stub's six and not the old constant" 0 "[......]" \
  with_indent_of indented
check "the re-indented caller is otherwise the stub it was read from" 0 \
  "      uses: heavy-duty/ceremony/.github/workflows/labels-sweep.yml@0.4.1" \
  sweep_of indented
# The frozen half of the criterion: 0.4.1's shipped stub is unchanged, so the
# four-space write is still exactly what a run against it produces. The
# `named` rows above assert that positively; this one asserts the two sources
# really are different, so those rows and these cannot both be reading one.
check "the shipped source still writes it at four" 0 "[....]" with_indent_of named

# ...and a stub whose placeholder is not on a `uses:` key is a block this step
# has not understood. It says so and writes nothing, rather than picking a
# width — the loud half of B9's two permitted outcomes.
SRC_NOUSES="$TMP/src-nouses"
cp -pPR "$SRC" "$SRC_NOUSES"
sed -i 's|^    uses: \(heavy-duty/ceremony/.github/workflows/labels-sweep.yml@<pinned-tag>\)$|    ref: \1|' \
  "$SRC_NOUSES/docs/CONSUMERS.md"
nouses_shape() {
  printf '[%s]\n' "$(grep -c '^    ref: heavy-duty/ceremony' "$SRC_NOUSES/docs/CONSUMERS.md")"
}
check "the unreadable-stub fixture really moved the placeholder" 0 "[1]" nouses_shape
split_consumer nouses 0.3.0 named_caller
check "a placeholder off the uses: key is a loud failure" 1 \
  "carries its '@<pinned-tag>' placeholder on a line that is not a" \
  in_consumer nouses --check --source "$SRC_NOUSES" 0.4.1
check "that failure quotes the line it could not read" 1 \
  "    ref: heavy-duty/ceremony/.github/workflows/labels-sweep.yml@<pinned-tag>" \
  in_consumer nouses --check --source "$SRC_NOUSES" 0.4.1
check "and it says nothing was written" 1 "Nothing was written." \
  in_consumer nouses --check --source "$SRC_NOUSES" 0.4.1
unchanged "an unreadable stub writes nothing" "$TMP/nouses" \
  in_consumer nouses --fix --source "$SRC_NOUSES" 0.4.1

# --- B7: the guide is true in both places, and a row keeps it so ------------
#
# THE ONE MUST-FAIL BUILD NOTHING ELSE READS. Leave the refusals table saying
# 0.4.1 is the only mechanised tag and every row above still passes, while the
# published guide tells a consumer something the command contradicts on its
# first run. That damage is invisible to a suite that only drives the command,
# so these rows read the guide instead — the same ratchet shape the migration
# table already gets against the guide's availability notes, pointed the other
# way.
guide_section() { # <heading> — that section's paragraphs, unwrapped
  awk -v want="$1" '
    $0 == want { inside = 1; next }
    inside && /^## / { exit }
    inside && /^[[:space:]]*$/ { if (p != "") { print p; p = "" }; next }
    inside { p = p " " $0 }
    END { if (p != "") print p }
  ' "$ROOT/docs/CONSUMERS.md"
}
labels_section() { guide_section '## Labels automation'; }
# Not vacuous: an awk that matched no heading would print nothing and satisfy
# every absence row below while proving nothing about the guide.
labels_section_size() { printf '[%s]\n' "$(labels_section | wc -l | tr -d ' ')"; }
check_absent "the Labels automation section is not empty" 0 "[0]" labels_section_size

check "the 0.5.0 note is in the section this reads" 0 \
  "The optional \`panel[<login>]=\` rows are available at \`0.5.0\` and later" \
  labels_section
check "the 0.5.0 section names the command as the mechanised route" 0 \
  'crosses this' labels_section
check "and says what that crossing performs" 0 \
  'it moves every ceremony ref and re-syncs the mirror' labels_section
check "and says it writes no panel row of its own" 0 \
  "it writes no \`panel[<login>]=\` row" labels_section
check "the 0.4.1 note still names the command too" 0 \
  'performs this migration for you' labels_section

# The clause the first mechanised tag left behind, and the shape of clause the
# next rung will leave behind again: a count. The absence is asserted over the
# WHOLE tree, not the guide alone, because a sentence like this gets quoted.
# BOTH SCANS EXCLUDE THIS FILE, and that is the assertion's shape rather than
# a convenience: the phrase being looked for is written here, in the row that
# looks for it, so a scan reading its own needle can only ever fail. What the
# rows are about is a sentence a CONSUMER reads, and this file is not one.
NOT_THIS_FILE=':!test/ceremony-upgrade.test.sh'
stale_only_claim_sites() {
  printf '[%s]\n' "$(git -C "$ROOT" grep -lF 'today it is the only one' -- "$NOT_THIS_FILE" | tr '\n' ' ' | sed 's/ $//')"
}
check "no file still claims one tag is the only mechanised one" 0 "[]" \
  stale_only_claim_sites
also_stale_only_claim_sites() {
  printf '[%s]\n' "$(git -C "$ROOT" grep -lF 'the only migration it performs' -- "$NOT_THIS_FILE" | tr '\n' ' ' | sed 's/ $//')"
}
check "and none claims the command performs only one migration" 0 "[]" \
  also_stale_only_claim_sites

refusals_row() { grep -hF '| **the move crosses a migration** |' "$ROOT/docs/CONSUMERS.md"; }
check "the refusals row names 0.4.1's applied step" 0 \
  "[\`0.4.1\`](#labels-automation)'s two-caller split" refusals_row
check "the refusals row names 0.5.0's" 0 \
  "[\`0.5.0\`](#labels-automation)'s panel rows" refusals_row
check "the refusals row names 0.6.0's" 0 \
  "[\`0.6.0\`](#doctrine-mirror)'s doctrine-mirror crossing" refusals_row
check "the refusals row names 0.7.8's" 0 \
  "[\`0.7.8\`](#the-guarded-scaffold--ceremony-owns-a-block-you-own-the-rest)'s guarded scaffold" \
  refusals_row
# "the tags mechanised so far" and not "both" or "two": a count is the thing
# the NEXT rung falsifies again, and this row is what stops one being written.
check "the refusals row claims no count the next rung would falsify" 0 \
  "the tags mechanised so far" refusals_row
check_absent "it does not say two" 0 "the two tags" refusals_row
check_absent "and it does not say both" 0 "both of them" refusals_row

mechanised_set_rows() {
  git -C "$ROOT" grep -hF 'the tags mechanised so far' -- \
    ':!test/ceremony-upgrade.test.sh'
}
mechanised_set_row_count() {
  printf '[%s]\n' "$(mechanised_set_rows | wc -l | tr -d ' ')"
}
check "one consumer-facing row states the complete mechanised set" 0 "[1]" \
  mechanised_set_row_count
check "that complete set includes 0.6.0" 0 \
  "[\`0.6.0\`](#doctrine-mirror)'s doctrine-mirror crossing" \
  mechanised_set_rows

doctrine_section() { guide_section '## Doctrine mirror'; }
doctrine_route="[\`ceremony-upgrade\`](#ceremony-upgrade--the-bump-run-for-you) mechanises this \`0.6.0\` crossing"
check "the Doctrine mirror section names ceremony-upgrade for 0.6.0" 0 \
  "$doctrine_route" doctrine_section
check "the Doctrine mirror route keeps docs-sync as the RELEASES.md writer" 0 \
  "end-of-run mirror re-sync writes it through \`docs-sync --fix\`" \
  doctrine_section
check "the Doctrine mirror route says no refs-guard caller is written" 0 \
  "command writes no \`.github/workflows/refs-guard.yml\`" doctrine_section
check "the Doctrine mirror route leaves adoption to the consumer" 0 \
  "consumer's own call under [Bootstrap a new repo]" doctrine_section

guarded_scaffold_section() {
  guide_section '### The guarded scaffold — ceremony owns a block, you own the rest'
}
guarded_route="[\`ceremony-upgrade\`](#ceremony-upgrade--the-bump-run-for-you) mechanises the \`0.7.8\` crossing"
check "the guarded-scaffold section names ceremony-upgrade" 0 \
  "$guarded_route" guarded_scaffold_section
guarded_writer="writes the block through \`docs-sync --fix\`"
check "the guarded-scaffold section keeps docs-sync as the writer" 0 \
  "$guarded_writer" guarded_scaffold_section

migration_step_field() { # <tag>
  sed -n "s/^  \"$1|[^|]*|[^|]*|\([^\"]*\)\"$/[\1]/p" "$SCRIPT"
}
check "the 0.7.8 migration row names its step" 0 \
  "[step_0_7_8_guarded_scaffold]" migration_step_field 0.7.8
check "the 0.6.0 migration row names its step" 0 \
  "[step_0_6_0_doctrine_and_refs]" migration_step_field 0.6.0
check "the 0.7.0 migration row names its step" 0 \
  "[step_0_7_0_rc_release_path]" migration_step_field 0.7.0
for unmechanised in 0.1.0 0.2.0 0.3.0; do
  check "$unmechanised remains unmechanised" 0 "[]" \
    migration_step_field "$unmechanised"
done

doctrine_step_body() {
  sed -n '/^step_0_6_0_doctrine_and_refs() {$/,/^}$/p' "$SCRIPT"
}
check "the 0.6.0 step carries a non-empty plan" 0 "step_plan+=(" \
  doctrine_step_body
check_absent "the 0.6.0 step has no refusal" 0 "step_refuse" \
  doctrine_step_body
check_absent "the 0.6.0 step declares no new file" 0 "step_new_file" \
  doctrine_step_body
check_absent "the 0.6.0 step declares no edited file" 0 "step_edit_file" \
  doctrine_step_body
check_absent "the 0.6.0 step declares no edit operations" 0 "step_edit_ops" \
  doctrine_step_body
check_absent "the 0.6.0 step does not read the doctrine manifest" 0 \
  "VENDORED.txt" doctrine_step_body

# B6 for the tag this build mechanises, in the shape its two siblings use.
# THE ROWS BELOW ARE THE CRITERION; THE CROSSING ROWS ARE NOT. A crossing that
# writes a byte is caught by the --fix fixtures, but B6 states a property of
# the FUNCTION: a step_refuse on an unreached branch, a manifest read whose
# result is discarded, or an edit declaration the planner never acts on all
# change no behaviour and no output, so no fixture can see them. Only reading
# the body can. Extraction starts at the definition line and NOT at the head
# comment above it, which says "IT CALLS step_refuse NOWHERE" and would
# satisfy every absence row it is supposed to fail.
#
# Both manifests, not one: this step reads neither, and VENDORED.txt is only
# incidentally covered for it by the file-wide row below.
rc_step_body() {
  sed -n '/^step_0_7_0_rc_release_path() {$/,/^}$/p' "$SCRIPT"
}
check "the 0.7.0 step carries a non-empty plan" 0 "step_plan+=(" \
  rc_step_body
check_absent "the 0.7.0 step has no refusal" 0 "step_refuse" \
  rc_step_body
check_absent "the 0.7.0 step declares no new file" 0 "step_new_file" \
  rc_step_body
check_absent "the 0.7.0 step declares no edited file" 0 "step_edit_file" \
  rc_step_body
check_absent "the 0.7.0 step declares no edit operations" 0 "step_edit_ops" \
  rc_step_body
check_absent "the 0.7.0 step does not read the doctrine manifest" 0 \
  "VENDORED.txt" rc_step_body
check_absent "the 0.7.0 step does not read the scaffold manifest" 0 \
  "SCAFFOLDED.txt" rc_step_body

unexpected_vendored_hits() {
  printf '[%s]\n' "$(
    awk '
      /VENDORED/ {
        if ($0 ~ /^[[:space:]]*#/) next
        if ($0 ~ /^  "0\.1\.0\|Read the manifest/) next
        print NR ":" $0
      }
    ' "$SCRIPT"
  )"
}
check "every VENDORED hit is comment prose or the migration-row description" 0 \
  "[]" unexpected_vendored_hits

# The disclosure 0.6.0's planner carried is DISCHARGED, not deleted: it used
# to say the next mint owed a decision about `stepable`, and mechanising 0.7.0
# made that decision. These rows moved with it (#610 J9) — they assert the
# record of what was decided, so deleting the comment still reds, and the
# absence row below makes the stale promise unrepeatable.
stepable_disclosure() {
  awk '/THAT DECISION WAS MADE WHEN 0.7.0 WAS MECHANISED/ { armed = 1 }
       armed && !/^#/ { exit }
       armed' "$SCRIPT"
}
check "the 0.7.0 disclosure says the last stepable ladder position disappeared" 0 \
  "did remove the last released ladder position expressing" \
  stepable_disclosure
check "the 0.7.0 disclosure records the decision instead of owing one" 0 \
  "the coverage MOVED rather than being dropped or re-based" stepable_disclosure
check "the 0.7.0 disclosure names where the coverage went" 0 \
  "SECOND source tree carrying one fabricated rung" stepable_disclosure
check "the 0.7.0 disclosure says why the rung is kept out of the shared ladder" 0 \
  "The rung is NOT in \$SRC" stepable_disclosure
check_absent "no comment still says the next mint owes a stepable decision" 0 \
  "OWES A DECISION, NOT A RE-BASE" cat "$SCRIPT"

# B13 — the real-intervals convention acquired an exception in this build, and
# a convention that acquires an unwritten one is the next reader's trap. These
# rows are what make deleting the amendment red: without them the comment is
# prose nothing measures, which is exactly how it would rot.
# Bounded by the END OF THE COMMENT BLOCK, never by a second literal. An
# end-anchored range whose anchor is inside the region it grades runs to EOF
# the moment that region is deleted — and then sweeps up the needles in the
# rows below, which pass for the wrong reason. Deleting the exception must red
# every row that names it, so the extractor stops at the first non-comment
# line and returns nothing at all when the block's opening line is gone.
intervals_convention() {
  awk '/^# THE LADDER.S VERSIONS ARE THE REAL ONES on purpose/ { armed = 1 }
       armed && !/^#/ { exit }
       armed' "$ROOT/test/ceremony-upgrade.test.sh"
}
check "the real-intervals convention still states the rule" 0 \
  "have to be the real intervals" \
  intervals_convention
check "the real-intervals convention carries its exception" 0 \
  "ONE FIXTURE IS AN EXCEPTION, AND IT IS DELIBERATE" intervals_convention
check "the exception names the fixture and its second source tree" 0 \
  "stepable\` stands" intervals_convention
check "the exception gives its reason" 0 \
  "left no real interval" intervals_convention
check "the exception says every other fixture still uses real intervals" 0 \
  "Every OTHER fixture still uses the real intervals" intervals_convention

# B18 — what the sixth mint inherits, recorded in the file rather than only in
# this build's PR. A row matches it so deleting the paragraph reds.
sixth_mint_disclosure() {
  awk '/^# WHAT THE SIXTH MINT INHERITS/ { armed = 1 }
       armed && !/^#/ { exit }
       armed' "$SCRIPT"
}
check "the sixth-mint disclosure names the two remaining crossable tags" 0 \
  "0.2.0 wants a triage-actors= value no" sixth_mint_disclosure
check "the sixth-mint disclosure says which fixture stands on 0.2.0" 0 \
  "\`ancient\` keys on 0.2.0" sixth_mint_disclosure
check "the sixth-mint disclosure says which fixture stands on the pair" 0 \
  "\`atwall\` keys on the 0.2.0 → 0.3.0 pair" sixth_mint_disclosure
check "the sixth-mint disclosure says what mechanising either tag costs" 0 \
  "re-homes \`atwall\` again" sixth_mint_disclosure

# #605 pinned `stepable`, `atwall` and the override probe byte-identical to
# 5677d46 PRECISELY BECAUSE 0.7.0 was still unmechanised. This build is the one
# that moves them, so those three pins are discharged and replaced by rows
# asserting where the fixtures now stand. A pin to a commit cannot express
# "and it moved correctly"; these can, and they red on the specific ways this
# re-homing goes wrong.
override_probe_body() {
  sed -n '/^in_consumer_with_override() {$/,/^}$/p' "$ROOT/test/ceremony-upgrade.test.sh"
}
# J6's defect, made checkable: move the atwall block and leave the probe's
# hard-coded target behind and the L638 row keeps PASSING while testing a
# mechanised crossing instead of a hand-only one. The probe must name atwall's
# new target and must not name the tag this build just mechanised.
check_absent "the override probe does not target the newly mechanised tag" 0 \
  "0.7.0" override_probe_body
check "the override probe targets the re-based at-wall crossing" 0 \
  "0.3.0" override_probe_body
# The re-homed fixtures stand where this build put them: `atwall` on a real
# consecutive interval, `stepable` on the synthetic source and NOT on $SRC.
#
# THE NEEDLE IS BUILT FROM THE ARGUMENTS AND ANCHORED TO A WHOLE LINE, and
# both of those are load-bearing. These two rows first cat'd the whole file
# for an unanchored needle spelled out on the assertion's own line: the row
# matched ITSELF, so changing the declaration it claims to guard left it
# green. Composing the pattern here means the literal exists nowhere but the
# declaration, and anchoring it means an assertion that quotes the pin in
# passing can never satisfy the row. The count is bracketed on both sides so
# a duplicated declaration reads as [2] rather than as a substring of [1].
fixture_pin_lines() { # <fixture> <pin>
  printf '[%s]\n' "$(
    grep -c "^consumer $1 ${2//./\\.}\$" "$ROOT/test/ceremony-upgrade.test.sh"
  )"
}
check "the at-wall fixture is pinned at the re-based rung" 0 "[1]" \
  fixture_pin_lines atwall 0.2.0
check "the stepable fixture is pinned at the synthetic interval's rung" 0 "[1]" \
  fixture_pin_lines stepable 0.2.0
stepable_runs() {
  sed -n '/^consumer stepable 0.2.0$/,/^check_absent "the shared source ladder/p' \
    "$ROOT/test/ceremony-upgrade.test.sh" | grep -- '--source'
}
# The needles carry no dollar on purpose: they are matched against the FILE's
# own text, where the variable name is literal, and a needle written with one
# would be a shellcheck SC2016 for no gain. 'SRC" ' matches the shared source
# and cannot match "$SRC_SYNTH", which ends 'SYNTH"'.
check_absent "no stepable row still runs against the shared source" 0 \
  'SRC" ' stepable_runs
check "every stepable row runs against the synthetic source" 0 \
  'SRC_SYNTH"' stepable_runs

added_consumer_numeric_refs() {
  printf '[%s]\n' "$(
    git -C "$ROOT" diff --unified=0 5677d46 -- \
      bin/ceremony-upgrade docs/CONSUMERS.md |
      sed -n 's/^+//p' |
      awk '!/^[[:space:]]*#/' |
      grep -E '#[0-9]+' || true
  )"
}
check "new messages, plan lines and guide prose carry no issue number" 0 \
  "[]" added_consumer_numeric_refs

guarded_step_body() {
  sed -n '/^step_0_7_8_guarded_scaffold() {$/,/^}$/p' "$SCRIPT"
}
check "the 0.7.8 step carries a non-empty plan" 0 "step_plan+=(" \
  guarded_step_body
check_absent "the 0.7.8 step has no refusal" 0 "step_refuse" \
  guarded_step_body
check_absent "the 0.7.8 step declares no new file" 0 "step_new_file" \
  guarded_step_body
check_absent "the 0.7.8 step declares no edited file" 0 "step_edit_file" \
  guarded_step_body
check_absent "the 0.7.8 step declares no edit operations" 0 "step_edit_ops" \
  guarded_step_body
check_absent "the 0.7.8 step does not read the scaffold manifest" 0 \
  "SCAFFOLDED.txt" guarded_step_body

summary
