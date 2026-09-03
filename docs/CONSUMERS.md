# Consumer setup

How a repo adopts the ceremony — bootstrap for a greenfield repo, a
conversion checklist for a repo carrying its own copy of the machinery,
and the policies that keep either honest afterwards. The doctrine (what a
release *is*, the doors, the guards, the drill) lives in
[../README.md](../README.md); this guide is the how-to. It is meant to be
sufficient on its own: a conversion executed from this guide should need
zero out-of-band knowledge, and gaps found while converting are filed as
edits to this guide (#12).

## Prerequisites

- **Repo shape**: work lands on a `main` default branch by PR; fork PRs
  are fine — the merge door rides `push` to `main`, never `pull_request`
  ([release.yml](../.github/workflows/release.yml#L70-L74), box#97), and
  the label read goes through the API
  ([lib/facts.sh](../lib/facts.sh#L88-L101)), so the ceremony never needs
  the PR's own context. No PAT, no secrets: every permission the flow uses
  is the caller-declared `GITHUB_TOKEN` grant.
- **Carry the release caller with the doctrine mirror**:
  `.github/workflows/release.yml` contains the single `uses:` line whose ref
  `docs-sync` reads to verify `.ceremony/`, so one pin governs machinery and
  doctrine instead of creating a second thing to bump. A repository that
  publishes no artifact still carries this caller: the pin lives here and the
  artifact hook is optional.
- **Pick the version backend**: `file` (a `VERSION` file — box, rig,
  incubator) or `package-json` (the `version` field, lockfile kept in sync
  on the post-release bump — cast). This is the workflow's one input; the
  full configuration surface of the ceremony is enumerated in
  [#1](https://github.com/heavy-duty/ceremony/issues/1) ("The
  configuration axes").
- **The `release` label must exist** before the first ceremony PR — it is
  the merge door's declared-intent read
  ([lib/facts.sh](../lib/facts.sh#L88-L101)). Bootstrap it via the labels
  sweep caller's `workflow_dispatch`
  ([Labels automation](#labels-automation)), or create it by hand,
  matching the core table
  ([actions/labels-reconcile/labels-reconcile.sh](../actions/labels-reconcile/labels-reconcile.sh#L369)):

  ```sh
  gh label create release --color 0E8A16 \
    --description "Release flow and version/packaging work"
  ```

## On-board a fleet-worked repo

The ordinary bootstrap paths below assume a human can land the first PR. A
repo the fleet will work has an earlier gate: **its queue taxonomy must exist
before the repo enters the fleet registry.** The taxonomy is normally created
by a dispatch in a workflow that a builder still has to land, but that builder
cannot claim the bootstrap issue until the queue labels exist. Resolve that
bootstrap-order problem explicitly: the operator hand-creates the minimum
set, the builder lands labels automation, the operator dispatches it, and only
after verifying the full taxonomy adds the repo to `repos.txt`.

The minimum hand-created set is `ready`, `release`, `claimed`, `blocked`,
`epic`, and `state:needs-human`. Do not retype their colors or descriptions.
Read the complete canonical rows from `core_label_rows()` at the same ceremony
ref the new repo will pin, then use those rows for the hand-created labels:

```bash
repo=OWNER/REPO
ceremony_ref=X.Y.Z # replace with the exact tag this repo will pin
minimum='^(ready|release|claimed|blocked|epic|state:needs-human)$'

gh api "/repos/heavy-duty/ceremony/contents/actions/labels-reconcile/labels-reconcile.sh?ref=${ceremony_ref}" \
  --jq .content | base64 --decode |
  awk -F '|' -v minimum="$minimum" '
    /^core_label_rows\(\) \{/ { in_function = 1; next }
    in_function && /^  cat <<.*EOF/ { in_rows = 1; next }
    in_rows && /^EOF$/ { exit }
    in_rows && $1 ~ minimum { print }
  ' |
  while IFS='|' read -r name color description; do
    gh label create "$name" --repo "$repo" --color "$color" \
      --description "$description" --force
  done
```

`state:needs-human` belongs in a *minimum* set for a reason: it is the one
state label the PR author sets by hand at handoff, and it is exactly what the
operator notifier sweeps for. Without it, the first PR can become mergeable
without telling anybody that the human now owns the move.

With those six labels present, a builder can claim and land the bootstrap
below, including both labels callers and `.github/labels.conf`. Immediately
after that PR merges, dispatch the sweep caller with taxonomy bootstrapping
enabled and wait for that exact run to succeed:

```bash
me="$(gh api /user --jq .login)"
dispatched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh workflow run labels-sweep.yml --repo "$repo" -f bootstrap=yes
run_id=
for attempt in {1..12}; do
  run_id="$(gh api -X GET \
    "/repos/$repo/actions/workflows/labels-sweep.yml/runs" \
    -f event=workflow_dispatch -f "created=>=$dispatched_at" \
    -f per_page=100 |
    jq -r --arg me "$me" \
      'first(.workflow_runs[] | select(.actor.login == $me) | .id) // empty')"
  [ -z "$run_id" ] || break
  sleep 5
done
test -n "$run_id" || { echo "labels bootstrap run did not appear" >&2; false; }
gh run watch "$run_id" --repo "$repo" --exit-status
```

**The resolver discriminates on `actor.login`, and nothing weaker does.**
The trigger job dispatches the sweep too, so a repository with any traffic
at all has other `workflow_dispatch` runs of this same workflow landing in
the same window. Measured on a trafficked board on 2026-08-27: of 100
`workflow_dispatch` runs that day, 98 were the trigger job's and 2 the
operator's. `--event workflow_dispatch … --limit 1` therefore takes
whichever run is newest and reports its conclusion as yours, and `gh run
list -u <login>` does not narrow it either — `-u` filters
`triggering_actor`, which is the operator's login on the trigger job's
dispatches as well. Only `actor.login` separates the two, and only the REST
representation carries it: `gh run list --json` has no actor member to
select (#505).

Do not treat six familiar-looking labels as proof that the dispatch ran.
Verify the repository contains every core row declared at the pinned ref:

```bash
expected="$(gh api "/repos/heavy-duty/ceremony/contents/actions/labels-reconcile/labels-reconcile.sh?ref=${ceremony_ref}" \
  --jq .content | base64 --decode |
  awk -F '|' '
    /^core_label_rows\(\) \{/ { in_function = 1; next }
    in_function && /^  cat <<.*EOF/ { in_rows = 1; next }
    in_rows && /^EOF$/ { exit }
    in_rows { print $1 }
  ' | sort)"
actual="$(gh label list --repo "$repo" --limit 1000 --json name \
  --jq '.[].name' | sort)"
missing="$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"))"
test -z "$missing" || { printf 'missing core labels:\n%s\n' "$missing" >&2; false; }
```

The first bootstrap dispatch also removes GitHub's six retired defaults:
`duplicate`, `invalid`, `question`, `wontfix`, `help wanted`, and
`good first issue`. That deletion is expected; `question` is a discussion in
this flow, and the other five are likewise outside the shared taxonomy.

Only after the successful run and the full-taxonomy comparison may the
operator add the repository to the fleet's `repos.txt`. Pointing the fleet at
it earlier turns a missing label from a setup omission into a partially
mutated claim that the builder cannot repair.

### The doctrine ref before a pin exists

A governed repo answers "which ceremony rules govern me?" with its pin:
`AGENTS.md` routes every role to `.ceremony/`, and `docs-sync` verifies that
mirror against the single `uses:` ref in `.github/workflows/release.yml`. One
pin, one ref. A fleet-worked repository that carries neither half — no
`.ceremony/` mirror and no workflow caller, so no pin — has no such ref, and
an instruction to read ceremony directly names none.

**A fleet-worked repository with no ceremony pin reads doctrine at the latest
published ceremony release tag, never at `main`.** The reason travels with the
rule: every other board in this fleet runs at a released tag, so a rule that
has not shipped should not reshape an unpinned board that no other agent is
reading the same way. Two agents given the same instruction on the same day
otherwise resolve it differently, and unshipped doctrine both adds and removes
work depending on which board it lands on (#548).

**The latest release is the newest published, non-draft, non-prerelease
release** — not the newest tag, which may be a prerelease or a tag no release
was cut from, and not what `VERSION` holds on the default branch, which names
the version being prepared rather than one that has shipped. Resolve it:

```sh
gh release view --repo heavy-duty/ceremony --json tagName -q .tagName
```

With no tag argument `gh release view` returns the repository's latest
release, which is the same read as the releases API's
`/repos/heavy-duty/ceremony/releases/latest`. Read the whole vendored
doctrine set at that tag — the files `docs/VENDORED.txt` declares — not a
mixture of refs. The rule governs only while the pin is
absent: once the repository carries one, the pin is the ref,
[as it is everywhere else](#version-pinning).

## Bootstrap a new repo

The greenfield path (incubator's, #16) — the repo never owns a copy of
the machinery at all:

1. **`VERSION` at `X.Y.Z-dev` — never bare.** A first version that never
   carried `-dev` hits the decide table's refuse row and has to ship by
   the tag door (the known first-release edge, cast#111;
   [lib/decide.sh](../lib/decide.sh#L70-L74)). Bootstrapping at `-dev`
   keeps the repo clear of it entirely. (`package-json` backend: the
   `version` field, same rule.)
2. **An armed changelog: a `CHANGELOG.md` preamble plus `changelog.d/`.**
   The changelog file starts as preamble only — no section; the first
   release writes the first one. The fragments directory beside it is the
   arming (#112): it carries a `README.md` marker naming the assembler and
   the doctrine — take ceremony's own
   [changelog.d/README.md](../changelog.d/README.md) at the pin — which is
   what keeps the directory tracked while it holds no fragments and what
   `changelog-armed` asserts. Every behavior-change PR then writes
   `changelog.d/<issue>.md` ([The changelog rule](#the-changelog-rule));
   the release PR assembles the section
   ([Assembling a release section](#assembling-a-release-section)).

   Fragment mode is available at `0.2.0` and later, and not in `0.1.0`.
   A consumer pinned to `0.1.0` bootstraps the legacy shape instead — the
   preamble plus an empty `## Unreleased` section for entries to land
   under — and converts on the pin bump to `0.2.0` or later; never mix
   refs to adopt it early.
3. **`drills/README.md`** defining what a drill *means* in this repo —
   each repo names its own
   ([the drill doctrine](../README.md#the-drill-doctrine)). Plain
   `drills`, not a dot-directory
   ([drill-recorded.sh](../actions/drill-recorded/drill-recorded.sh#L49-L52)).
4. **`.github/workflows/release.yml`** — the caller, verbatim from
   [Release workflow](#release-workflow) below.
5. **CI guard steps** in the repo's `ci.yml`:

   ```yaml
       - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
         with:
           # changelog-monotonic and changelog-assembled compare HEAD
           # against the merge base; a checkout that cannot resolve it is
           # a hard failure in CI, not a skip (a guard that can quietly
           # stop guarding is the failure shape these checks exist to
           # refuse).
           fetch-depth: 0
       - uses: heavy-duty/ceremony/actions/changelog-armed@<pinned-tag>
       - uses: heavy-duty/ceremony/actions/changelog-monotonic@<pinned-tag>
       # changelog-assembled is available at 0.2.0 and later, not in
       # 0.1.0. Adopt this step with the pin bump to 0.2.0 or later;
       # never mix refs. Green NOTICE on every non-release PR; on a
       # release PR it asserts the stamped section is exactly the
       # fragments it consumed.
       - uses: heavy-duty/ceremony/actions/changelog-assembled@<pinned-tag>
       - uses: heavy-duty/ceremony/actions/drill-recorded@<pinned-tag>
       # runner-isolated is available at 0.2.0 and later, not in 0.1.0.
       # Adopt this step with the pin bump to 0.2.0 or later; never mix
       # refs.
       - uses: heavy-duty/ceremony/actions/runner-isolated@<pinned-tag>
       - uses: heavy-duty/ceremony/actions/sha-pinned@<pinned-tag>
   ```

   `changelog-armed` and `drill-recorded` take
   `version-source: package-json` where that is the backend; every guard's
   inputs and defaults are in its `action.yml`
   ([actions/](../actions/)). Adopting the agent team flow adds the
   `docs-sync` step ([below](#adopting-the-agent-team-flow)).

   `sha-pinned` enforces the vendored rule that third-party actions and
   reusable workflows use a full lowercase commit SHA followed by a readable
   trailing comment. Adopt it only after pinning every existing reference,
   then add the guard in that same PR: adding the step first merely makes the
   known sweep red. Its two scan inputs are `workflows-dir` (default
   `.github/workflows`, direct `*.yml`/`*.yaml` children) and `actions-dir`
   (default `.github/actions`, one-level `*/action.yml`/`*/action.yaml`). A
   repo that keeps composite actions at `actions/`, as ceremony does, passes
   `actions-dir: actions`. Both directories may be absent. The scan is
   deliberately non-recursive, so workflow fixtures nested elsewhere do not
   become shipping policy by accident.

   Local `./` references and references owned by `GITHUB_REPOSITORY`'s owner
   are exempt. The latter keeps ceremony's one-release-pin model intact; use
   `first-party-owner` only to override that derived owner. With neither a
   repository value nor an override, no owner is exempt. The guard performs
   no network lookup and cannot judge whether a publisher is established;
   `docker://` references also remain outside it because image digests use a
   different syntax.

   Pin the commit a release tag ultimately names, not an annotated tag object.
   Inspect the ref first, then dereference when its object type is `tag`:

   ```sh
   gh api /repos/O/R/git/ref/tags/vX --jq .object
   gh api /repos/O/R/git/tags/<tag-object-sha> --jq .object
   ```

   The second command is required only for an annotated tag; its returned
   commit SHA is the value that belongs after `@`. `actions/delete-package-versions@v5`
   is a worked example where pinning the tag object's SHA would look plausible
   but name the wrong object. The trailing comment may be `# v4`, a full
   semantic version, or a date—the guard requires useful text but cannot
   prove that prose true.

   `runner-isolated` asserts that no workflow file which **executes
   PR-authored code** names a self-hosted runner you have not vouched
   for — such a file runs the branch's code, and unreviewed fork code
   must never execute on your own hardware
   ([#58](https://github.com/heavy-duty/ceremony/issues/58)). A file
   executes PR-authored code when it is `pull_request`-triggered,
   always, or when it is `pull_request_target`-triggered **and** checks
   out a PR ref — base-branch privileges running PR-authored code, the
   shape the guard was blind to until `0.7.2` (#395). A
   `pull_request_target` file that checks out no PR ref executes none of
   it and passes however it is routed. Self-hosted labels are read from
   `runs-on:` and from `with:` input values alike — quoted, flow or
   block-scalar (`runner: |`) — each value judged on its own: two inputs
   passed on one line are two runners, and vouching for one of them does
   not vouch for the other, at any nesting depth. A value is read to its
   own closing bracket, so a mapping or list written across several
   lines is scanned like any other, and a quoted scalar is opaque: a
   bracket or comma inside quotes is that value's text, not its end. It
   is read wherever it begins, too: a value written on the line
   **after** its key — a flow list or mapping, or a plain or quoted
   scalar such as a wrapped `'["self-hosted","ci-runner"]'` — is that
   key's value as much as a `- …` list is, and so is a block mapping under
   `runs-on:`: its `labels:` key is the runner spec's label set, read in
   both of that key's own spellings, while the mapping's other keys
   contribute nothing and close nothing, so a `group:` above the `labels:`
   does not hide it. The surviving gap is the `group:` key itself: it
   selects no label fragment, so a group named `self-hosted` with no
   `labels:` key beside it passes (#402). A plain scalar that **folds** onto further
   lines is read on its first line only, which it always was: it is the
   one value that spans lines with no bracket, quote or block indicator
   to follow, and it can only name a label containing spaces.
   An **alias** is its anchor's value — a
   `runner: *runner-input` passes the labels `&runner-input` names and
   is judged on them, and the anchor is found wherever the line writes
   one, inside a flow collection included — while a `*name` inside a
   **quoted** scalar is that scalar's own text and not an alias at all.
   A
   comment is the other way round — it is never part of a value, ends
   with its own line and closes nothing, so a `}` written inside one
   leaves the collection open and the labels below it are still read,
   and it may begin anywhere YAML lets one begin: after a space, after a
   `{`, `[`, `,`, `]` or `}` **in flow context**, or after a quoted
   scalar's closing quote. A `#` is part of a value only where it
   continues a plain scalar (`ci#runner`, and `a,#b` in block context,
   where a `,` may sit in one) or sits inside a quoted one. Every
   input's value is
   read this way whatever the key is called, so prose passed to a
   reusable workflow by a PR-code file is reported as a label set —
   documented rather than narrowed, which
   [discussion #403](https://github.com/heavy-duty/ceremony/discussions/403#discussioncomment-17996195)
   ruled on 2026-08-13: the callee names its own inputs and this guard
   never opens that file, so a key allowlist would be a false negative
   sized by somebody else's naming. It
   fires on the PR that first puts PR-authored code on an unvouched
   self-hosted label; the two unblocks are splitting the workflow and
   [vouching for the tier](#vouching-for-a-runner-that-may-execute-pr-code).
   A repo with **no** self-hosted runner still wants it: the guard's
   value is the day somebody adds one.

   This guide documents `main`. A marker is the literal token
   `**unreleased**` immediately followed by its issue citation (for example,
   `(#238)`); whitespace between them may include a line break. A citation is
   mandatory, because a marker the guard cannot trace is a marker it cannot
   prove false. A token inside an inline-code span is a mention, not a marker;
   spans are ignored individually, so unrelated inline code cannot hide one.
   A marker for this repository's own issue uses bare `#N`. Cross-repo
   citations such as `(crew#293)` satisfy the traceability rule but are not
   compared with this repository's release section. The ceremony-only
   `marker-check.sh` guard enforces these rules. The release PR that ships the machinery clears, in that same PR,
   every marker its own assembled section makes false: the section cites its
   issues, each marker cites the same issue, and the release PR's diff is the
   one place both halves are visible at once (#221). If an action does not exist at the
   consumer's pinned tag, adopt it with the pin bump to the first tag that
   carries it; never mix a moving or newer ref into an otherwise exact-pin
   consumer. In particular, `0.1.0` carries `changelog-armed`,
   `changelog-monotonic` and `drill-recorded` plus `docs-sync`, but not
   `changelog-assembled` or `runner-isolated`.
6. **`.github/workflows/refs-guard.yml`** — the body-aware guard is its own
   caller because `edited` is load-bearing: #200 gained its accidental
   closing keyword after the PR opened, with no push to wake ordinary CI.
   It costs the consumer one read-only workflow file and no other machinery:

   ```yaml
   name: Refs guard

   on:
     pull_request:
       types: [opened, edited, reopened, synchronize]

   permissions:
     contents: read
     pull-requests: read

   jobs:
     refs-not-closing:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
         - uses: heavy-duty/ceremony/actions/refs-not-closing@<pinned-tag>
   ```

   `refs-not-closing` is available at `0.6.0` and later (#218). Adopt this
   caller with that ordinary pin bump; never point only this file at a
   moving or newer ref.
7. **Labels automation** (optional but recommended): the two callers from
   [Labels automation](#labels-automation) — the event-facing labels
   caller and the sweep caller (#209) — plus `.github/labels.conf`
   (panel + the repo's `scope:*` rows) and `.github/labeler.yml` (the
   path→scope globs). Run the sweep caller's `workflow_dispatch` once —
   **this bootstraps the taxonomy, `release` label included** — and use it
   again whenever an operator needs a full-board sweep immediately.
8. **The artifact hook** (optional): `.github/actions/release-artifact/`
   per [The artifact hook](#the-artifact-hook). No hook → the source
   tarball is the package.
9. **Record this board in your operator's catalog.** Adopting the ceremony
   makes this repository one of the boards your operator governs, and
   nothing outside it records that it did. A roster re-derived on demand —
   scanning an organisation for the labels caller — is only ever as
   complete as the token running the scan: on `2026-08-30` three fleet
   identities enumerated 82, 41 and 36 of the same 82 repositories, so a
   gate written against that scan was clearable by credential rather than
   by work (#567). The answer is a checked-in list, and a list is only
   worth reading if joining it is part of joining.

   Add this repository to whatever tracked list your operator already
   keeps of the boards it governs. Where the operator keeps none, this is
   the step that creates one: a tracked file naming every governed board,
   in whatever format that repository already reads. No repository and no
   filename is required of you — where the list lives is the operator's
   call, not ceremony's. heavy-duty's own is
   [`catalog.yaml`](https://github.com/heavy-duty/infra/blob/main/catalog.yaml),
   named here as an example and not as a destination for your board; it
   sits in that operator's own state repository, so treat the link as a
   citation rather than as a page to open — nothing this step asks of you
   depends on reading it.

   This is not the fleet's `repos.txt` a second time. That registry
   answers which repositories the fleet *works*, and
   [On-board a fleet-worked repo](#on-board-a-fleet-worked-repo) gates
   entry to it on a verified taxonomy; the catalog answers which boards
   the operator *governs*. A governed board need not be fleet-worked, so
   ticking this step by pointing at `repos.txt` loses exactly the boards
   the census exists to count.

   Skipping this step fails no check; it removes the board from every
   later count. A board absent from the catalog is not enumerated by the
   censuses that a taxonomy change, a pin bump or a label retirement each
   run first — so those land without it, and the omission surfaces only
   when somebody scans by credential again (#576).

From there the flow is the doctrine: ordinary PRs write their fragment,
the ceremony PR makes
[the three stamps](../README.md#what-a-release-is), and the merge ships it:
a human presses by default, or an opted-in sweep presses and dispatches the
release caller with that exact merged head. The machine then transcribes.

## Convert an existing repo

The box/rig/cast path — the repo carries its own copy of the machinery
and hands it over. The conversion PR is release-flow work: label it
`release` if the repo's conventions ask for that, and either way it lands
as a green `NOTICE` no-op on main — the decide table's green rows exist
precisely so the machinery is safe to work on
([lib/decide.sh](../lib/decide.sh#L6-L12)).

- [ ] Replace `.github/workflows/release.yml` with the caller from
      [Release workflow](#release-workflow) — **whole file**, keeping its
      load-bearing comments. Check the result has **one** `push:` key
      carrying both filters: YAML maps are last-key-wins, and a second
      sibling `push:` silently kills a door (rig's review catch).
- [ ] Swap the guard *script* steps in `ci.yml` for the `uses:` steps in
      the bootstrap list above (with `fetch-depth: 0` on the checkout).
- [ ] Add `refs-guard.yml` from the bootstrap list with the same ceremony
      pin as the release caller and CI guard steps.
- [ ] Replace `labels.yml` with the caller from
      [Labels automation](#labels-automation) and add the sweep caller
      `labels-sweep.yml` beside it (#209); extract
      `.github/labels.conf` from the old reconciler's embedded config —
      the `panel=` roster line and the repo's `scope:*` rows
      ([the format](#labels-automation)). `.github/labeler.yml` stays as
      it is (path globs are inherently repo-specific).
- [ ] Convert the changelog to fragments (requires a pin at the first tag
      carrying fragment mode — not `0.1.0`): move every entry under
      `## Unreleased` to `changelog.d/<issue>.md`, verbatim — the filename
      is derivable from the entry's own `(#N)`, which is the *filename*
      rule and not the whole of what `(#N)` has to satisfy: a moved entry
      also meets the entry rules in
      [The changelog rule](#the-changelog-rule), the 300-character bound
      and the single citation group closing the entry. `## Unreleased`
      prose has not shipped, so an entry that misses either is rewritten
      here rather than carried in — an entry citing several issues folds
      them into its one closing group, `(#61, #62).`, and goes to the file
      for the first cited. Then delete the
      `## Unreleased` heading, and add the `changelog.d/README.md` marker
      ([bootstrap step 2](#bootstrap-a-new-repo)). Published sections stay
      byte-identical; `changelog-monotonic` proves that on the conversion
      PR, and `changelog-armed` refuses a surviving `## Unreleased` the
      moment the directory exists. Rewrite the repo's own contributor
      docs that say "add a line under `## Unreleased`" in the same PR —
      split either way, main lies for as long as the split lasts.
- [ ] Delete the now-shadowed copies — zero shared scripts remain:
      `.github/scripts/release-notes.sh` (box, cast) or
      `release-lib.sh` (rig), `changelog-armed.sh` (box),
      `changelog-monotonic.sh`, `drill-recorded.sh`,
      `labels-reconcile.sh`.
- [ ] Trim the repo's test suite to repo-specific tests: the machinery
      tests go — they live in this repo's `test/` now, run by its CI —
      while the repo's own surfaces stay (box/rig's install-channel halves
      of `test/release.sh`, cast's `install-sh` tests). A machinery test
      *file* goes whole when its subject moved (rig's
      `test/labels-reconcile.sh` sourced the deleted reconciler), and so
      do tests that pin the old workflow's shape — a grep or awk against
      `release.yml`/`ci.yml` internals fails against the caller stub, not
      because the stub is wrong (rig #13's conversion).
- [ ] Sweep the repo's other docs for pointers at the deleted paths —
      `drills/README.md` and any labels doc typically cite the old
      `.github/scripts/*.sh` by path; repoint them at the pinned actions.
      A repo carrying its own copy of a doc the mirror vendors (rig's
      root `LABELS.md`) retires it in the same PR: a hand-maintained
      copy beside a machine-verified mirror is the drift the mirror
      exists to end.
- [ ] Shrink CONTRIBUTING's release section to a pointer at
      [this repo's README](../README.md) plus what is genuinely per-repo:
      the drill meaning (`drills/README.md`), artifact notes, the
      changelog house style if it differs from
      [the portable rule](#the-changelog-rule).
- [ ] Record this board in your operator's catalog — the step
      [bootstrap step 9](#bootstrap-a-new-repo) names, owed here for the
      same reason: a converted repository is a governed board by exactly
      the same test as a bootstrapped one. Add it to whatever tracked list
      your operator already keeps of the boards it governs; where the
      operator keeps none, this is the step that creates one — a tracked
      file naming every governed board, in whatever format that repository
      already reads. No repository and no filename is required of you.
      heavy-duty's own is
      [`catalog.yaml`](https://github.com/heavy-duty/infra/blob/main/catalog.yaml),
      named as an example and not as a destination for your board; it sits
      in that operator's own state repository, so the link is a citation
      and not a page you need to open. This is not the fleet's `repos.txt`
      a second time: that registry answers which repositories the fleet
      *works*, the catalog which boards the operator *governs*, and a
      governed board need not be fleet-worked. A board absent from the
      catalog is not enumerated by the censuses that a taxonomy change, a
      pin bump or a label retirement each run first, so those land without
      it (#576).
- [ ] What stays, per repo, forever: `VERSION` (or the `package.json`
      version), `CHANGELOG.md`, `changelog.d/`, `drills/`, `.github/labeler.yml`,
      `.github/labels.conf`, the optional
      `.github/actions/release-artifact/` — the full kept-vs-moved table
      is in [#1](https://github.com/heavy-duty/ceremony/issues/1).

## Runner routing

The reusable `release.yml`, `labels.yml`, and `labels-sweep.yml` workflows
each accept one optional `runner` input and apply it to every job they own.
The value is JSON, even for one label: omit it to keep `ubuntu-latest`, pass
`'"ubuntu-22.04"'` to select another hosted label, or pass
`'["self-hosted","ci-runner"]'` to require both labels on a self-hosted
runner. A bare `ubuntu-latest` is invalid JSON and fails loudly; it never
falls back to the default.

These jobs carry the permissions declared by their callers. In particular,
`labels.yml` runs under `pull_request_target`: it still checks out and
executes no consumer PR code, but its write-scoped token now executes on the
selected hardware. **Route these to a runner isolated from anything the token should not reach — never to a host that is itself part of the deploy path.**
Self-hosted runners do **not** reset state between jobs unless run ephemerally.
Persistent installs therefore need consumer-owned cleanup, at minimum a
scheduled `docker system prune`. **One runner process executes one job at a
time.** A busy consumer needs several runner services. Several services on one
host are enough and require no per-job provisioning.

Keep these runners repo-scoped unless the organization can restrict a runner
group to selected repositories. On GitHub Free, an organization runner in the
Default group is available to every repository, including public repositories
where a fork PR supplies the workflow file and can name the runner label. The
`actions/runner-isolated` guard reads this `runner` input's **value** where
a caller spells it — `0.7.2` (#395) — but it still
does not follow the reusable-workflow call into the callee's own `runs-on:`,
nor resolve a runner group, matrix or expression, so consumers must enforce
this registration and isolation boundary themselves.

incubator's worked example has two guests on one `ci-server` host.
`deploy-box` is the sole guest with the Coolify/tailnet grant.
`ci-box` has no grants and carries the `ci-runner` label. Ceremony jobs go to
`ci-runner`, keeping them off deploy-path hardware and out of the deploy
runner's single-job queue.

### Vouching for a runner that may execute PR code

`actions/runner-isolated` takes one optional input,
`pr-code-runner-labels` — a comma-separated list of runner labels on which
you assert PR-authored code may execute — `0.7.2` (#395). It is empty by
default, and an empty allowlist vouches for nothing: a consumer that passes
nothing keeps the verdict it had on every file that executes PR-authored
code.

That is the input's compatibility claim, and it is deliberately narrower than
"nothing changes". The same release corrects the axis, and the correction
moves one verdict on its own: a file triggered by `pull_request_target` that
names a self-hosted runner but checks out **no** PR ref executes no PR code,
so it stops failing — it needs no allowlist entry and never did. If a pin
bump makes this guard go quiet on a file you expected it to flag, that is the
shape to check first: adding a PR-ref checkout to such a file brings the
failure straight back.

```yaml
      - uses: heavy-duty/ceremony/actions/runner-isolated@<pinned-tag>
        with:
          pr-code-runner-labels: pr-runner
```

**This input is an assertion, not a proof.** Whether a file checks out a PR
ref can be read off the file, so the guard derives it and never asks. Whether
a runner tier is isolated cannot be read off any file, so it is the one thing
left to you — and every assertion is a place the guard can be told something
false. The bar the label carries, all three clauses:

- it **publishes no artifact any trusted job consumes** — no image, package
  or cache that a later privileged job pulls;
- it **holds no credential the job should not have** — no registry login, no
  deploy token, no tailnet membership;
- it **reaches nothing the PR author should not reach** — network position
  included, not just secrets.

A tier that fails any clause is not vouched for by writing it here; it is
merely no longer guarded. `runs-on:` label sets are conjunctions, so naming
one label of a set vouches for the whole set — and naming `self-hosted`
itself vouches for **every** self-hosted tier you own, which is almost never
what you mean. A set is one **value**: where a job or a caller names two
runners — two `with:` inputs on one line, say — vouching for one leaves the
other guarded, and a set spread over `- ` list items, or over the lines of a
`{…}`/`[…]` collection, is read as the one set it is.

**Name the untrusted tier, never the trusted one.** incubator is the worked
example, and the direction of its split is the whole point:

| label | guest | publishes | in `pr-code-runner-labels`? |
|---|---|---|---|
| `ci-runner` | `ci-box` | **yes** — release images to `ghcr.io` | **never** |
| `pr-runner` | `pr-box` | nothing; no registry credential, not a tailnet member | yes |

`ci-runner` is the tier incubator's release seat uses, and it holds the GHCR
push. It is *more* trusted than a hosted runner, which is exactly why
PR-authored code must never be told it may run there. `pr-runner` is the tier
built to be spent: it publishes nothing, so the worst a malicious fork PR
gets is a box that already assumes it is hostile. The failure mode this table
exists to prevent is a reader opting in the runner their release job uses,
because that is the one whose name they know.

## Release workflow

The reusable release workflow implements both doors of the ceremony — the
merge door (merging the `release`-labeled ceremony PR ships it) and the tag
door (a bare `X.Y.Z` tag push as the manual fallback and backfill). The
design essay lives in the workflow's own header comment; the doctrine in
issue #1.

The consumer's **entire** `release.yml`:

```yaml
name: release
# Triggers and permissions MUST live here (a called workflow cannot define them):
on:
  # ONE push key, both filters — YAML maps are last-key-wins; a second sibling
  # `push:` silently replaces the first and kills a door (rig's review catch).
  push:
    tags: ["**"]      # every tag — a wrong tag must FAIL the assert loudly,
                      # never be skipped by a shape filter that didn't match
    branches: [main]
permissions:
  contents: write       # tag ref create + release create + the bump push
  pull-requests: write  # decide's label read; the bump-fallback `gh pr create`
  issues: write         # --label on that fallback PR rides the issues API
jobs:
  release:
    uses: heavy-duty/ceremony/.github/workflows/release.yml@<pinned-tag>
    with:
      version-source: file   # or: package-json
```

To route this caller, add one of these lines under its existing `with:` key:

```yaml
runner: '"ubuntu-22.04"'
runner: '["self-hosted","ci-runner"]' # choose one; do not repeat the key
```

To declare a tag namespace that is intentionally not a release, add this line
under the same `with:` key. Omit it to keep the empty default:

```yaml
non-release-namespace: drill/**
```

`version-source` selects `file` (a `VERSION` file — box, rig, incubator) or
`package-json` (the version field, lockfile kept in sync on the post-release
bump — cast). `runner` is the shared scheduling input described above.
`non-release-namespace` is an optional shell glob naming one tag namespace
that is deliberately not a release, for example `drill/**`. It defaults to
empty. A matching non-version tag exits successfully before the tree-version
assertion, release notes, artifact hook, or publication, and logs both the
matched namespace and that no release was created. With the empty default,
every tag follows the pre-existing release-or-loud-failure behavior unchanged.
Everything else a repo might vary is a change to the ceremony itself, made in
this repo, once.

Keep the merge door on `push` to `main` — never `pull_request`: a
`pull_request` run from a public fork gets a read-only `GITHUB_TOKEN` that
`permissions:` cannot raise (box#97), and every ceremony PR in this org is
cross-repo from a bot fork.

Bootstrap the version at `X.Y.Z-dev`, not bare: a first version that never
carried `-dev` hits the decide table's refuse row and has to ship by the
tag door instead (the known first-release edge, cast#111).

### The artifact hook

If the repository contains `.github/actions/release-artifact/action.yml`,
both doors invoke it — after the tag exists, before `gh release create` —
with the release `version` as input and `RELEASE_ASSETS_DIR` exported.
Contract for hook authors:

- Drop finished files into `$RELEASE_ASSETS_DIR`; every file there is
  uploaded as a release asset.
- Exit non-zero to abort the release.
- The hook owns its own toolchain (checkout is done; install node, docker,
  whatever it needs, itself).

A failed hook leaves the tag created but no release published. Recovery is
the tag door's semantics: fix the cause, then delete and re-push the same
tag (the tag door publishes for it), or run `gh release create` by hand from
a fixed tree. The merge door's nothing-exists assert will refuse a re-run of
the completed merge, by design.

No hook → no assets: for a pure-bash tree, GitHub's source tarball for the
tag IS the package. Worked examples land with the conversions: cast's tgz
build (#15) and incubator's GHCR image push (#16).

Native release-candidate cuts and deterministic rc re-arming are available
at `0.7.0` and later (#322). Adopt them with the ordinary pin bump and
doctrine re-sync; earlier pins do not carry the rc release path.

**[`ceremony-upgrade`](#ceremony-upgrade--the-bump-run-for-you) mechanises
this `0.7.0` crossing**, and crossing it is the whole of the migration: the
release workflow's `workflow_call` inputs are unchanged in name and in
requiredness across this tag, so a caller valid on an earlier pin is valid
here unchanged and the command asks your tree for no edit. The capability
arrives inside the called workflow, which moving the pin already moves.

## Labels automation

The labels automation is two reusable workflows since #209, adopted
together at the same pin:

- **`labels.yml`** — the event-facing half, called on PR and issue events.
  Two jobs: additive path-based `scope:*` labels, and a few-seconds
  `trigger` job that wakes the sweep by dispatching the consumer's sweep
  caller (`gh workflow run`, plain `GITHUB_TOKEN` — `workflow_dispatch` is
  one of the two documented exemptions from the token's no-retrigger rule,
  so no PAT anywhere in the path and no loop: the sweep dispatches
  nothing).
- **`labels-sweep.yml`** — the reconcile sweep: PR state, blockers,
  handoff, stale status, the issue work queue, and the `needs-ruling`
  invariants on both surfaces — the bare-flag check and the 7-day
  comment-only nudge (#52; the sweep reads that flag and never writes it).
  Detached from PR-triggered runs on purpose: all sweeps serialize through
  one shared concurrency group, and GitHub records every queue-displaced
  run as CANCELLED — harmless (the surviving sweep does its work) until it
  rode a `pull_request_target` run and the ❌ landed on that PR's checks
  as fake red CI that GitHub refuses to rerun (crew#250: `gh run rerun`
  and its `--failed`/`--job` forms all decline a queue-displaced run).
  Behind its own caller, a displaced sweep cancels on the
  Actions tab, attached to no PR; PR checks show `scope` and the green
  `trigger` only. **Two jobs since `0.7.7`** (#506): a `bootstrap` job that
  upserts the taxonomy and does nothing else, and the `reconcile` sweep
  above. They carry separate concurrency groups, so a bootstrap press waits
  in an effectively uncontended queue instead of competing with every sweep
  the board raises — the upsert being the one displaced work item no
  surviving sweep redoes. Both take the caller's `runner` input, and the
  caller's `with:` block, `permissions:` and `workflow_dispatch` inputs are
  unchanged: consumers get the split at their next pin bump with no edit.

The consumer keeps its path mapping in `.github/labeler.yml` and its
review panel plus scope taxonomy in `.github/labels.conf`.

`0.7.4` (#441) — the sweep also diagnoses four board shapes:
`idle`, `deep`, `cycle` and `stalled`. These diagnostics are comment-only: they
add no label, change no queue state and re-point no dependency edge. `deep`
posts on each chain head. `idle` does too when the graph has a head; when an
idle graph has none, it posts on each blocked cycle member instead. `cycle`
posts on every member because a cycle has no head. `stalled` posts on the head
alone — head meaning zero indegree, exactly as `deep` means it — so a cycle
member never carries it and the `cycle` family reports that set instead. It
fires only where three terms hold together, none of which implies another: the
head is `claimed`; the head has an open PR whose check rollup concludes
`FAILURE` (that alone — pending, absent or unreadable is a different sentence
from "this head is red"); and the chain it heads is at or above the stalled
threshold, counting the head itself. So a chain deep enough to trip `deep`
behind a `claimed` head whose PR is green is silent here, and so is a `claimed`
red head with nothing queued behind it — the first is ordinary work and the
second is one builder's fix round, and only the conjunction is the whole
chain's problem. That red-head term is graded with the same classifier that
decides `blocker:ci-red`, so the flag and that label cannot disagree, and
`rerun-owed` does not exempt a head from the flag: that label says the builder
owes nothing, not that the board does. Deduplication is per family and keyed to
the shape, so an unchanged shape does not re-post and a changed one does. The
`deep` and `stalled` thresholds are each a constant in the shared automation,
not a consumer setting in `.github/labels.conf`, and neither is derived from
the other — they answer different questions; a different threshold belongs in
that shared implementation. The comments themselves carry their current wording
and remedies rather than duplicating them here.

**Additive means additive** (available at `0.3.0` and later — #130): the
scope job's only label
write is `POST /issues/{n}/labels`, which adds the derived scopes and removes
nothing, so a label applied while the job runs survives it. Earlier tags used
`actions/labeler@v5`, which — even under `sync-labels: false` — replaces the
whole label set and silently drops a label written mid-job (ceremony#128 lost
its `release` that way). With the same pin bump, `.github/labeler.yml` keeps
its format but the accepted shape becomes exactly the one this guide has
always shown: label → `changed-files` → `any-glob-to-any-file`, block or flow
style, globs over `**`, `*` and `?` (`**` crosses `/`, the others do not; the
whole path must match). Any other labeler key — `all-globs-to-all-files`,
branch matchers, negations — fails the run loudly instead of being
half-honoured. The reconcile sweep also notices (never sets) when a non-draft
PR carries a bare `X.Y.Z` version differing from its base but no `release`
label. The merge itself is refused by nothing; what the release path refuses,
*after* that merge, is creating the release — the version transitioned and no
merged, release-labeled PR is behind the commit, so nothing publishes. At
`0.7.7` and later (#501) the sweep says so as **a comment on the pull
request**, once per episode, retracted when the label arrives; the
`::warning::` annotation it has always emitted stays beside it. That
annotation alone was the whole notice until `0.7.7`, and it attaches to the
check run that emitted it — a run on the sweep's own branch, so it is not
reachable from the pull request. ceremony#500 merged unlabelled and published
nothing with 21 such annotations standing behind it.

The complete event-facing caller is:

```yaml
name: labels
on:
  pull_request_target:
    # Fork PRs; these carry the head/draft/review facts state:* derives from.
    # labeled/unlabeled are the handoff wake (state:needs-human confirmed here);
    # synchronize re-derives on every push. review_requested/review_request_removed
    # (shipped in 0.3.0, ceremony#137) wake the sweep that clears
    # blocker:unrequested when the panel is asked.
    types: [opened, reopened, ready_for_review, converted_to_draft, synchronize, labeled, unlabeled, review_requested, review_request_removed]
  # Available at 0.2.0 and later (the first tag carrying ceremony#32); a
  # consumer pinned to 0.1.0 omits this block.
  issues:
    # Narrowed (#199) to the actions carrying a queue-state change the hourly
    # cron cannot wait one cadence for: opened → the mint→needs-triage check,
    # closed → the blocker-closes→ready self-heal, edited → a body rewrite of the
    # `Blocked by #N` declaration the sweep parses, reopened → a closed issue
    # re-entering the queue. Dropped: labeled/unlabeled/assigned/unassigned —
    # validation + the 48h claim clock, caught within one cadence, and
    # labeled/unlabeled were the issues-churn source. The handoff wake is
    # pull_request_target:labeled, not issues, so this leaves it intact.
    types: [opened, closed, edited, reopened]
permissions:
  contents: read
  checks: read          # mergeability/check-rollup read for PR state
  statuses: read        # commit-status rollup read for PR state
  actions: write        # the trigger job's `gh workflow run` dispatch of the sweep caller (#209)
  issues: write
  pull-requests: write
jobs:
  labels:
    uses: heavy-duty/ceremony/.github/workflows/labels.yml@<pinned-tag>
    # If the sweep caller below is named anything but labels-sweep.yml,
    # say so: `with: { sweep_workflow: <filename> }`. Ceremony's own
    # dogfood does (self-labels-sweep.yml).
```

To route the event-facing caller, add one of these lines under its existing `with:` key (alongside `sweep_workflow` when present); do not repeat the key:

```yaml
with: { runner: '"ubuntu-22.04"' }
with: { runner: '["self-hosted","ci-runner"]' } # choose one
```

And the complete sweep caller, `labels-sweep.yml` beside it — the hourly
cron lives HERE since #209, not on the labels caller:

```yaml
name: labels-sweep
on:
  # The consumer owns this cadence (#203). Hourly is the recommended default
  # when no other engine drives board state: the cron is then the sweep's only
  # wake for four transition classes — a review verdict landing (no
  # pull_request_review trigger on the labels caller), blocker:ci-red
  # set/cleared, blocker:conflict when another PR merges under this one, and
  # time-based stale / 48h claim-reclaim. The labels caller's events carry the
  # rest in seconds, one trigger-job dispatch away. Hourly trades ≤1h of
  # latency on those four while cutting nominal scheduled sweeps from four an
  # hour to one at GitHub's 1-minute floor. Do not delete the cron: it is their
  # discovery path. If another engine writes some of those transitions, only
  # the classes with no other writer bound the cadence; relax it only as that
  # list shrinks.
  schedule: [{cron: "0 * * * *"}]
  # A manual full-board sweep. A bare dispatch (input default "yes") also
  # bootstraps the taxonomy on a fresh repo. The labels caller's trigger job
  # wakes this workflow with bootstrap=no on every board event, so the
  # declared input is part of the contract: a dispatch naming an undeclared
  # input is refused, and the trigger job goes loudly red.
  workflow_dispatch:
    inputs:
      bootstrap:
        description: Bootstrap the label taxonomy before sweeping
        type: choice
        options: ["yes", "no"]
        default: "yes"
permissions:
  contents: read
  checks: read          # mergeability/check-rollup read for PR state
  statuses: read        # commit-status rollup read for PR state
  actions: read         # workflow-run nodes inside the check rollup — private repos do not imply it (incubator#60)
  issues: write
  pull-requests: write
jobs:
  sweep:
    uses: heavy-duty/ceremony/.github/workflows/labels-sweep.yml@<pinned-tag>
    # If this repo's PR-facing labels caller is named anything but `labels`,
    # pass that name: `with: { pr_workflow_name: <name> }`. The sweep exports
    # it as SELF_WORKFLOW so the label machinery's own check entries (scope,
    # trigger) never count toward blocker:ci-red — a red trigger means "fix
    # the caller", which no PR edit can do (#208 reads it).
```

To route the sweep caller, add one of these lines under its existing `with:` key (alongside `pr_workflow_name` when present); do not repeat the key:

```yaml
with: { runner: '"ubuntu-22.04"' }
with: { runner: '["self-hosted","ci-runner"]' } # choose one
```

Naming any permission sets every unnamed permission to `none`. Public
repositories allow check data to be read regardless, but a private consumer
needs the explicit reads above; without them the failure appears as an empty
`state:*` axis on the board rather than a red workflow run. The labels
caller's `actions: write` is different — it is required everywhere, public
repos included: the trigger job's `gh workflow run` is a write, and without
it every event run goes red at the trigger.

**The failure mode to know before bumping**: a consumer that bumps its pin
to a #209-carrying tag without adding the sweep caller keeps green-looking
silence nowhere — the trigger job goes **red on every PR and issue event**
(workflow-not-found; likewise on a sweep caller missing its `bootstrap`
input, or a labels caller missing `actions: write`), and event-woken sweeps
stop until the caller lands. That loudness is deliberate: never read
silence, or a green `scope` alone, as health. Make the adoption one atomic
PR — pin bump, sweep caller file, `actions: write` line together.

The `issues:` trigger is available at `0.2.0` and later — `0.2.0` is the
first tag carrying ceremony#32. A consumer pinned to `0.1.0` omits it. Adopt
it only by bumping every ceremony reference to `0.2.0` or later; never mix
refs to adopt it early. The type list has grown then narrowed across tags:
`0.2.0` (ceremony#32) shipped `[opened, labeled, unlabeled, assigned,
unassigned, closed]`; `0.3.0` (ceremony#144) added `edited` and `reopened`;
ceremony#199 narrows it to `[opened, closed, edited, reopened]` and relaxes the
cron to hourly, so a consumer picks up the smaller trigger surface at the pin
bump to the first tag carrying ceremony#199. The narrowing drops
`labeled`/`unlabeled`/`assigned`/`unassigned` — validation and the 48h claim
clock, which the hourly cron catches within one cadence, and `labeled`/
`unlabeled` were the issues-churn source — while **keeping** #144's `edited`/
`reopened`: those carry a queue-state change an event uniquely carries (a body
rewrite of `Blocked by #N`, and a closed issue re-entering the queue), so the
must-fail in ceremony#199 keeps them on events. `opened` drives the
mint→`needs-triage` check and `closed` the blocker-closes→`ready` self-heal;
the stub and ceremony's own caller stay byte-for-byte identical, the parity
#144 established.

The two-caller split (ceremony#209) is available at `0.4.1` and later. A
consumer pinned to `0.4.0` or earlier keeps the previous single-caller
shape — the labels caller carrying the cron, `workflow_dispatch`, and
`actions: read` — and adopts the split at the pin bump to `0.4.1` or
later. Never mix refs to adopt it early.

The migration is **one atomic PR** with exactly four edits — crew, the
consumer whose displaced-check evidence drove #209 (crew#227, crew#250),
is the worked example; written here against `0.4.1`, the first tag
carrying the split:

1. **Pin bump, every reference together** ([Version pinning](#version-pinning)):
   `0.4.0` → `0.4.1` in the labels caller's `uses:` line **and in every
   other ceremony `uses:` in the repo** — crew also pins in
   `release.yml` and its `ci.yml` guard steps. A repo on the doctrine
   mirror re-runs `docs-sync --fix` in the same PR.
2. **New file `.github/workflows/labels-sweep.yml`** — the sweep caller
   stub above, verbatim, `bootstrap` input included (the trigger's
   `-f bootstrap=no` dispatch is refused if the input is undeclared).
3. **The hourly cron RELOCATES — it is moved, never copied.** Delete the
   `schedule:` block (and the bare `workflow_dispatch:`) from the labels
   caller in the same edit that adds the sweep caller.
   **Warning**: a consumer that copies the sweep caller and leaves the
   old schedule on the labels caller gets DOUBLE sweeps — every cron tick
   fires both callers into the one shared `labels-reconcile` group — so
   displacement goes **up**, and the fix reads as the bug getting worse.
4. **`actions: write` on the labels caller** — consumers carry
   `actions: read` today (crew does); the trigger job's `gh workflow run`
   is a write. The sweep caller keeps `actions: read`.

Bump without the sweep caller and the trigger job goes red on every PR
and issue event — the loud failure mode above — so never split these
four edits across PRs.

**[`ceremony-upgrade`](#ceremony-upgrade--the-bump-run-for-you) performs
this migration for you**: point
it at `0.4.1` from the root of your checkout and it moves every ceremony
ref, writes `.github/workflows/labels-sweep.yml` from the stub above,
relocates your cron onto it with your own cadence, grants `actions: write`,
and re-syncs the mirror — the same four edits, in one commit's worth of
tree. It stops at `0.4.1` whatever tag you asked for, tells you the pin it
left you at, and grades the rest of the move the next time you run it. The
four edits above stay the procedure: they are what the command performs,
they are what a reader checks its output against, and they are the answer
where it refuses. It refuses whenever it cannot anchor an edit
unambiguously — a sweep caller already in the tree under either spelling,
two `schedule:` keys, a `workflow_dispatch:` carrying inputs of your own,
no `permissions:` block, an `actions:` grant it did not write (anything
other than one `actions: read`, a write you granted by hand included, and
the value is compared as written, so a quoted `'read'` is not one), a
`name:` whose quoting it cannot decode, a `with:` it cannot read, an `on:`
block carrying nothing but the two triggers it relocates (performing the
edits there would leave your caller with no trigger at all, and what
triggers it instead is yours to decide) — and a
refusal leaves the tree byte-identical, so the hand procedure is always
still open to you. Every refusal names the file, the line and the shape,
so what to do by hand is one edit away from what it told you.

`pull_request_target` is intentional: fork PRs need the base repository's
token to write labels. The reusable workflows execute no PR code. They check
out only the consumer's base branch and the pinned ceremony implementation.
The #52 ruling invariants ride exactly these triggers — but the caller above
is no longer the #18 shape, so adopting current triggers is a stub edit, not
a bare pin bump. `review_requested` and `review_request_removed` on
`pull_request_target:` shipped in `0.3.0` (ceremony#137) — the wake that
clears `blocker:unrequested` the moment the panel is asked, without which a
quiet repo wears that flag until the backstop cron; a consumer picks them up
by pinning `0.3.0` or later, never through mixed refs.

`.github/labels.conf` has one mandatory panel setting, one mandatory
`triage-actors` setting, zero or more optional per-author panel rows, and
then zero or more scope rows:

```text
panel=claude-bot example-codex-bot example-grok-bot
panel[example-builder]=example-codex-bot example-grok-bot
triage-actors=example-triage-bot
scope:cli|C5DEF5|The command-line surface
scope:docs|C5DEF5|Documentation
```

The mandatory `triage-actors=` setting is likewise accepted at `0.2.0` and
later, and not by `0.1.0`. At that tag the file contains `panel=` plus scope
rows only; adding `triage-actors=` is a parse failure, not an ignored setting.
Add it at the same pin bump as the `issues:` trigger — `0.2.0` or later —
never before it and never through mixed refs.

The optional `panel[<login>]=` rows are available at `0.5.0` and later (#224). A row names
the effective panel for PRs authored by exactly that login — the reconciler
computes that PR's required set from the row, minus the author as always —
and every other author keeps the base `panel=`, which stays mandatory. The
panel is configured or it is the base one: ceremony never infers a reviewer
set from the model behind a login. On any earlier pin a bracketed row is a
**parse failure, not an ignored setting** — the same shape `triage-actors=`
bought at `0.2.0`, but harsher in practice: the reconcile job dies on every
PR event and every sweep until the row is removed, so the whole label board
goes down. Add the row only at or after the pin bump that carries it, never
before it and never through mixed refs.

**[`ceremony-upgrade`](#ceremony-upgrade--the-bump-run-for-you) crosses this
tag for you**, and crossing it is the whole of the migration: `0.5.0` asks a
tree moving forwards for nothing. Point the command at `0.5.0` and it moves
every ceremony ref and re-syncs the mirror, and that is the migration
performed — it writes no `panel[<login>]=` row, because the row is optional
and which logins are on which panel is yours to choose. The hazard the
paragraph above names is a move *backwards* across this tag with a bracketed
row already written, and the command refuses every backwards move outright,
so there is no shape of this crossing it performs half.

Both actor lists are whitespace-separated. `triage-actors` names the identities
allowed to mint issues without the sweep applying `needs-triage`. Label rows use exactly
`name|color|description`; blank lines are ignored and extra pipes are refused.
There are no comment lines: every non-blank line must be the `panel=`
setting, a `panel[<login>]=` row, the `triage-actors=` setting, or a label
row, so `#`-prefixed prose is a parse failure, not a comment (rig #13's
conversion found this the hard way — keep the file data only).
Core state, blocker, work-queue, and release labels come from ceremony. Scope
rows remain consumer-owned because paths and surfaces differ by repository.

After adding the callers and configuration, dispatch the sweep caller once
to bootstrap labels on a fresh repository. A bare dispatch is also the
operator's general manual full-board sweep — the answer when the board
looks wrong now rather than after the next scheduled cadence:

```sh
gh workflow run labels-sweep.yml -R <owner>/<repo>
```

Ceremony dogfoods the callers under the filenames `self-labels.yml` and
`self-labels-sweep.yml`, so the equivalent command in this repository
substitutes that filename. Scheduled and trigger-driven runs only
reconcile; they do not repeatedly upsert the taxonomy (the trigger's
dispatch carries `bootstrap=no`). **The taxonomy changes only on a
bootstrap dispatch** — the reconciler's one gate is that `bootstrap`
input, so no board event and no cadence can install, rename or retire a
label. When a ceremony pin bump adds a core label, bump the pin first and
then re-dispatch: the label arrives on that dispatch and on no earlier
run. That re-dispatch is the press below, and it is verified rather than
assumed. The scheduled sweep warns when the pinned taxonomy declares a
core label the repository lacks, which is the nag in the meantime (#472).

### A bootstrap press that reports whether it ran

The bare dispatch above needs no check, because a displaced one costs
nothing: a reconcile sweep evicted from the queue is redone by the next
sweep, and the board converges either way. **A bootstrap press is the one
dispatch that is not lossless.** Every sweep that could survive in its
place is one of the reconcile-only runs named above — which is why an
evicted reconcile sweep costs nothing and an evicted bootstrap press costs
the row it was pressed for.

The queue is the shared `concurrency` group every sweep in the repository
runs under, and GitHub holds one running run plus one pending run there. A
third arrival evicts the pending one, which ends `cancelled` having
executed no steps. `gh workflow run` prints `✓ Created workflow_dispatch
event` for that press exactly as it does for one that runs, so at the
terminal the press that installed the taxonomy and the press that
installed nothing are the same two words. Resolve the run and read its
conclusion:

```bash
repo=<owner>/<repo>
ceremony_ref=<pinned-tag>
me="$(gh api /user --jq .login)"
dispatched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh workflow run labels-sweep.yml --repo "$repo" -f bootstrap=yes
run_id=
for attempt in {1..12}; do
  run_id="$(gh api -X GET \
    "/repos/$repo/actions/workflows/labels-sweep.yml/runs" \
    -f event=workflow_dispatch -f "created=>=$dispatched_at" \
    -f per_page=100 |
    jq -r --arg me "$me" \
      'first(.workflow_runs[] | select(.actor.login == $me) | .id) // empty')"
  [ -z "$run_id" ] || break
  sleep 5
done
test -n "$run_id" || { echo "bootstrap dispatch never appeared" >&2; false; }
gh run watch "$run_id" --repo "$repo" --exit-status
```

The resolution discriminates on `actor.login` for the reason given under
[On-board a fleet-worked repo](#on-board-a-fleet-worked-repo): the trigger
job dispatches this same workflow, so on any trafficked board the newest
`workflow_dispatch` run is almost certainly not yours, and `-u` filters
`triggering_actor`, which does not separate the two.

**A `cancelled` conclusion here means the taxonomy was not touched.** It is
not an error and not a transient. It is eviction from the shared queue: the
run executed no steps, and every label the press was for is still absent.
The correct response is to press again — re-run the block above, and keep
pressing until it exits zero. Do not go looking at the pin. A pin that is
behind fails the run or leaves rows missing afterwards; it does not cancel
the run.

**Where several presses in a row have been evicted, create the rows by
hand.** This is the same escape hatch the on-boarding section above uses
for the bootstrap-order problem, and it is evidence and not a workaround
around the check: the rows come from `core_label_rows()` at the ref the
repository is pinned to — the same source a bootstrap dispatch upserts
from — and the reconciler upserts rather than replaces, so a later
surviving press makes them canonical either way.

```bash
gh api "/repos/heavy-duty/ceremony/contents/actions/labels-reconcile/labels-reconcile.sh?ref=${ceremony_ref}" \
  --jq .content | base64 --decode |
  awk -F '|' '
    /^core_label_rows\(\) \{/ { in_function = 1; next }
    in_function && /^  cat <<.*EOF/ { in_rows = 1; next }
    in_rows && /^EOF$/ { exit }
    in_rows { print }
  ' |
  while IFS='|' read -r name color description; do
    gh label create "$name" --repo "$repo" --color "$color" \
      --description "$description" --force
  done
```

`--force` makes that idempotent, so it is safe over a partially applied
press. Confirm the result with the full-taxonomy comparison under
[On-board a fleet-worked repo](#on-board-a-fleet-worked-repo) — six
familiar-looking labels are still not proof that the dispatch ran.

### Letting the sweep merge a converged PR

*Only humans merge* is this organization's default and stays the default
here. A repository may delegate that one press to the reconciler, and this
subsection is the whole of what that costs. It is a diff you apply
deliberately: the stubs above pass no auto-merge input and grant no write,
so a repository that copies them is unaffected by everything below.

**1. The four inputs.** All live on the **sweep** caller and default inert.
The merge toggles govern disjoint sets: `auto_merge` selects ordinary PRs and
`auto_merge_release` selects `release`-labelled PRs.

| input | accepted | default | what it does |
|---|---|---|---|
| `auto_merge` | `off`, `merge`, `squash`, `rebase` | `off` | governs ordinary PRs; the non-`off` value is their merge method |
| `auto_merge_release` | `off`, `merge`, `squash`, `rebase` | `off` | governs release PRs; the non-`off` value is their merge method |
| `post_merge_workflow` | a workflow filename or name in this repository | *(empty)* | dispatched once after a merge this sweep performed; empty dispatches nothing |
| `release_workflow` | the release caller's filename or name | *(empty)* | dispatched with `merged-sha` after a release merge; empty prevents release auto-merges |

Any other merge-toggle value fails loudly rather than being read as `off`.
Workflow names are not validated here: existence, a `workflow_dispatch:`
entrance and token access are questions `gh workflow run` answers by failing.

```yaml
jobs:
  sweep:
    uses: heavy-duty/ceremony/.github/workflows/labels-sweep.yml@<pinned-tag>
    with:
      auto_merge: squash            # off | merge | squash | rebase
      auto_merge_release: merge     # independent; omit to keep releases human
      post_merge_workflow: ci.yml   # omit to dispatch nothing
      release_workflow: release.yml # required when auto-merging releases
```

Add those under the sweep caller's existing `with:` key alongside
`pr_workflow_name` and `runner` when present; do not repeat the key.

**2. The two permission changes, on the caller.** A called workflow cannot
raise what its caller grants (box#97, as at
[Release workflow](#release-workflow) above), so these go on **your**
`labels-sweep.yml` and nowhere else. Change the sweep caller's `contents:
read` to `contents: write` — the merge is a write to `main` — and its
`actions: read` to `actions: write`, which `gh workflow run` needs for either
dispatch. Take `actions: write` only if you set a workflow input;
`contents: write` only if you set a merge toggle. **A consumer that changes
neither permission is unaffected by this whole feature**, inputs included:
without `contents: write` the merge simply fails and is logged.

**3. What the reconciler refuses to merge**, in the order it asks, and it
merges only when all five pass:

1. **Not opted in** — the governing toggle is `off` (`auto_merge_release` for
   a release PR, `auto_merge` for every other PR).
2. **Not this pass's own `state:needs-human` verdict.** The trigger is the
   conclusion this sweep just computed from the PR's blockers, draft state
   and current-head approvals — **never the `state:needs-human` label**,
   whoever set it. A builder, a reviewer or an operator who applies that
   label by hand merges nothing: the sweep re-derives the verdict from
   scratch every pass, so a hand-set label that the facts do not support is
   corrected rather than obeyed. The label being writable by anyone is
   exactly why it is not the trigger.
3. **Release dispatch absent** — a release PR is refused when
   `release_workflow` is empty, even if `auto_merge_release` is on.
4. **Not authored by a fleet login** — the author must appear in this
   repository's `.github/labels.conf`, in `panel=`, in any
   `panel[<login>]=` row, or in `triage-actors=`. A human's PR and an
   outside contributor's PR are never auto-merged.
5. **Not `MERGEABLE`** — GitHub's own mergeability, so a conflicted or
   blocked PR is refused.

Two locks, not one: the head is re-read immediately before the merge and
the merge itself is pinned to that SHA, so a push arriving in the seconds
between the grading and the press loses the race rather than the review.
Every merge the sweep performs posts a provenance comment on the PR naming
the head, the method and the setting that authorised it. A release-label
change in either direction during confirmation refuses rather than reselecting.

**4. The push-run cost — read this before opting in.** A commit merged with
the workflow's own `GITHUB_TOKEN` raises **no `push` event**, so a `push`-
triggered workflow does not run and your `main` stops being graded. Nothing
goes red; it goes quiet, which is worse. Two lines fix it, and you need
both:

- name that workflow in `post_merge_workflow` on the sweep caller;
- add `workflow_dispatch:` to that workflow's **own** `on:` triggers, since
  a workflow without it cannot be dispatched at all.

A failed dispatch is logged and non-fatal: the merge has already happened
and stands.

For a release auto-merge, overlay this entrance and pass-through on the
consumer release caller from [Release workflow](#release-workflow), then name
that caller in `release_workflow`:

```yaml
on:
  workflow_dispatch:
    inputs:
      merged-sha:
        description: Full release-PR head SHA already merged to main
        required: true
        type: string
jobs:
  release:
    with:
      merged-sha: ${{ inputs.merged-sha }}
```

The sweep dispatches it only after the release merge, using the exact head it
graded and pinned. A failed release dispatch is loud and non-fatal because the
merge already stands.

**5. The approval-latency note.** The event-facing labels caller carries no
`pull_request_review` trigger, so the round's final approval wakes nothing
and the merge waits for the next scheduled sweep — up to an hour on the
recommended cron. A consumer that wants the press to follow the approval
adds the trigger to its **own** labels caller:

```yaml
  pull_request_review:
    types: [submitted]
```

**6. The stubs above stay minimum-permission and are not edited by this.**
The copyable sweep caller keeps `contents: read`, keeps `actions: read` and
passes neither input; the copyable labels caller keeps its trigger list as
shown. Opting in is the diff in points 1, 2 and 5 applied on purpose, never
the default anyone pastes.

## Rerun servicing

`0.7.4` (#424) — one more caller, adopted at the same pin as the two
above and independent of them.

A fork PR's `pull_request` run lives in the **base** repository, and rerunning
it needs `actions: write` there. No fleet identity holds that right — builders
are fork authors and the review bots measure `triage: true` and nothing more —
so a head that is red on a flaky runner used to wait for a human to press the
button. `rerun-owed` names that state; `ci-rerun.yml` services it. The builder
sets the label with its evidence comment (`🔁 rerun owed at head <sha>`), and
this workflow starts the one rerun, removes the label, and comments the new
attempt's URL.

Four gates are measured at service time and none is inherited from the label:
the label's actor is a fleet identity named in this repository's own
`.github/labels.conf` — the `panel=` line, a `panel[<login>]=` row's bracketed
login or its listed reviewers, or the `triage-actors=` line — the
PR's head still is the one the evidence names, the newest non-successful run at
that head concluded `failure` — a cancelled or in-flight run is not a verdict
(#139, #209) — and that run is on attempt 1. **A refusal leaves the label
standing** and comments which gate refused and what a human would have to do;
only a started attempt clears it.

Which runs are candidates is bounded the same way. A `pull_request_target` run
carries the PR **head's** SHA, so every workflow the label event wakes — your
`labels.yml`, this workflow itself, any other caller triggered on `labeled` —
appears in the run list at that head alongside the checks. None of them is the
run the label is about, so a candidate must have been **created before the
evidence comment that names the head**: the builder evidenced a head it saw
red, and a run that did not exist when that comment was written cannot be the
one it names. Nothing is filtered by workflow name or by event kind, so a red
`pull_request_target` check of your own — as unrerunnable by a fork author as
any other — is serviced like the rest, as long as it was there to be
evidenced.

The job holds a privileged token, so what it does is bounded by construction:
it checks out this repository's default branch and the pinned ceremony
implementation, never the PR head, runs no PR-authored code, and makes API
calls only. There is no schedule and no retry — it acts on one label event and
stops.

```yaml
name: ci-rerun
on:
  # pull_request_target, not pull_request: a fork PR's pull_request run holds a
  # read-only token and can neither rerun a run nor remove the label.
  pull_request_target:
    types: [labeled]
permissions:
  contents: read        # .github/labels.conf (the fleet roster) and the implementation — never the head
  actions: write        # the rerun no fork PR author can start; the whole reason this exists
  pull-requests: write  # remove rerun-owed, post the outcome
jobs:
  ci-rerun:
    uses: heavy-duty/ceremony/.github/workflows/ci-rerun.yml@<pinned-tag>
```

To route it, add one line under a `with:` key:

```yaml
with: { runner: '"ubuntu-22.04"' }
with: { runner: '["self-hosted","ci-runner"]' } # choose one
```

**Copy the `permissions` block or the workflow refuses every time.** Naming any
permission sets every unnamed one to `none`, and each of these three is load-
bearing: without `actions: write` the rerun call comes back `403` and the
workflow goes red with the label still standing; without `pull-requests: write`
it can neither clear the label nor say why; without `contents: read` the
checkout of this repository's default branch fails, so the job never reaches
the gate that reads `.github/labels.conf` at all. A consumer that adopts the
label without this caller
gets the state and no servicing — which is where the fleet was before #424, and
the operator services it by hand.

**The roster is the second precondition, and it is measured against your own
conf.** A consumer whose `.github/labels.conf` names none of the identities
that set the label gets a refusal at gate 1 every time — the happy path above,
where the builder sets the label with its evidence comment and the rerun
starts, does not happen until the conf names that builder by one of the fields
the gate reads. So read your own file, and ask of it the question the gate
will: does it name whoever will actually set `rerun-owed` here? Gate 1 reads
three fields, listed with the gates above — the `panel=` line, a
`panel[<login>]=` row (its bracketed login as much as the reviewers it lists),
and the `triage-actors=` line — and a conf whose roster is review bots alone
answers **no** for every builder who is not also a reviewer. The skeleton in
`.github/labels.conf`'s own section above is the other way round: it carries a
`panel[example-builder]=` row, and a bracketed login is a fleet identity on
its own, so an adopter who copies it unchanged has a builder in the roster and
is **admitted**. The precondition bites the repository that drops
that row, or never writes one, and then has a builder set `rerun-owed`. Who
belongs in that roster is the repository's own call and is not something this
workflow decides: it reads the file and refuses anyone absent from it, and the
refusal comment names both the actor and the file so the fix is one edit away.

## Doctrine mirror

Machinery is consumed by reference — GitHub fetches the workflows and
actions above from the pin at run time — but documents have no runtime: an
agent reads the working tree it stands in. So the agent-facing doc set
declared by ceremony's `docs/VENDORED.txt` is vendored into each consumer at **`.ceremony/`**,
byte-identical to ceremony at the pin, plus a generated `.ceremony/README.md`
marking the directory machine-managed. `actions/docs-sync` owns the copy:
`--fix` writes it (and deletes what the manifest dropped — mirror means
mirror), `--check` re-diffs it in CI on every PR, so a hand edit or a stale
pin goes red instead of quietly governing.

`RELEASES.md` joins that mirror with the first tag carrying ceremony#248,
and is available at `0.6.0` and later: consumers add `.ceremony/RELEASES.md`
only with the ordinary pin bump and re-sync, never by copying it ahead of
their pinned doctrine set.

**[`ceremony-upgrade`](#ceremony-upgrade--the-bump-run-for-you) mechanises
this `0.6.0` crossing**: its plan names `.ceremony/RELEASES.md`, and the
end-of-run mirror re-sync writes it through `docs-sync --fix`. The same plan
says `refs-not-closing` becomes available, but the command writes no
`.github/workflows/refs-guard.yml`; adopting that optional caller remains the
consumer's own call under [Bootstrap a new repo](#bootstrap-a-new-repo).

### Read the manifest, never a copy of it

Anything on the consumer's side that needs to know *which* documents are
vendored — a re-vendor script, a `docs-sync` equivalent, the task list of a
conversion issue — reads **the pin's `docs/VENDORED.txt`** and never names
the files itself. The manifest is available at the pinned ref from `0.1.0`
and later — it shipped with `actions/docs-sync` itself (ceremony#19), in the
same commit, and that tool has read it rather than a list since — and it is
one path per line, relative to ceremony's root, blank lines ignored:

```sh
# the vendored doc set at the ref this repo is pinned to
curl -fsSL "https://raw.githubusercontent.com/heavy-duty/ceremony/<pinned-tag>/docs/VENDORED.txt"
```

That is the whole benefit: a doctrine file added in ceremony — `RELEASES.md`
was the last, ceremony#248 — reaches every consumer at its next **ordinary
pin bump**, with **zero list edits** anywhere. A hardcoded list propagates
nothing, and its staleness is silent rather than red: `docs-sync --check`
asserts byte-identity for the files the list names and says nothing at all
about one it omits, so a consumer keeps a green guard while governing
itself with doctrine it no longer has.

What makes reading the manifest *sufficient* — rather than merely better
than a copy — is that ceremony's CI now refuses a root doctrine file that is
declared in neither the manifest nor a short in-script exemption list
(`.github/scripts/vendored-check.sh`), so the manifest at a tag is the
complete set as of that tag. That guarantee holds at `0.6.0` and later
(#251); the manifest is worth reading at every earlier pin regardless, since
it is what `actions/docs-sync` has always mirrored.

The consumer's ci.yml gains the guard alongside the others:

```yaml
      - uses: actions/checkout@v4
      - uses: heavy-duty/ceremony/actions/docs-sync@<pinned-tag>
```

`mode` defaults to `check`. There is no ref input: the action reads the pin
from the consumer's own `.github/workflows/release.yml` — the same single
`uses: …/release.yml@<ref>` line that pins the machinery, so one pin governs
machinery and doctrine alike, and a second pin cannot fall out of sync.

**Bootstrap on adoption**: add the release and labels callers first (the pin
must exist — the mirror is verified against it), then run `--fix` once from
the repo root and commit `.ceremony/` together with the callers:

```sh
curl -fsSL "https://raw.githubusercontent.com/heavy-duty/ceremony/<pinned-tag>/actions/docs-sync/docs-sync.sh" \
  | bash -s -- --fix
```

If the repo has no root `AGENTS.md`, `--fix` also scaffolds the thin stub
that routes agents to `.ceremony/AGENTS.md` — created once, never
overwritten; it is per-repo content the moment you edit it, so `--check`
asserts only that it exists.

Bumping the pin re-syncs the mirror in the same PR —
[the pin-bump procedure](#the-pin-bump-procedure).

### The guarded scaffold — ceremony owns a block, you own the rest

`.github/pull_request_template.md` is a third kind of file, and it is neither
of the two above. It cannot join the mirror: a pull request template only
works where GitHub reads it, and `.ceremony/` is not that place. It cannot be
a stub either — a file scaffolded once and never revisited sits at the
version it was written from while the machinery that renders into it moves
on, which is the measured failure this exists to stop.

So ceremony owns a **delimited region** of it and you own every other byte:

```
<!-- ceremony:pr-template:start -->
…ceremony's template at your pin, verbatim…
<!-- ceremony:pr-template:end -->
```

The markers are HTML comments, so they render as nothing in a pull request.
They are written by `--fix` and do **not** exist in ceremony's own copy of
the file, which is what keeps the comparison exact: the block's bytes and the
source's bytes are one thing to diff, not two.

**[`ceremony-upgrade`](#ceremony-upgrade--the-bump-run-for-you) mechanises the
`0.7.8` crossing**: its plan names this guarded-scaffold edit, and the mirror
re-sync at the end of the run writes the block through `docs-sync --fix`
rather than giving the upgrade command a second writer or a second reader of
the scaffold manifest.

- **`--fix`** replaces the block and touches nothing outside it. A
  *"Deployment notes"* section you added below, a house preamble above —
  both survive every future bump, byte for byte. Where the file exists with
  no block, `--fix` **appends** one rather than overwriting: a
  hand-maintained template is content, not garbage. Where the file does not
  exist, it is created carrying the block alone.
- **`--check`** fails at the mirror's severity — not a warning — when the
  file is missing, carries no block, or carries a block that has drifted from
  your pin.
- **Broken markers are a refusal, in both modes.** A start with no end, or a
  second start, means the block's boundaries are unknown, and every repair
  from there guesses at which of your bytes are ceremony's. Fix the markers
  by hand and re-run `--fix`; the tool will not delete content below a
  truncated block to make itself succeed.

The set is read from **the pin's `docs/SCAFFOLDED.txt`**, exactly as the
mirror's set is read from `docs/VENDORED.txt` and for the same reason: what
is scaffolded is decided at the pinned ref, so a bump that adds or drops one
re-shapes it in the same PR with no second list to maintain. It is one path
per line, relative to ceremony's root, blank lines ignored. A ref that
carries no such file has no guarded scaffolds and syncs exactly as it always
did.

The guarded scaffold is available at `0.7.8` and later (#559). **The pin bump
and the `--fix` run are one PR.** A bump onto this ref reds `docs-sync --check`
until the block exists, the same way a bump that adds a doctrine file reds
it until the mirror is re-synced — so run `--fix` from the repo root in the
bump PR itself and commit `.github/pull_request_template.md` alongside
`.ceremony/`. Splitting them leaves the default branch red in between, and
the repair is a second PR nobody scheduled.

## Requesting a doctrine change

The section above is how a document **reaches** you, and it is one-way by
construction: the marker in every `.ceremony/README.md` says these files are
never edited where they land. That leaves the opposite question unanswered —
what you do when the doctrine you were handed is itself the problem. This
section is the answer. It is a **route and not a mechanism**: nothing
automated crosses a repository boundary, and this repository is never told
who its consumers are or what they run.

**The address is a discussion here**, the door everything else already comes
through — `TRIAGE.md` opens *"You are the only door issues come through.
Humans and agents open discussions."* A request that arrives from a consumer
is not special enough to earn a second door, and a second door is how one of
them rots. Open it in
[this repository's discussions](https://github.com/heavy-duty/ceremony/discussions);
triage converges it to one of its five outcomes like anything else.

**A good ask carries four things**, and each is here because it was missing
somewhere real:

1. **The rule, quoted from the vendored file at your pin, naming the pin** —
   because doctrine moves, and an ask argued against a remembered rule spends
   its first round establishing which text is under discussion.
2. **The case the rule cannot express**, concretely, naming the issue or pull
   request in your own repo where it is visible — because that is the
   evidence, and it is what makes the ask triageable rather than an opinion.
3. **The local workaround now in force** — because there always is one, you
   had to ship something, and triage needs to know what is holding while the
   fix is written.
4. **What retires the workaround**, the condition in your own words — because
   that is what turns a workaround into a debt somebody can pay, rather than
   a paragraph indistinguishable from a decision.

**Bring three of the four and you are still triaged**, and triage asks for the
fourth. These are the shape of a good ask, written here where someone
preparing one will read them, and deliberately not gates at the door: the
ideas form these asks arrive through is light on purpose, because discussions
are where ambiguity is allowed and a form demanding rigor at the door defeats
the room (#24 D4).

**Your half is one link, and it is what makes the debt visible**: the local
workaround **names the upstream discussion or issue, in the body where the
workaround lives**. A workaround citing nothing reads exactly like a
decision, so a correct and complete finding can sit on a board for days while
the work around it copies the workaround forward. That link is the only
obligation this route places on you.

**The return path is the ordinary pin bump, and neither side polls.** The
upstream issue names in prose the consumers waiting on it, as any issue names
anything; your workaround names that issue; and the fix arrives the way every
other doctrine change arrives — at your next pin bump and re-sync
([the pin-bump procedure](#the-pin-bump-procedure)), the same carrier that
gives the manifest its zero-list-edits property. Retire the workaround and
drop its citation in that same PR, where the rule that replaced it is already
in the diff.

## Version pinning

- **Pin an exact ceremony release tag** — `@0.1.0`, never a branch and
  never a moving major pointer: the family pins things and reviews
  updates ([#1 D2](https://github.com/heavy-duty/ceremony/issues/1)).
  Every `uses:` of this repo in the consumer — the two workflow callers
  and the guard steps — names the same tag.
- **Bump by PR, every reference together.** Before bumping, read the
  ceremony's own `CHANGELOG.md` section for the new version (the release
  body on its
  [releases page](https://github.com/heavy-duty/ceremony/releases) is
  that section, verbatim). One bump PR updates **every** ceremony `uses:`
  reference in the repo to the new tag — the workflow callers *and* each
  guard step. The exact count is tag-dependent: it is the workflow caller
  or callers plus the guards that the pinned tag carries. Changing only
  one line leaves the consumer split across ceremony versions, which the
  same-tag rule above forbids. A repo that has adopted the agent team flow
  additionally bumps the mirror in the same PR —
  [the pin-bump procedure](#the-pin-bump-procedure).
- **One pin governs machinery and doctrine.** The ref in the consumer's
  `release.yml` `uses:` line is the single pin: `docs-sync` reads it from
  exactly there and verifies the `.ceremony/` mirror against it — there
  is no second pin to fall out of sync (#19).

## The changelog rule

The portable version of the family's contributor rule — the repo's own
CONTRIBUTING may sharpen it, but this is the floor the guards assume:

- **Every PR that changes behavior writes one fragment**:
  `changelog.d/<issue>.md`, named for the authorizing issue —
  `<repo>-<issue>.md` for cross-repo work carrying `Part of <repo>#N` —
  so the name is known at claim time and two builders can only collide by
  working the same issue (#112 D2). Never an edit to `CHANGELOG.md`: the
  release PR assembles the section
  ([below](#assembling-a-release-section)).

  The sole exception is the release PR: it writes no fragment. It consumes
  the directory and stamps the section, so a fragment it created would be
  absent from
  [`changelog-assembled`](https://github.com/heavy-duty/ceremony/blob/a602fd0/actions/changelog-assembled/changelog-assembled.sh)'s
  merge-base replay if consumed, or refused by
  [`changelog-armed`](https://github.com/heavy-duty/ceremony/blob/a602fd0/actions/changelog-armed/changelog-armed.sh)
  if left to survive into the next release. A change that must ship inside
  the release PR therefore ships without an entry. If it can wait and wants
  an entry, land it as an ordinary PR before the release PR, then rebase and
  re-assemble the release.
- **The fragment is the prose, not a description of it** (#112 D3): the
  exact lines that will be published — no front-matter, no `## ` heading
  (that one is the assembler's to write). `changelog-armed` refuses a
  malformed fragment on the PR that wrote it.
- **Grouped repos group inside the fragment**: `### Added`, `### Changed`,
  `### Fixed` headings with bullets under them; create `Deprecated`,
  `Removed`, or `Security` only when a change genuinely needs that rarer
  kind. A repo is grouped or flat, never both (#112 D4). The assembler
  merges groups in canonical order — Added, Changed, Fixed, Removed,
  Deprecated, Security, then anything else first-seen — and inside a
  group entries read newest issue first (#112 D5). Which shape binds is
  inferred from the newest published section, unless an optional sentinel
  `changelog.d/shape` — one line, exactly `flat` or `grouped` — declares
  it and outranks the inference (#182). To flip a repo's shape, land one
  PR that adds the sentinel and converts every pending fragment to the
  declared shape, bullets byte-identical; the sentinel stays after the
  release, as the declaration a reader in the directory finds.
- **One line: say what changed, and stop.** Lead with the surface, not
  the mechanism — "`state:needs-human` is set at handoff" beats "the
  labels workflow now also wakes on `labeled`". The why and the how
  belong in the PR body, where anyone chasing the reasoning already goes.
- **An entry is at most 300 characters**, and `changelog-armed` refuses a
  longer one on the PR that wrote it. The count is taken on the *whole*
  entry — the `- ` bullet and every line continuing it, joined into one
  string with runs of whitespace collapsed to single spaces and the ends
  trimmed — so it is not a per-line bound, and wrapping a long entry over
  three lines does not shorten it. Over the bound, split it into several
  `- ` entries in the same fragment (#571).
- **Cite the issue or PR, and let the citation close the entry**: exactly
  one `(#N)` group ends it, with the final `.` after that group. One group
  may carry several references separated by a comma and a space, and a
  reference may name another repository, so `(#N).`, `(#N, #M).` and
  `(owner/repo#N, #M).` are all admitted — an entry needing two references
  writes `(#141, #163).`, and one citing a sibling repository writes
  `(heavy-duty/ceremony#567, #61).` or the bare `(ceremony#567, #61).`.
  What `changelog-armed` refuses is a **second parenthesised citation group
  anywhere in the entry**, because with two groups no single group closes
  the entry and so none is terminal: `(#141) (#163).` fails where
  `(#141, #163).` passes, and so does anything trailing after the closing
  `.` (#571).
- **Mark a breaking change** with a leading `BREAKING:`.
- A repo not yet on fragment mode — no `changelog.d/` — keeps the legacy
  floor until its conversion: one line under `## Unreleased`, inserted
  **above** the heading below it, never over it (replacing a shipped
  heading deletes that release's section silently — box#122, why the
  [monotonic guard](../README.md#changelog-monotonic--shipped-headings-are-append-only)
  exists), appended under a standing `### ` heading where the repo groups.

## Assembling a release section

The ceremony PR's changelog stamp is one command, run **by hand, never in
CI** — the assembled section must land in the release PR's diff, where
the panel reads it (#112 D12). A consumer runs the tool from a ceremony
checkout at its own pin:

```sh
git clone --depth 1 --branch <pinned-tag> https://github.com/heavy-duty/ceremony /tmp/ceremony
/tmp/ceremony/bin/changelog-assemble <X.Y.Z>
```

Run it at the repo root. It folds every `changelog.d/` fragment into a
new `## X.Y.Z — DATE` section on top of `CHANGELOG.md` (DATE is today's
UTC date; pass one as a second argument to choose it) and deletes the
fragments it consumed — commit both halves together. `--check` prints the
would-be section body without touching anything; read it before running
the real thing. In CI, `changelog-assembled` replays the run from the
merge base and refuses a stamp that is not byte-for-byte what the
fragments assemble to — a mis-run hand step fails the PR, not the
published release.

## Adopting the agent team flow

The team flow (discussion → triage → issue → build → review → human
merge) is **optional per repo and separable from the release ceremony**:
a repo can adopt release-only and take the team flow later — incubator's
initial posture (#16). The model is this repo's own
[CONTRIBUTING](../CONTRIBUTING.md) ("How the other repos use this");
this is the checklist:

- [ ] **Enable Discussions** — the triage door exists or the pipeline
      has no intake.
- [ ] **Vendor the doctrine**: run `docs-sync --fix` (#19) to materialize
      `.ceremony/{AGENTS,TRIAGE,BUILDER,REVIEWER,LABELS}.md` —
      byte-identical to this repo at the pinned ref — plus the generated
      `.ceremony/README.md` (machine-managed marker) and, if the repo has
      none, the thin root `AGENTS.md` stub ("governed by
      heavy-duty/ceremony; read `.ceremony/AGENTS.md` first; repo
      specifics in CONTRIBUTING"). The stub is scaffolded once and never
      overwritten; the mirror is machine-written and never hand-edited.
      Commit `.ceremony/` together with the workflow callers.
- [ ] **Guard the mirror in CI**: add the `docs-sync` check step
      alongside the other guards —

      ```yaml
          - uses: heavy-duty/ceremony/actions/docs-sync@<pinned-tag>
      ```

      (`mode: check` is the default.) Hand-editing a vendored file, or
      bumping the pin without re-syncing, goes red (#19).
- [ ] **Reduce tool-specific files** (`CLAUDE.md`, …) to one pointer line
      at the root `AGENTS.md`, so every harness converges on the same
      router.
- [ ] **Point CONTRIBUTING at the mirror**: a short header telling agents
      to read `.ceremony/` first — agents never leave the working tree to
      read the rules — followed by only what is genuinely per-repo: the
      review panel roster, the `scope:*` set, the drill meaning, the
      repo's code conventions.
- [ ] **Name the review panel**: the roster table in CONTRIBUTING and the
      `panel=` line in `.github/labels.conf` — the required verdicts for
      any PR are the panel minus its author (#10).
- [ ] **Bootstrap the issue-flow labels**: the labels
      `workflow_dispatch` once ([above](#labels-automation)), or the hand
      commands in [LABELS.md](../LABELS.md).
- [ ] **State the single-writer rule** in the repo's own docs: only
      triage mints issues; everyone else opens discussions.

### The pin-bump procedure

Bumping the ceremony pin is **one PR carrying both halves**: every
ceremony `uses:` reference — the workflow callers *and* each guard step,
[all to the same new tag](#version-pinning) — and the re-synced
`.ceremony/` mirror —
run `docs-sync --fix` locally, or let the red `--check` on the bump PR
tell you what is stale. The CI guard is what makes a half-done bump —
pin without mirror, or mirror without pin — unmergeable (#19). This is
how a process change rolls out to a governed repo: deliberately, per
repo, reviewed. Both halves can be done for you —
[`ceremony-upgrade`](#ceremony-upgrade--the-bump-run-for-you), below —
which is also what refuses a bump that crosses a migration.

A bump that adds a core label is not finished at the merge: the bootstrap
re-dispatch that carries the new row into the repository is a separate
act, and its press can be evicted from the shared queue without saying so.
Run it in the verified form —
[A bootstrap press that reports whether it ran](#a-bootstrap-press-that-reports-whether-it-ran)
— which is where that block lives and the only place in this file it is
written out.

### `ceremony-upgrade` — the bump, run for you

`bin/ceremony-upgrade` performs the procedure above against a working
tree: it moves every ceremony `uses:` reference to one tag, re-syncs the
mirror by calling `docs-sync --fix`, and **refuses** where the move
crosses a migration. Run it from the root of your checkout, from a
ceremony checkout of any recent tag (#561):

```sh
# what would happen — changes not one byte
path/to/ceremony/bin/ceremony-upgrade 0.7.7

# do it
path/to/ceremony/bin/ceremony-upgrade --fix 0.7.7
```

`--check` is the default, as it is in `docs-sync`, and `--source <dir>`
substitutes a local ceremony checkout for the network so a move can be
previewed against an unreleased tree. The command opens no PR and pushes
nothing: it edits the tree and stops, and committing the refs and the
mirror **together** is still yours to do, for the reason above — a
half-done bump is what the CI guard refuses.

**It is not `sed 's/0.7.4/0.7.7/g'`, and that is the whole point.** A
bare version string is not a pin: a README that mentions the old version,
or your own `CHANGELOG.md` heading for your own `0.7.6` release, is
silently corrupted by a tree-wide substitution. The pin shape is the one
`docs-sync` reads the pin by, so the two can never disagree about what
this repo is pinned to — and `--fix` rewrites exactly the lines `--check`
listed, by line number, looking at no other line in the file. It then
re-reads the tree and checks that against what it told you: the counts it
announced, every ref at the target, and every file it rewrote unchanged
outside those lines, down to whether it ended with a newline. A run that
did something other than its own plan undoes itself and says so.

**And several pin moves are migrations rather than substitutions.** The
*"available at `X` and later"* notes throughout this guide say what a tag
changed about the tree a consumer must carry, and crossing one without
its hand edit does not leave you half-upgraded — it leaves a tree that
fails loudly. Crossing `0.4.1` without
[the two-caller split](#labels-automation) leaves the trigger job red on
every pull request and issue event. So the command refuses rather than
guesses. **A refusal leaves the tree byte-identical** — there is nothing
to undo and nothing to inspect.

That holds however deep the refusal comes from, and it takes two things
to hold. Every check this command makes runs before any write. But it
does not write alone — it calls `docs-sync`, which has refusals of its
own that come *after* it has started writing, such as a
`pull_request_template.md` whose ceremony markers are unbalanced. So
`--fix` also takes a snapshot of everything the pair can touch
(`.github/`, `.ceremony/`, and your root's own files) before the first
byte is written, and restores it if anything goes wrong at any depth —
including a `docs-sync` refusal, and including a `Ctrl-C` mid-run. You
never end up pinned forward with a half-written mirror.

The refusals, and what each one means:

| refusal | what it means | what to do |
| --- | --- | --- |
| **no ceremony pin** | no `uses: heavy-duty/ceremony/…@<ref>` line under `.github/`, so there is no pin to move *from* | this is bootstrap, not an upgrade, and it is not something this command does: follow [Bootstrap a new repo](#bootstrap-a-new-repo) by hand |
| **the refs are not all at one ref** | two ceremony refs in one tree, so it has no single pin — usually a bump that moved some lines and not others | put them on one ref by hand, then re-run; the message names the files that differ |
| **the current pin is not a released tag** | a branch or a commit SHA cannot be placed on the release ladder, so which migrations the move crosses is unknowable | pin to a released tag first |
| **the target tag does not exist** | the tag was never cut — check it against the [releases page](https://github.com/heavy-duty/ceremony/releases), or pass `--source` to preview an unreleased tree | — |
| **the move crosses a migration** | the interval between your pin and the target contains a tag whose note in this guide asks something of your tree | it depends on the first crossed tag. Where that tag carries an **applied step** — [`0.4.1`](#labels-automation)'s two-caller split, [`0.5.0`](#labels-automation)'s panel rows, [`0.6.0`](#doctrine-mirror)'s doctrine-mirror crossing, [`0.7.0`](#the-artifact-hook)'s rc release path, and [`0.7.8`](#the-guarded-scaffold--ceremony-owns-a-block-you-own-the-rest)'s guarded scaffold, the tags mechanised so far — the command performs that tag for you, the refs and whatever edits that tag needs in one pass, then stops there and names the pin it left you at and what still stands between that pin and the tag you asked for; run it again from the new pin for the next rung. Where the first crossed tag has no applied step, and where a step cannot anchor one of its edits in your tree, the crossing is hand-only: perform the first crossed tag's edits and move the ceremony refs to that tag in the same commit, because tree edits alone do not change the pinned interval. When a released tag exists between the current pin and that first crossing, the message emits that shorter runnable move; otherwise it says no shorter move exists |
| **the move is backwards** | a downgrade; this guide's notes are written forwards and none of them says how to undo a tag | undo the crossed migrations deliberately and move the refs by hand |

Every refusal names the tags it is refusing over and the section of this
guide that covers each, and says what it *would* have done — the ref
count and the files — so a refusal about migrations is never mistaken for
a refusal about the refs.
