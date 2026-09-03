#!/usr/bin/env bash
# Contract tests for actions/refs-not-closing (issue #218). Bodies and
# closing-reference sets are fixtures: no network and no pull request are
# involved. set -u, not -e: failures are behavior for the harness to inspect.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test/harness.sh
. "$ROOT/test/harness.sh"

SCRIPT="$ROOT/actions/refs-not-closing/refs-not-closing.sh"
ACTION="$ROOT/actions/refs-not-closing/action.yml"
ENTRYPOINT="$ROOT/actions/refs-not-closing/run.sh"
WORKFLOW="$ROOT/.github/workflows/refs-guard.yml"
BUILDER="$ROOT/BUILDER.md"
REVIEWER="$ROOT/REVIEWER.md"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

body() {
  local name="$1"
  shift
  printf '%s\n' "$@" >"$TMP/$name.md"
}

guard() {
  local name="$1"
  shift
  bash "$SCRIPT" "$TMP/$name.md" "$@"
}

body ref-5 'Refs #5'
check "Refs target with empty closing set passes" 0 "no Refs target" guard ref-5
check "Refs target with itself closing fails" 1 "#5" guard ref-5 5
check "Refs target with another issue closing passes" 0 "no Refs target" guard ref-5 9

body ordinary 'Closes #5'
check "ordinary Closes PR remains green" 0 "no Refs target" guard ordinary 5

body mixed 'Refs #5' '' 'This PR legitimately Closes #9.'
check "Refs #5 plus Closes #9 remains green" 0 "no Refs target" guard mixed 9

body prose 'Refs #5' '' 'Triage closes #5 by hand after the live proof.'
check "closing prose for a Refs target fails" 1 "closes #5" guard prose 5
check "failure prints the surrounding sentence" 1 \
  "sentence: Triage closes #5 by hand after the live proof" guard prose 5
check "failure offers number-first rewrite" 1 "#N is" guard prose 5
check "failure offers number-free rewrite" 1 "closes the issue" guard prose 5

body code-span 'Refs #5' '' "The body must not contain \`Closes #5\` anywhere."
check "backticked closing keyword is reported as the match" 1 \
  "matched: Closes #5" guard code-span 5
check "backticked match points at the Development sidebar remedy" 1 \
  "remove the Development sidebar link" guard code-span 5

diagnostic_contains_retired_sentence() {
  bash "$SCRIPT" "$TMP/code-span.md" 5 2>&1 |
    grep -qF "Backticks do not protect"
}

check "failure omits the retired backtick claim" 1 "" \
  diagnostic_contains_retired_sentence

# Prove the diagnostic pin is load-bearing rather than merely compatible with
# both the retired and replacement text (#359).
MUTANT="$TMP/refs-not-closing-without-routes.sh"
sed '/The closing graph can come from a/,/sidebar link\./c\
  The closing graph has an unexplained entry.' "$SCRIPT" >"$MUTANT"

diagnostic_names_both_routes() {
  local candidate="$1" output
  output="$(bash "$candidate" "$TMP/code-span.md" 5 2>&1)"
  grep -qF "closing keyword adjacent to the number in the body's prose" \
    <<<"$output" && grep -qF "Development" <<<"$output"
}

check "diagnostic names both closing-graph routes" 0 "" \
  diagnostic_names_both_routes "$SCRIPT"
check "two-route mutation changes the script" 1 "" \
  cmp -s "$SCRIPT" "$MUTANT"
check "removing the two-route diagnostic reds its pin" 1 "" \
  diagnostic_names_both_routes "$MUTANT"

# The mirror of the code-span fixture above: a pull request that legitimately
# closes N while its archived round record quotes `Refs #N` at that same N.
# The closing keyword is the correct one, so the evidence must name the quoted
# occurrence that actually produced the intersection and the remedy must not
# send the author to rewrite the close (#606). Quoted-only is a property of
# every occurrence, which is what the bare rows below discriminate.
body quoted-only 'Closes #220' '' \
  "An archived round said \`Refs #220\` was right then." '' \
  '> Round 2 argued Refs #220 against the issue as it stood.'

check "quoted-only intersection still reds" 1 \
  "scheduled to close: #220" guard quoted-only 220
check "quoted-only failure names the occurrence that fired" 1 \
  "Refs match: Refs #220" guard quoted-only 220
check "quoted-only failure prints the quoted occurrence's sentence" 1 \
  "Refs sentence: An archived round said" guard quoted-only 220
