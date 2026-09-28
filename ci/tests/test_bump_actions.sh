#!/usr/bin/env bash
# Regression tests for the selected-actions guard in bump-actions.sh.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="$ROOT/ci/tools/bump-actions.sh"
OLD=1111111111111111111111111111111111111111
NEW=2222222222222222222222222222222222222222
rc=0

run_case() { # policy-mode expected-exit expected-changed description
    local mode="$1" want_exit="$2" want_changed="$3" desc="$4"
    local tmp got changed
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/repo/.github/workflows" "$tmp/repo/ci/tools" "$tmp/bin"
    git -C "$tmp/repo" init -q
    cp "$SCRIPT" "$tmp/repo/ci/tools/bump-actions.sh"
    printf 'name: fixture\non: {}\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: vendor/tool@%s # v2.32.0\n' "$OLD" \
        >"$tmp/repo/.github/workflows/test.yml"
    cat >"$tmp/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -u
mode="${MOCK_POLICY_MODE:?}"
old="${MOCK_OLD:?}"
new="${MOCK_NEW:?}"
case "$1 $2" in
    "release list") printf '%s\n' v2.33.0 ;;
    "repo view") printf '%s\n' acme/project ;;
    "api repos/vendor/tool/git/ref/tags/v2.33.0")
        case "$*" in
            *object.type*) printf '%s\n' commit ;;
            *) printf '%s\n' "$new" ;;
        esac
        ;;
    "api repos/acme/project/actions/permissions" | \
    "api orgs/acme/actions/permissions")
        printf '%s\n' selected
        ;;
    "api repos/acme/project/actions/permissions/selected-actions" | \
    "api orgs/acme/actions/permissions/selected-actions")
        [ "$mode" = error ] && exit 1
        printf 'vendor/tool@%s\n' "$old"
        if [ "$mode" = admitted ]; then
            printf 'vendor/tool@%s\n' "$new"
        fi
        ;;
    *)
        printf 'unexpected gh call: %s\n' "$*" >&2
        exit 99
        ;;
esac
MOCK
    chmod +x "$tmp/bin/gh"

    (
        cd "$tmp/repo" || exit 2
        PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=acme/project \
            MOCK_POLICY_MODE="$mode" MOCK_OLD="$OLD" MOCK_NEW="$NEW" \
            bash ci/tools/bump-actions.sh
    ) >"$tmp/out" 2>&1
    got=$?
    if grep -q "vendor/tool@$NEW" "$tmp/repo/.github/workflows/test.yml"; then
        changed=1
    else
        changed=0
    fi

    if [ "$got" -eq "$want_exit" ] && [ "$changed" -eq "$want_changed" ]; then
        echo "ok   $desc"
    else
        echo "FAIL $desc: exit=$got changed=$changed, want exit=$want_exit changed=$want_changed" >&2
        sed 's/^/       | /' "$tmp/out" >&2
        rc=1
    fi
    rm -rf "${tmp:?}"
}

# Negative/control: the old exact SHA remains pinned when the candidate has
# not been admitted.  Positive: adding the candidate to the real predicate's
# shape permits the normal action bump.  Boundary/error: an unreadable policy
# is not treated as unrestricted.
run_case held 0 0 "exact selected-actions pin holds an unadmitted bump"
run_case admitted 0 1 "admitted candidate SHA is bumped"
run_case error 1 0 "unreadable selected-actions policy fails closed"

exit "$rc"
