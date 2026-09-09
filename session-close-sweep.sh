#!/usr/bin/env bash
# ~/.claude/hooks/session-close-sweep.sh
#
# SessionEnd: verify every closed issue's Artifacts: claims against the repo.
# Emits a systemMessage only when something is missing. ~1.5s for 114 issues.
# Always exits 0 -- a session must never fail to end because of a check.
set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
command -v bd >/dev/null 2>&1 || exit 0

verifier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bd-verify-artifacts.sh"
[ -x "$verifier" ] || exit 0

out="$("$verifier" --ref HEAD 2>&1)" && exit 0   # exit 0 from verifier = nothing missing

jq -nc --arg out "$out" '{
  systemMessage: ("⚠ SESSION-CLOSE INTEGRITY CHECK FAILED — a closed issue claims code that is not in the repository:\n\n" + $out + "\nReopen the affected issues and re-verify before trusting any of this session'"'"'s close reasons. `git fsck --unreachable | grep commit` may recover lost work.")
}'
exit 0