check "quoted-only failure says every occurrence is quoted" 1 \
  "every Refs occurrence is quoted" guard quoted-only 220
check "quoted-only remedy names the archived round record" 1 \
  "archived round record" guard quoted-only 220
check "quoted-only remedy says to de-parse the tokens" 1 \
  "de-parse them" guard quoted-only 220
check "quoted-only remedy keeps the Development sidebar route" 1 \
  "Development sidebar link" guard quoted-only 220
check_absent "quoted-only remedy drops the number-first rewrite" 1 \
  "#N is" guard quoted-only 220
check_absent "quoted-only remedy drops the number-free rewrite" 1 \
  "closes the issue" guard quoted-only 220

# J2, at the two edges the analysis could have moved: a quoted-only body with
# no closing entry, and one whose closing entry is a different number.
check "quoted-only body with an empty closing set still passes" 0 \
  "no Refs target" guard quoted-only
check "quoted-only body closing another issue still passes" 0 \
  "no Refs target" guard quoted-only 9

# One bare occurrence among the quoted ones is not quoted-only, and takes the
# old path in full — both safe forms included.
body quoted-with-bare 'Closes #220' '' \
  "An archived round said \`Refs #220\` was right then." '' \
  '> Round 2 argued Refs #220 against the issue as it stood.' '' \
  'Refs #220 stands bare in this sentence.'

check "one bare occurrence keeps the number-first rewrite" 1 \
  "#N is" guard quoted-with-bare 220
check "one bare occurrence keeps the number-free rewrite" 1 \
  "closes the issue" guard quoted-with-bare 220
check_absent "one bare occurrence is not quoted-only" 1 \
  "every Refs occurrence is quoted" guard quoted-with-bare 220
check_absent "one bare occurrence does not reach the archived-record route" 1 \
  "archived round record" guard quoted-with-bare 220

# Each quoting form on its own is sufficient. A build that reads backticks but
# not `>`, or fences but not spans, reds exactly one of these three.
body quoted-span 'Closes #220' '' "The record said \`Refs #220\` there."
body quoted-blockquote 'Closes #220' '' '> The record said Refs #220 there.'
body quoted-fence 'Closes #220' '' '```' 'The record said Refs #220 there.' '```'

for form in span blockquote fence; do
  check "a $form occurrence alone is quoted-only" 1 \
    "every Refs occurrence is quoted" guard "quoted-$form" 220
  check "a $form-only intersection still reds" 1 \
    "scheduled to close: #220" guard "quoted-$form" 220
done

# The fence closes on its own delimiter character and nothing else, so a fence
# neither swallows the body after it nor is broken open by a different
# character inside it. Both directions are the same house rule from
# actions/issueflow-reconcile/issueflow-reconcile.sh.
body fence-then-bare 'Closes #220' '' '~~~' 'The record said Refs #220 there.' \
  '~~~' '' 'Refs #220 stands bare after the fence.'
check_absent "a closed fence does not swallow the bare occurrence after it" 1 \
  "every Refs occurrence is quoted" guard fence-then-bare 220
check "the occurrence after a closed fence keeps the old remedy" 1 \
  "#N is" guard fence-then-bare 220

body fence-mismatched '```' 'The record said Refs #220 there.' '~~~' \
  'And said Refs #220 again.' '```' '' 'Closes #220'
check "a tilde line does not close a backtick fence" 1 \
  "every Refs occurrence is quoted" guard fence-mismatched 220

# Quoting is classified per number, so the remedy is selected per number. A
# set that does not agree gets both blocks under a paragraph binding each to
# the numbers it governs: sending the whole set the bare remedy tells the
# author of the marked number to rewrite its own legitimate close, which is
# the destructive edit (#606).
body mixed-quoting 'Closes #220' 'Closes #221' '' \
  "An archived round said \`Refs #220\` was right then." '' \
  'Refs #221 stands bare in this sentence.'

check "a mixed-quoting set still reds and names both numbers" 1 \
  "scheduled to close: #220 #221" guard mixed-quoting 220 221
check "the mixed set is scoped rather than given one remedy" 1 \
  "do not share a remedy" guard mixed-quoting 220 221
check "the mixed scoping forbids rewriting a marked number's close" 1 \
  "Do not rewrite a closing-keyword" guard mixed-quoting 220 221
check "the mixed remedy keeps the archived-record route" 1 \
  "archived round record" guard mixed-quoting 220 221
