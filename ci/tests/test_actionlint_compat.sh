#!/usr/bin/env bash
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
HELPER="$ROOT/ci/linter/actionlint-compat.sh"
rc=0

case_() { # expected-exit fixture-line description
    local want="$1" line="$2" desc="$3" tmp got
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/repo/.github/workflows" "$tmp/repo/ci/linter" "$tmp/bin"
    git -C "$tmp/repo" init -q
    cp "$HELPER" "$tmp/repo/ci/linter/actionlint-compat.sh"
    printf 'name: fixture\non: {}\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - %s\n' "$line" \
        >"$tmp/repo/.github/workflows/test.yml"
    cat >"$tmp/bin/actionlint" <<'MOCK'
#!/usr/bin/env bash
set -u
for arg in "$@"; do
    [ -f "$arg" ] || continue
    grep -q 'uses: \$/' "$arg" && exit 90
    grep -q 'uses: \$bad' "$arg" && exit 1
done
exit 0
MOCK
    chmod +x "$tmp/bin/actionlint"
    (
        cd "$tmp/repo" || exit 2
        PATH="$tmp/bin:$PATH" bash ci/linter/actionlint-compat.sh .github/workflows/test.yml
    ) >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "ok   $desc"
    else
        echo "FAIL $desc: expected exit $want, got $got" >&2
        rc=1
    fi
    rm -rf "${tmp:?}"
}

case_ 0 'uses: $/.github/actions/local' "self-repository token is mapped for actionlint"
case_ 0 'uses: owner/action@1111111111111111111111111111111111111111' "remote action reference is unchanged"
case_ 1 "uses: \$bad" "malformed dollar reference is not laundered"

exit "$rc"
