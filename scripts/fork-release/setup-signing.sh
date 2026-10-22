#!/usr/bin/env bash

# Prepares the release credentials on the release Mac. Run it yourself in a
# terminal: it asks for the passwords it needs and never prints secrets.
#
# In the runner directory it creates or reuses:
#   easydict-release.keychain-db  Developer ID identity, and the notarytool
#                                 profile unless the source keychain's is reused
#   .keychain-password            random password of that keychain (mode 600)
#   .sparkle-ed25519-key          Sparkle private key (mode 600), plus .pub
# and records their locations in the runner's private .env.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_DIR="${EASYDICT_RUNNER_DIR:-$HOME/actions-runners/easydict}"
KEYCHAIN="$RUNNER_DIR/easydict-release.keychain-db"
PASSWORD_FILE="$RUNNER_DIR/.keychain-password"
SPARKLE_KEY_FILE="$RUNNER_DIR/.sparkle-ed25519-key"
NOTARY_PROFILE="easydict-notary"
P12_FILE=""
SOURCE_KEYCHAIN=""
SOURCE_PASSWORD_FILE=""
NOTARY_KEYCHAIN=""
NOTARY_PASSWORD_FILE=""
TEMP_DIR=""

log() {
    printf '==> %s\n' "$*"
}

fail() {
    printf 'setup-signing: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<'EOF'
usage: setup-signing.sh (--p12 <file> | --from-keychain <keychain>) [options]

  --p12 <file>                   import the Developer ID identity from a .p12 file
  --from-keychain <path>         copy the Developer ID identity from another keychain,
                                 and reuse its notarytool profile when it has one
  --source-password-file <file>  unlock that keychain with this file instead of a prompt
  --profile <name>               notarytool profile name (default: easydict-notary)
EOF
    exit 2
}