check "the mixed remedy keeps the number-first rewrite for the bare number" 1 \
  "#N is" guard mixed-quoting 220 221
check "the mixed remedy keeps the number-free rewrite for the bare number" 1 \
  "closes the issue" guard mixed-quoting 220 221

# Presence of the marker is not enough: a flag that is global in either
# direction prints it for both numbers or for neither, and both of those also
# satisfy the rows above. Count it instead — exactly one of the two targets is
# quoted-only. The colon is what separates the marker line from the scoping
# paragraph's backticked quotation of it.
mixed_marker_count() {
  bash "$SCRIPT" "$TMP/mixed-quoting.md" 220 221 2>&1 |
    grep -cF 'every Refs occurrence is quoted:'
}
check "exactly one of the mixed targets carries the marker" 0 "1" \
  mixed_marker_count

# The two directions backtick parity got wrong. A valid multi-backtick span
# read as bare is the stranding remedy landing on the shape this branch
# exists to protect; an unmatched opener read as quoted is the discrimination
# J1 spells out in "anything else … is not quoted-only".
body span-double 'Closes #220' '' \
  "The archive says \`\`Refs #220\`\` was once right."
check "a double-backtick span is quoted" 1 \
  "every Refs occurrence is quoted" guard span-double 220
check_absent "a double-backtick span does not get the stranding rewrite" 1 \
  "#N is" guard span-double 220

body span-unclosed 'Closes #220' '' \
  "The archive starts \`Refs #220 but the span never closes."
check_absent "an unmatched opener is not quoted" 1 \
  "every Refs occurrence is quoted" guard span-unclosed 220
check "an unmatched opener keeps the old remedy" 1 \
  "#N is" guard span-unclosed 220

# J7/K13: provenance lives in code comments, never in the message the author
# reads. The remedy text carries no issue, pull request or discussion number —
# only the intersecting numbers the run was given.
remedy_names_an_issue_number() {
  bash "$SCRIPT" "$TMP/quoted-only.md" 220 2>&1 |
    sed -n '/must not close N/,$p' | grep -qE '#[0-9]'
}
check "quoted-only remedy names no issue number" 1 "" \
  remedy_names_an_issue_number

# A code span is descriptive in both role paragraphs, but it must never appear
# after the safe-rewrite anchor as another recommended remedy (#359).
doctrine_avoids_code_span_remedy() {
  local candidate="$1" role="$2" paragraph tail
  case "$role" in
    builder)
      paragraph="$(awk '
        /^- On a `Refs #N` PR/ { emit = 1 }
        emit && /^- \*\*/ { exit }
        emit { print }
      ' "$candidate")"
      tail="${paragraph#*Put the number first}"
      ;;
    reviewer)
      paragraph="$(awk '
        /^1\. \*\*The issue.s acceptance criteria/ { emit = 1 }
        emit && /^2\. \*\*/ { exit }
        emit { print }
      ' "$candidate")"
      tail="${paragraph#*The safe forms}"
      ;;
    *)
      return 2
      ;;
  esac
  [ "$tail" != "$paragraph" ] && ! grep -qiF "code span" <<<"$tail"
}

BUILDER_MUTANT="$TMP/BUILDER-with-code-span-remedy.md"
sed 's/) or omit it\./) or omit it, or put the closing phrase in a code span./' \
  "$BUILDER" >"$BUILDER_MUTANT"
REVIEWER_MUTANT="$TMP/REVIEWER-with-code-span-remedy.md"
sed '/The safe forms/{n;s/) or omit it.*/) or omit it, or put the closing phrase in a code span./;}' \
  "$REVIEWER" >"$REVIEWER_MUTANT"

check "builder doctrine does not offer a code-span remedy" 0 "" \
  doctrine_avoids_code_span_remedy "$BUILDER" builder
check "builder doctrine mutation changes the file" 1 "" \
  cmp -s "$BUILDER" "$BUILDER_MUTANT"
check "builder code-span remedy reds its doctrine pin" 1 "" \
  doctrine_avoids_code_span_remedy "$BUILDER_MUTANT" builder
check "reviewer doctrine does not offer a code-span remedy" 0 "" \
  doctrine_avoids_code_span_remedy "$REVIEWER" reviewer
check "reviewer doctrine mutation changes the file" 1 "" \
  cmp -s "$REVIEWER" "$REVIEWER_MUTANT"
check "reviewer code-span remedy reds its doctrine pin" 1 "" \
  doctrine_avoids_code_span_remedy "$REVIEWER_MUTANT" reviewer

