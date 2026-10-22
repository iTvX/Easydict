#!/usr/bin/env bash

# Installs, inspects, or removes the self-hosted GitHub Actions runner that
# publishes fork releases. Like the other release runners on this Mac, it lives
# in ~/actions-runners/<name> and runs as a per-user LaunchAgent while this
# user is logged in. Run setup-signing.sh first so the runner's private .env
# already names the release credentials when the service starts.

set -euo pipefail

REPO="${EASYDICT_REPO:-iTvX/Easydict}"
RUNNER_DIR="${EASYDICT_RUNNER_DIR:-$HOME/actions-runners/easydict}"
RUNNER_NAME="${EASYDICT_RUNNER_NAME:-easydict-$(scutil --get LocalHostName | tr '[:upper:]' '[:lower:]')}"
RUNNER_LABELS="easydict-release"

log() {
    printf '==> %s\n' "$*"
}

fail() {
    printf 'setup-runner: %s\n' "$*" >&2
    exit 1
}

runner_platform() {
    case "$(uname -m)" in
        arm64) printf 'osx-arm64\n' ;;
        x86_64) printf 'osx-x64\n' ;;
        *) fail "unsupported architecture: $(uname -m)" ;;
    esac
}

# Downloads the latest runner release and checks the SHA-256 that GitHub
# publishes in the release notes before unpacking it.
download_runner() {
    local platform tag version archive url expected actual body
    local download_dir

    platform="$(runner_platform)"
    tag="$(gh api repos/actions/runner/releases/latest --jq .tag_name)"
    version="${tag#v}"
    archive="actions-runner-$platform-$version.tar.gz"
    url="https://github.com/actions/runner/releases/download/$tag/$archive"
    body="$(gh api repos/actions/runner/releases/latest --jq .body)"
    expected="$(sed -nE \
        "s/.*<!-- BEGIN SHA $platform -->([0-9a-f]{64})<!-- END SHA $platform -->.*/\\1/p" \
        <<<"$body" | head -n 1)"
    [[ -n "$expected" ]] || fail "release $tag does not list a SHA-256 for $platform"

    download_dir="$(mktemp -d)"
    log "downloading $archive"
    curl -fsSL -o "$download_dir/$archive" "$url"
    actual="$(shasum -a 256 "$download_dir/$archive" | awk '{ print $1 }')"
    [[ "$actual" == "$expected" ]] || fail "SHA-256 mismatch for $archive"

    mkdir -p "$RUNNER_DIR"
    tar -xzf "$download_dir/$archive" -C "$RUNNER_DIR"
    rm -rf "$download_dir"
}

install_runner() {
    local token

    command -v gh >/dev/null || fail "GitHub CLI is required"
    if [[ -f "$RUNNER_DIR/.runner" ]]; then
        log "runner already configured in $RUNNER_DIR"
    else
        [[ -x "$RUNNER_DIR/config.sh" ]] || download_runner
        token="$(gh api -X POST \
            "repos/$REPO/actions/runners/registration-token" --jq .token)"
        (
            cd "$RUNNER_DIR"
            ./config.sh --unattended \
                --url "https://github.com/$REPO" \
                --token "$token" \
                --name "$RUNNER_NAME" \
                --labels "$RUNNER_LABELS" \
                --work _work \
                --replace
        )
    fi

    (
        cd "$RUNNER_DIR"
        if [[ ! -f .service ]]; then
            ./svc.sh install
        fi
        ./svc.sh stop >/dev/null 2>&1 || true
        ./svc.sh start
    )
    show_status
}

show_status() {
    if [[ -x "$RUNNER_DIR/svc.sh" ]]; then
        (cd "$RUNNER_DIR" && ./svc.sh status) || true
    fi
    gh api "repos/$REPO/actions/runners" \
        --jq '.runners[] | "\(.name): \(.status) [\([.labels[].name] | join(", "))]"'
}

uninstall_runner() {
    local token

    [[ -f "$RUNNER_DIR/.runner" ]] || fail "no configured runner in $RUNNER_DIR"
    token="$(gh api -X POST \
        "repos/$REPO/actions/runners/remove-token" --jq .token)"
    (
        cd "$RUNNER_DIR"
        ./svc.sh stop || true
        ./svc.sh uninstall || true
        ./config.sh remove --token "$token"
    )
}

case "${1:-}" in
    install) install_runner ;;
    status) show_status ;;
    uninstall) uninstall_runner ;;
    *) fail "usage: setup-runner.sh install|status|uninstall" ;;
esac
