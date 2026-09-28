#!/usr/bin/env bash
# Run actionlint while it catches up with GitHub's `uses: $/...` syntax.
#
# GitHub added the self-repository form in July 2026.  It prevents a prior
# step from replacing a workspace-relative action on disk, and zizmor 1.30
# correctly requires it.  The latest released actionlint (1.7.12) still
# rejects that syntax (https://github.com/rhysd/actionlint/issues/711).
# Feed actionlint faithful temporary copies with only that token mapped back to
# its legacy spelling.  Every other byte, including malformed `$...` forms,
# remains available to actionlint.  Remove this adapter once #711 ships.
set -euo pipefail

[ "$#" -gt 0 ] || {
    echo "actionlint-compat: no workflow files" >&2
    exit 2
}

root="$(git rev-parse --show-toplevel)"
cd "$root"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp:?}"' EXIT

mapped=()
for source in "$@"; do
    case "$source" in
        .github/workflows/*.yml | .github/workflows/*.yaml) ;;
        *)
            echo "actionlint-compat: refusing non-workflow path: $source" >&2
            exit 2
            ;;
    esac
    target="$tmp/$source"
    mkdir -p "$(dirname "$target")"
    # Only a uses value beginning with the exact self-repository token moves.
    # A broad s,$,., would launder expressions and malformed references.
    sed -E 's#^([[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*)[$]/#\1./#' "$source" >"$target"
    mapped+=("$target")
done

SHELLCHECK_OPTS=-Swarning \
    actionlint -config-file .github/actionlint.yaml \
    -ignore 'label ".+" is unknown' "${mapped[@]}"
