#!/usr/bin/env bash
# Scans every active repository in the org for pull requests that are inactive/stale.
#
# A pull request with no activity for DAYS_BEFORE_STALE days gets a comment and the "stale"
# label. If it then sits another DAYS_BEFORE_CLOSE days without any updates, it is closed (with a comment)
# Activity is anything that bumps the pull request's "updated_at" metadata: a push, a comment,
# a review, a label change.

set -euo pipefail

: "${GH_TOKEN:?}"
: "${OWNER:?}"
DRY_RUN="${DRY_RUN:-false}"
DAYS_BEFORE_STALE="${DAYS_BEFORE_STALE:-30}"
DAYS_BEFORE_CLOSE="${DAYS_BEFORE_CLOSE:-14}"
STALE_LABEL="${STALE_LABEL:-stale}"

stale_message="This pull request has had no activity for $DAYS_BEFORE_STALE days, so it has \
been marked \`$STALE_LABEL\`. It will be closed in $DAYS_BEFORE_CLOSE days unless it becomes \
active. To keep it open, push a commit, leave a comment, or remove the \`$STALE_LABEL\` \
label. If it is blocked, a short note on what it is waiting for is enough."
close_message="Closing this pull request because it stayed \`$STALE_LABEL\` for \
$DAYS_BEFORE_CLOSE days with no further activity. Reopen it if the work is still needed."

if [ "$DRY_RUN" = "true" ]; then
  would="would "
else
  would=""
fi

repos=0; seen=0; marked=0; closed=0; unmarked=0; failed=0

write() {
  if [ "$DRY_RUN" = "true" ]; then
    return 0
  fi
  gh api "$@" 2>&1 >/dev/null | tr '\n\r' '  '
}

ensure_label() {
  local repo=$1
  if gh api "repos/$OWNER/$repo/labels/$STALE_LABEL" >/dev/null 2>&1; then
    return 0
  fi
  write -X POST "repos/$OWNER/$repo/labels" -f name="$STALE_LABEL" -f color=ededed \
    -f description="No activity for $DAYS_BEFORE_STALE days. Closes after $DAYS_BEFORE_CLOSE more unless something changes."
}

# Comment first, label last. The label event is what later runs measure activity against,
# so it has to be the newest thing on the pull request when this returns.
mark_stale() {
  local repo=$1 number=$2
  ensure_label "$repo" \
    && write -X POST "repos/$OWNER/$repo/issues/$number/comments" -f body="$stale_message" \
    && write -X POST "repos/$OWNER/$repo/issues/$number/labels" -f "labels[]=$STALE_LABEL"
}

close_pr() {
  local repo=$1 number=$2
  write -X POST "repos/$OWNER/$repo/issues/$number/comments" -f body="$close_message" \
    && write -X PATCH "repos/$OWNER/$repo/pulls/$number" -f state=closed
}

unmark_stale() {
  local repo=$1 number=$2
  write -X DELETE "repos/$OWNER/$repo/issues/$number/labels/$STALE_LABEL"
}

# When a pull request was last marked as stale
marked_at() {
  local repo=$1 number=$2
  gh api "repos/$OWNER/$repo/issues/$number/events?per_page=100" --paginate 2>/dev/null \
    | jq -rs --arg l "$STALE_LABEL" \
        '[.[][] | select(.event == "labeled" and .label.name == $l)] | last | .created_at // empty'
}

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# Skip archived repositories
gh api "orgs/$OWNER/repos" --paginate \
  --jq '.[] | select(.archived == false) | .name' | sort > "$workdir/repos.txt"
echo "Sweeping $(wc -l < "$workdir/repos.txt" | tr -d ' ') active repositories."

# avoid leaking private repo names (probably doesn't matter but ¯\_(ツ)_/¯)
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  while read -r repo; do
    echo "::add-mask::$repo"
  done < "$workdir/repos.txt"
fi

while read -r -u 3 repo; do
  repos=$((repos+1))
  prs=$(gh api "repos/$OWNER/$repo/pulls?state=open&per_page=100" --paginate 2>/dev/null \
          | jq -c --arg l "$STALE_LABEL" \
              '.[] | {number, updated_at, stale: any(.labels[]; .name == $l)}') || {
    echo "::warning::could not list pull requests in $repo"; failed=$((failed+1)); continue; }

  while read -r -u 4 pr; do
    [ -n "$pr" ] || continue
    seen=$((seen+1))
    number=$(jq -r .number <<<"$pr")
    updated=$(jq -r .updated_at <<<"$pr")
    is_stale=$(jq -r .stale <<<"$pr")

    if [ "$is_stale" != "true" ]; then
      idle_days=$(jq -rn --arg u "$updated" '((now - ($u | fromdateiso8601)) / 86400) | floor')
      if [ "$idle_days" -lt "$DAYS_BEFORE_STALE" ]; then
        continue
      fi
      if err=$(mark_stale "$repo" "$number"); then
        echo "${would}mark: $repo#$number (idle ${idle_days}d)"; marked=$((marked+1))
      else
        echo "::warning::could not mark $repo#$number stale: $err"; failed=$((failed+1))
      fi
      continue
    fi

    since=$(marked_at "$repo" "$number") || {
      echo "::warning::could not read the events of $repo#$number"; failed=$((failed+1)); continue; }
    if [ -z "$since" ]; then
      echo "::warning::$repo#$number carries the $STALE_LABEL label but has no labeled event, leaving it alone"
      continue
    fi

    # The mark is two calls a moment apart and updated_at is only second-precise, so a
    # minute of slack keeps the marking run itself from reading as activity.
    verdict=$(jq -rn --arg u "$updated" --arg m "$since" --argjson d "$DAYS_BEFORE_CLOSE" '
      ($u | fromdateiso8601) as $u | ($m | fromdateiso8601) as $m
      | if $u > $m + 60 then "unmark"
        elif now - $m >= $d * 86400 then "close"
        else "wait" end')
    stale_days=$(jq -rn --arg m "$since" '((now - ($m | fromdateiso8601)) / 86400) | floor')

    case "$verdict" in
      unmark)
        if err=$(unmark_stale "$repo" "$number"); then
          echo "${would}unmark: $repo#$number (activity after the mark)"; unmarked=$((unmarked+1))
        else
          echo "::warning::could not remove the $STALE_LABEL label from $repo#$number: $err"; failed=$((failed+1))
        fi
        ;;
      close)
        if err=$(close_pr "$repo" "$number"); then
          echo "${would}close: $repo#$number (stale ${stale_days}d)"; closed=$((closed+1))
        else
          echo "::warning::could not close $repo#$number: $err"; failed=$((failed+1))
        fi
        ;;
    esac
  done 4<<<"$prs"
done 3< "$workdir/repos.txt"

tally="Repositories: $repos. Open pull requests: $seen. Marked stale: $marked. Closed: $closed. Unmarked: $unmarked. Failed: $failed."
if [ "$DRY_RUN" = "true" ]; then
  tally="Dry run, nothing changed. $tally"
fi
echo "$tally"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$tally" >> "$GITHUB_STEP_SUMMARY"
fi
# Everything above only warns. Without this a nightly run goes green even when every write
# failed, say because the app lost Pull requests: write.
if [ "$failed" -gt 0 ]; then
  exit 1
fi
