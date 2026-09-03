#!/usr/bin/env bash
set -euo pipefail

# refs-not-closing.sh <body-file> [<closing-issue-number> ...] — compare the
# issues a PR promises merely to reference with GitHub's closing-issue graph
# (#218). The graph is authoritative because it includes both closing
# keywords and sidebar links. The body still matters: only an issue named by
# `Ref #N` or `Refs #N` is protected, so an ordinary `Closes #N` PR remains
# untouched.
#
# This decision stays network-free so test/refs-not-closing.test.sh can drive
# the incident matrix offline. The composite action gathers both facts in one
# GraphQL read and passes them here. A failed or partial read never reaches
# this script: action.yml refuses it before asking for a verdict.

body_file="${1:-}"
shift || true

if [ -z "$body_file" ] || [ ! -f "$body_file" ]; then
  echo "refs-not-closing: body file is missing or unreadable: ${body_file:-<none>}" >&2
  exit 1
fi

declare -A closing=()
for issue in "$@"; do
  case "$issue" in
    ''|*[!0-9]*)
      echo "refs-not-closing: invalid closing issue number: '$issue'" >&2
      exit 1
      ;;
  esac
  closing["$issue"]=1
done

mapfile -t refs_targets < <(
  awk '
    {
      rest = tolower($0)
      while (match(rest, /(^|[^[:alnum:]_])refs?[[:space:]]*:?[[:space:]]*[[]?#[0-9]+/)) {
        token = substr(rest, RSTART, RLENGTH)
        sub(/^.*#/, "", token)
        print token + 0
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
  ' "$body_file" | sort -nu
)

intersections=()
for issue in "${refs_targets[@]}"; do
  if [ -n "${closing[$issue]:-}" ]; then
    intersections+=("$issue")
  fi
done

if [ "${#intersections[@]}" -eq 0 ]; then
  echo "refs-not-closing: no Refs target appears in GitHub's closing-issue graph"
  exit 0
fi

sentence_for_issue() {
  local issue="$1" mode="$2"
  awk -v issue="$issue" -v mode="$mode" '
    /^[[:space:]]*$/ {
      if (paragraph != "") {
        text = text paragraph "\n\n"
        paragraph = ""
      }
      next
    }
    {
      if (paragraph != "") paragraph = paragraph " "
      paragraph = paragraph $0
    }
    END {
      text = text paragraph
      count = split(text, sentence, /[.!?][[:space:]]+|\n\n+/)
      if (mode == "closing") {
        needle = "(^|[^[:alnum:]_])(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[[:space:]]+#[[:space:]]*" issue "([^0-9]|$)"
      } else {
        needle = "(^|[^[:alnum:]_])refs?[[:space:]]*:?[[:space:]]*\\[?#[[:space:]]*" issue "([^0-9]|$)"
      }
      for (i = 1; i <= count; i++) {
        lower = tolower(sentence[i])
        if (match(lower, needle)) {
          matched = substr(sentence[i], RSTART, RLENGTH)
          sub(/^[^[:alnum:]_]*/, "", matched)
          sub(/[^0-9]*$/, "", matched)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", sentence[i])
          printf "%s\t%s\n", matched, sentence[i]
          exit
        }
      }
    }
  ' "$body_file"
}

# Where every `Refs` occurrence for an intersecting number is quoted — inside a
# fenced block, an inline code span, or a blockquote line — the closing keyword
# in the body is typically the pull request's own legitimate one, and the shape
# is an archived round record arguing about that number. Telling that author to
# rewrite the closing-keyword sentence deletes the close and strands the issue,
# so the remedy branches on this. It is message-only: `intersections` and the
# exit code above are computed without it and do not move (#606). Fence
# tracking follows the house form in
# actions/issueflow-reconcile/issueflow-reconcile.sh — the first delimiter
# opens, the next one whose leading character matches closes, so a tilde line
# does not close a backtick fence and an unclosed fence consumes the rest.
refs_quoting() {
  local issue="$1"
  awk -v issue="$issue" '
    BEGIN {
      needle = "(^|[^[:alnum:]_])refs?[[:space:]]*:?[[:space:]]*[[]?#[[:space:]]*" issue "([^0-9]|$)"
    }
    /^ {0,3}(```|~~~)/ {
      delim = $0; sub(/^ {0,3}/, "", delim); char = substr(delim, 1, 1)
      if (!in_fence) { in_fence = 1; fence_char = char }
      else if (char == fence_char) { in_fence = 0 }
      next
    }
    {
      lower = tolower($0)
      blockquote = ($0 ~ /^[[:space:]]*>/)
      pos = 1
      while (match(substr(lower, pos), needle)) {
        start = pos + RSTART - 1
        stop = start + RLENGTH
        # The match can open on the boundary character the needle requires, so
        # walk past it: a leading backtick is the code-span delimiter itself
        # and must be counted as opening the span, not as sitting inside it.
        token = start
        while (token < stop && substr(lower, token, 1) !~ /[[:alnum:]_]/) token++
        total++
        if (in_fence || blockquote) {
          quoted = 1
        } else {
          ticks = 0
          for (i = 1; i < token; i++) if (substr($0, i, 1) == "`") ticks++
          quoted = ticks % 2
        }
        if (!quoted) bare++
        pos = stop
      }
    }
    END {
      if (total > 0 && bare == 0) print "quoted"; else print "bare"
    }
  ' "$body_file"
}

declare -A quoting=()
all_quoted=1
for issue in "${intersections[@]}"; do
  quoting["$issue"]="$(refs_quoting "$issue")"
  [ "${quoting[$issue]}" = quoted ] || all_quoted=0
done

{
  printf 'refs-not-closing: Refs target(s) also scheduled to close:'
  printf ' #%s' "${intersections[@]}"
  printf '\n'

  for issue in "${intersections[@]}"; do
    detail="$(sentence_for_issue "$issue" closing)"
    if [ -z "$detail" ]; then
      printf "  #%s: GitHub reports a closing reference; no adjacent closing keyword was found, so inspect the Development sidebar link.\n" "$issue"
    else
      matched="${detail%%$'\t'*}"
      sentence="${detail#*$'\t'}"
      printf '    matched: %s\n' "$matched"
      printf '    sentence: %s\n' "$sentence"
    fi
    # The intersection is produced by the `Refs` occurrence and never by the
    # closing keyword, so show it whichever scan found something: printing a
    # correct `Closes` line alone shows the author text that did not fire and
    # points the remedy at the wrong sentence (#606).
    refs_detail="$(sentence_for_issue "$issue" refs)"
    if [ -n "$refs_detail" ]; then
      printf '    Refs match: %s\n' "${refs_detail%%$'\t'*}"
      printf '    Refs sentence: %s\n' "${refs_detail#*$'\t'}"
    fi
    if [ "${quoting[$issue]}" = quoted ]; then
      printf '    every Refs occurrence is quoted: fenced, in a code span, or blockquoted\n'
    fi
  done

  if [ "$all_quoted" -eq 1 ]; then
    cat <<'EOF'
  A `Refs #N` PR must not close N, and every `Refs` occurrence above is
  quoted — inside a fence, an inline code span, or a blockquote. Two routes
  reach that shape. If this pull request legitimately closes N, the quoted
  tokens are an archived round record arguing about N: de-parse them so they
  no longer read as references, leave the substance of the record intact, and
  disclose the edit. Otherwise the entry is a Development sidebar link:
  remove the link. Leave the closing-keyword sentence as it stands — on this
  shape it is the correct one, and editing it loses the close.
EOF
  else
    cat <<'EOF'
  A `Refs #N` PR must not close N. The closing graph can come from a
  closing keyword adjacent to the number in the body's prose or a Development
  sidebar link. Remove the link or rewrite an adjacent closing-keyword sentence
  so the number comes first (`#N is closed by hand`) or the number is omitted
  (`triage closes the issue by hand`). If the only match above is backticked,
  remove the Development sidebar link.
EOF
  fi
} >&2
exit 1