body adjacency 'Refs #5' '' 'Triage closes #9 and #5 after the proof.'
check "non-adjacent #5 does not join closing set #9" 0 "no Refs target" \
  guard adjacency 9

body empty ''
check "empty body remains green" 0 "no Refs target" guard empty 5

body incidents-211 'Refs #209' 'Triage closes #209 by hand.'
check "#211 incident replays red" 1 "#209" guard incidents-211 209
body incidents-214 'Refs #212' 'Triage closes #212 and #209 on that evidence.'
check "#214 incident replays red" 1 "#212" guard incidents-214 212
body incidents-200 'Refs #199' "A later edit added \`Closes #199\`."
check "#200 incident replays red" 1 "#199" guard incidents-200 199

body multiple 'Refs #5 and Refs #7.' 'Triage closes #5 and fixes #7 by hand.'
check "failure names every intersecting issue" 1 \
  "scheduled to close: #5 #7" guard multiple 5 7

body soft-wrap 'Refs #5' '' 'Triage closes' '#5 by hand after the live proof.'
check "soft-wrapped closing prose is reported as one sentence" 1 \
  "sentence: Triage closes #5 by hand after the live proof" \
  guard soft-wrap 5

body refs-colon 'Refs: #5' '' 'Triage closes #5 after proof.'
check "Refs colon form is protected" 1 "matched: closes #5" \
  guard refs-colon 5
body refs-link 'Refs [#5](https://example.test/issues/5)' '' \
  'Triage closes #5 after proof.'
check "linked Refs form is protected" 1 "matched: closes #5" \
  guard refs-link 5

for number in 207 191 190 176 165 164; do
  body "incident-$number" "Refs #$number"
  check "#$number incident replays green" 0 "no Refs target" \
    guard "incident-$number"
done

check "missing body is a loud failure" 1 "missing or unreadable" \
  bash "$SCRIPT" "$TMP/missing.md"
check "invalid closing set is a loud failure" 1 "invalid closing issue" \
  guard ref-5 nope

# The action owns the network boundary. Drive its executable entrypoint with
# a fake `gh` so failures are behavioral assertions, not YAML text guesses.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -u
case "${FAKE_GH_MODE:-success}" in
  failure)
    echo "fake GraphQL read failed" >&2
    exit 42
    ;;
  partial)
    has_next=true
    ;;
  success)
    has_next=false
    ;;
  *)
    echo "unknown fake mode: ${FAKE_GH_MODE:-}" >&2
    exit 2
    ;;
esac
printf '{"data":{"repository":{"pullRequest":{"body":"Refs #5","closingIssuesReferences":{"nodes":[],"pageInfo":{"hasNextPage":%s}}}}}}\n' "$has_next"
EOF
chmod +x "$TMP/bin/gh"

action_boundary() {
  local mode="$1"
  env PATH="$TMP/bin:$PATH" FAKE_GH_MODE="$mode" \
    GITHUB_REPOSITORY="heavy-duty/ceremony" PR_NUMBER=268 \
    GITHUB_ACTION_PATH="$ROOT/actions/refs-not-closing" \
    bash "$ENTRYPOINT"
}

check "action boundary fails when GraphQL read fails" 42 \
  "fake GraphQL read failed" action_boundary failure
check "action boundary refuses a partial closing-reference page" 5 \
  "refusing a partial verdict" action_boundary partial
check "action boundary accepts a complete GraphQL read" 0 \
  "no Refs target" action_boundary success

one_graphql_read() {
  [ "$(grep -c "gh api graphql" "$ENTRYPOINT")" -eq 1 ]
  printf '1\n'
}

check "action performs exactly one GraphQL read" 0 "1" \
  one_graphql_read
check "composite delegates to the tested entrypoint" 0 "run.sh" \
  grep -F "run: bash \"\$GITHUB_ACTION_PATH/run.sh\"" "$ACTION"

check "workflow wakes on body edits" 0 "types: [opened, edited, reopened, synchronize]" \
  grep -F "types: [opened, edited, reopened, synchronize]" "$WORKFLOW"
check "workflow is pull_request-only" 1 "" \
  grep -E '^  (push|pull_request_target|workflow_dispatch|schedule|issue_comment):' \
  "$WORKFLOW"
check "workflow grants read-only pull request access" 0 "pull-requests: read" \
  grep -F "pull-requests: read" "$WORKFLOW"

summary