cleanup() {
    if [[ -n "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    if [[ -f "$KEYCHAIN" ]]; then
        security lock-keychain "$KEYCHAIN" 2>/dev/null || true
    fi
}

developer_id_count() {
    security find-identity -v -p codesigning "$KEYCHAIN" \
        | grep -cF '"Developer ID Application:' || true
}

# Creates the keychain with a random password without adding it to the
# keychain search list, matching the other release keychains on this Mac.
create_keychain() {
    local search_list

    if [[ -f "$KEYCHAIN" ]]; then
        [[ -f "$PASSWORD_FILE" ]] || fail "the keychain exists but its password file is missing"
        log "reusing $(basename "$KEYCHAIN")"
        return
    fi

    log "creating $(basename "$KEYCHAIN")"
    (umask 077 && openssl rand -base64 32 | tr -d '\n' >"$PASSWORD_FILE")
    search_list="$(security list-keychains -d user)"
    security create-keychain -p "$(<"$PASSWORD_FILE")" "$KEYCHAIN"
    if [[ "$(security list-keychains -d user)" != "$search_list" ]]; then
        printf '%s\n' "$search_list" | xargs security list-keychains -d user -s
    fi
    security set-keychain-settings -l -u -t 7200 "$KEYCHAIN"
}

import_identity() {
    local transfer_password

    if [[ "$(developer_id_count)" -ge 1 ]]; then
        log "the keychain already holds a Developer ID Application identity"
        return
    fi

    if [[ -n "$SOURCE_KEYCHAIN" ]]; then
        log "copying the identity from $(basename "$SOURCE_KEYCHAIN")"
        TEMP_DIR="$(mktemp -d)"
        P12_FILE="$TEMP_DIR/identity.p12"
        transfer_password="$(openssl rand -base64 24)"
        security export -k "$SOURCE_KEYCHAIN" -t identities -f pkcs12 \
            -P "$transfer_password" -o "$P12_FILE"
        security import "$P12_FILE" -k "$KEYCHAIN" -f pkcs12 \
            -P "$transfer_password" -T /usr/bin/codesign
        unset transfer_password
    else
        [[ -f "$P12_FILE" ]] || fail ".p12 file not found"
        log "importing $(basename "$P12_FILE"); enter the .p12 password when asked"
        security import "$P12_FILE" -k "$KEYCHAIN" -f pkcs12 -T /usr/bin/codesign
    fi

    # Lets codesign use the key without a keychain prompt on the runner.
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "$(<"$PASSWORD_FILE")" "$KEYCHAIN" >/dev/null
}

notary_profile_works() {
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" \
        --keychain "$1" >/dev/null 2>&1
}

# Uses the notarytool profile in the release keychain, or reuses the one
# already saved in the source keychain (the other release apps share one
# profile); only when neither exists does it ask for new credentials.
store_notary_profile() {
    NOTARY_KEYCHAIN="$KEYCHAIN"
    NOTARY_PASSWORD_FILE="$PASSWORD_FILE"
    if notary_profile_works "$KEYCHAIN"; then
        log "notarytool profile $NOTARY_PROFILE is already valid"
        return
    fi
    if [[ -n "$SOURCE_KEYCHAIN" && -n "$SOURCE_PASSWORD_FILE" ]] \
        && notary_profile_works "$SOURCE_KEYCHAIN"; then
        NOTARY_KEYCHAIN="$SOURCE_KEYCHAIN"
        NOTARY_PASSWORD_FILE="$SOURCE_PASSWORD_FILE"
        log "reusing notarytool profile $NOTARY_PROFILE from $(basename "$SOURCE_KEYCHAIN")"
        return
    fi
    log "storing notarytool profile $NOTARY_PROFILE; answer notarytool's prompts"
    xcrun notarytool store-credentials "$NOTARY_PROFILE" --keychain "$KEYCHAIN"
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" \
        --keychain "$KEYCHAIN" >/dev/null \
        || fail "the stored notarytool profile does not work"
}

# Sets one KEY=VALUE line in the runner's private .env.
set_runner_env() {
    local key="$1" value="$2" env_file="$RUNNER_DIR/.env"

    touch "$env_file"
    chmod 600 "$env_file"
    { grep -v "^$key=" "$env_file" || true; printf '%s=%s\n' "$key" "$value"; } \
        >"$env_file.tmp"
    mv "$env_file.tmp" "$env_file"
}

main() {
    while (($# > 0)); do
        case "$1" in
            --p12) P12_FILE="${2:-}"; shift 2 ;;
            --from-keychain) SOURCE_KEYCHAIN="${2:-}"; shift 2 ;;
            --source-password-file) SOURCE_PASSWORD_FILE="${2:-}"; shift 2 ;;
            --profile) NOTARY_PROFILE="${2:-}"; shift 2 ;;
            *) usage ;;
        esac
    done
    [[ -n "$P12_FILE" || -n "$SOURCE_KEYCHAIN" ]] || usage
    [[ -z "$P12_FILE" || -z "$SOURCE_KEYCHAIN" ]] || usage
    [[ -n "$NOTARY_PROFILE" ]] || usage

    install -d -m 700 "$RUNNER_DIR"
    trap cleanup EXIT

    create_keychain
    security unlock-keychain -p "$(<"$PASSWORD_FILE")" "$KEYCHAIN"
    if [[ -n "$SOURCE_KEYCHAIN" ]]; then
        [[ -f "$SOURCE_KEYCHAIN" ]] || fail "source keychain not found"
        log "unlocking $(basename "$SOURCE_KEYCHAIN")"
        if [[ -n "$SOURCE_PASSWORD_FILE" ]]; then
            security unlock-keychain -p "$(<"$SOURCE_PASSWORD_FILE")" "$SOURCE_KEYCHAIN"
        else
            security unlock-keychain "$SOURCE_KEYCHAIN"
        fi
    fi
    import_identity
    [[ "$(developer_id_count)" -eq 1 ]] \
        || fail "the keychain must hold exactly one Developer ID Application identity"
    log "Developer ID identity is ready"

    store_notary_profile

    EASYDICT_SPARKLE_KEY_FILE="$SPARKLE_KEY_FILE" \
        "$SCRIPT_DIR/fork-release.sh" setup-sparkle-key

    set_runner_env EASYDICT_SIGNING_KEYCHAIN "$KEYCHAIN"
    set_runner_env EASYDICT_KEYCHAIN_PASSWORD_FILE "$PASSWORD_FILE"
    set_runner_env EASYDICT_NOTARY_PROFILE "$NOTARY_PROFILE"
    set_runner_env EASYDICT_NOTARY_KEYCHAIN "$NOTARY_KEYCHAIN"
    set_runner_env EASYDICT_NOTARY_KEYCHAIN_PASSWORD_FILE "$NOTARY_PASSWORD_FILE"
    set_runner_env EASYDICT_SPARKLE_KEY_FILE "$SPARKLE_KEY_FILE"

    log "done; the public Sparkle key is in $(basename "$SPARKLE_KEY_FILE").pub"
    log "back up $(basename "$SPARKLE_KEY_FILE") somewhere safe: without it, installed builds cannot update"
}

main "$@"
