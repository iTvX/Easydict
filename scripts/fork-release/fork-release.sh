#!/usr/bin/env bash

# Builds, signs, notarizes, and publishes an Easydict release for the fork.
#
# Runs on the fork's self-hosted runner from .github/workflows/fork-release.yml
# and can also run by hand from a clean checkout of dev. Credentials never
# enter the repository or GitHub: the runner's private .env names the local
# signing keychain, its password file, the notarytool profile, and the Sparkle
# private key file. See docs/releases/fork-release.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$SCRIPT_DIR/fork_release.py"

LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
REPO="${EASYDICT_REPO:-${GITHUB_REPOSITORY:-iTvX/Easydict}}"
TEAM_ID="${EASYDICT_TEAM_ID:-}"
NOTARY_PROFILE="${EASYDICT_NOTARY_PROFILE:-}"
SIGNING_KEYCHAIN="${EASYDICT_SIGNING_KEYCHAIN:-$LOGIN_KEYCHAIN}"
NOTARY_KEYCHAIN="${EASYDICT_NOTARY_KEYCHAIN:-$SIGNING_KEYCHAIN}"
KEYCHAIN_PASSWORD_FILE="${EASYDICT_KEYCHAIN_PASSWORD_FILE:-}"
NOTARY_KEYCHAIN_PASSWORD_FILE="${EASYDICT_NOTARY_KEYCHAIN_PASSWORD_FILE:-$KEYCHAIN_PASSWORD_FILE}"
SPARKLE_KEY_FILE="${EASYDICT_SPARKLE_KEY_FILE:-}"
SPARKLE_ACCOUNT="${EASYDICT_SPARKLE_ACCOUNT:-easydict-fork}"
CODESIGN_VIA_LAUNCHCTL="${CODESIGN_VIA_LAUNCHCTL:-0}"
NOTARY_VIA_LAUNCHCTL="${NOTARY_VIA_LAUNCHCTL:-0}"
CACHE_DIR="${EASYDICT_RELEASE_CACHE_DIR:-$HOME/Library/Caches/easydict-fork-release}"
DERIVED_DATA="$CACHE_DIR/DerivedData"
# Kept on this Mac until the next run so failed runs can be inspected locally.
OUT_DIR="$CACHE_DIR/run"

WORKSPACE="$REPO_ROOT/Easydict.xcworkspace"
PROJECT="$REPO_ROOT/Easydict.xcodeproj"
SCHEME="Easydict"
ENTITLEMENTS="$REPO_ROOT/Easydict/App/Easydict.entitlements"
INFO_PLIST="$REPO_ROOT/Easydict/App/Info.plist"
FEED_URL="https://github.com/$REPO/releases/latest/download/appcast.xml"

SIGN_IDENTITY_HASH=""
KEYCHAINS_UNLOCKED=0

# Package resolution uses system git, which only asks the keychain for GitHub
# credentials when a server requires them. Xcode's built-in git can raise a
# keychain prompt that an unattended runner cannot answer.
export GIT_TERMINAL_PROMPT=0

log() {
    printf '==> %s\n' "$*"
}

fail() {
    printf 'fork-release: %s\n' "$*" >&2
    exit 1
}

group() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        printf '::group::%s\n' "$*"
    else
        log "$*"
    fi
}

endgroup() {
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        printf '::endgroup::\n'
    fi
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

sparkle_tool() {
    local tool="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/$1"
    [[ -x "$tool" ]] || fail "missing Sparkle tool $1; resolve packages first"
    printf '%s\n' "$tool"
}

resolve_packages() {
    group "Resolving Swift packages"
    xcodebuild -resolvePackageDependencies \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -scmProvider system \
        -derivedDataPath "$DERIVED_DATA" >/dev/null
    endgroup
}

# Some runner sessions can only reach the keychain from the user's login
# session; CODESIGN_VIA_LAUNCHCTL and NOTARY_VIA_LAUNCHCTL route the tools there.
run_codesign() {
    if [[ "$CODESIGN_VIA_LAUNCHCTL" == 1 ]]; then
        launchctl asuser "$(id -u)" codesign "$@"
    else
        codesign "$@"
    fi
}

run_notarytool() {
    if [[ "$NOTARY_VIA_LAUNCHCTL" == 1 ]]; then
        launchctl asuser "$(id -u)" xcrun notarytool "$@"
    else
        xcrun notarytool "$@"
    fi
}

# MARK: - Keychain and credentials

check_private_file() {
    local path="$1" label="$2"

    [[ -f "$path" && ! -L "$path" ]] || fail "$label is missing or a symlink"
    [[ "$(stat -f '%Su %Lp' "$path")" == "$(id -un) 600" ]] \
        || fail "$label must be owned by $(id -un) with mode 600"
    case "$path" in
        "$REPO_ROOT"/*) fail "$label must live outside the checkout" ;;
    esac
}

check_keychain_file() {
    [[ -f "$1" && ! -L "$1" ]] || fail "keychain $(basename "$1") is missing or a symlink"
}

unlock_keychain() {
    local keychain="$1" password_file="$2" password

    [[ -n "$password_file" ]] || return 0
    password="$(<"$password_file")"
    [[ -n "$password" ]] || fail "the password file of $(basename "$keychain") is empty"
    security unlock-keychain -p "$password" "$keychain" \
        || fail "cannot unlock keychain $(basename "$keychain")"
}

# Unlocks the release keychains with the runner's password files. Each signing
# or notarization phase calls this again, because a keychain can relock while
# Apple processes a long submission.
unlock_keychains() {
    unlock_keychain "$SIGNING_KEYCHAIN" "$KEYCHAIN_PASSWORD_FILE"
    unlock_keychain "$NOTARY_KEYCHAIN" "$NOTARY_KEYCHAIN_PASSWORD_FILE"
    KEYCHAINS_UNLOCKED=1
}

# Relocks the dedicated signing keychain. The login keychain and a notary
# keychain shared with other release apps stay as they were, since another
# runner may be using them.
lock_keychains() {
    if [[ "$KEYCHAINS_UNLOCKED" == 1 && "$SIGNING_KEYCHAIN" != "$LOGIN_KEYCHAIN" ]]; then
        security lock-keychain "$SIGNING_KEYCHAIN" 2>/dev/null || true
    fi
}

# Picks the Developer ID Application identity in the signing keychain. Without
# EASYDICT_TEAM_ID, the keychain must hold exactly one such identity.
resolve_signing_identity() {
    local identities matches count

    identities="$(security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" \
        | grep -F '"Developer ID Application:' || true)"
    if [[ -n "$TEAM_ID" ]]; then
        matches="$(grep -F "($TEAM_ID)\"" <<<"$identities" || true)"
    else
        matches="$identities"
    fi
    count="$(awk 'NF { n++ } END { print n + 0 }' <<<"$matches")"
    [[ "$count" -ge 1 ]] \
        || fail "no valid Developer ID Application identity in keychain $(basename "$SIGNING_KEYCHAIN")"
    [[ "$count" -eq 1 ]] \
        || fail "several Developer ID Application identities found; set EASYDICT_TEAM_ID"

    SIGN_IDENTITY_HASH="$(awk '{ print $2 }' <<<"$matches")"
    if [[ -z "$TEAM_ID" ]]; then
        TEAM_ID="$(sed -nE 's/.*\(([A-Z0-9]{10})\)"$/\1/p' <<<"$matches")"
    fi
    [[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "unable to read the Team ID"
}

preflight() {
    local tool feed_url public_key

    group "Preflight"
    for tool in xcodebuild xcrun codesign security ditto hdiutil spctl \
        shasum xmllint gh curl python3; do
        command -v "$tool" >/dev/null || fail "missing tool: $tool"
    done

    [[ -n "$NOTARY_PROFILE" ]] \
        || fail "set EASYDICT_NOTARY_PROFILE in the runner's private environment"
    [[ -n "$SPARKLE_KEY_FILE" ]] \
        || fail "set EASYDICT_SPARKLE_KEY_FILE in the runner's private environment"
    check_keychain_file "$SIGNING_KEYCHAIN"
    check_keychain_file "$NOTARY_KEYCHAIN"
    if [[ -n "$KEYCHAIN_PASSWORD_FILE" ]]; then
        check_private_file "$KEYCHAIN_PASSWORD_FILE" "keychain password file"
    fi
    if [[ -n "$NOTARY_KEYCHAIN_PASSWORD_FILE" ]]; then
        check_private_file "$NOTARY_KEYCHAIN_PASSWORD_FILE" "notary keychain password file"
    fi
    unlock_keychains

    resolve_signing_identity
    log "signing with the Developer ID Application identity of team $TEAM_ID"

    run_notarytool history --keychain-profile "$NOTARY_PROFILE" \
        --keychain "$NOTARY_KEYCHAIN" --output-format json >/dev/null \
        || fail "notarytool profile is missing or invalid; see docs/releases/fork-release.md"
    log "notarytool profile is valid"

    check_private_file "$SPARKLE_KEY_FILE" "Sparkle private key"
    feed_url="$(plist_value "$INFO_PLIST" SUFeedURL)"
    [[ "$feed_url" == "$FEED_URL" ]] \
        || fail "SUFeedURL is $feed_url, expected $FEED_URL"
    public_key="$(plist_value "$INFO_PLIST" SUPublicEDKey)"
    [[ "$(python3 "$HELPER" public-key --key-file "$SPARKLE_KEY_FILE")" \
        == "$public_key" ]] \
        || fail "SUPublicEDKey in Info.plist does not match the Sparkle private key"

    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        [[ -n "${GH_TOKEN:-}" ]] || fail "GH_TOKEN is not set"
    fi
    gh api "repos/$REPO" --jq .full_name >/dev/null \
        || fail "GitHub CLI cannot read $REPO"
    log "preflight passed"
    endgroup
}

# MARK: - Build

# Sets VERSION and BUILD from the project and the published feed. The latest
# release is kept as PREVIOUS_TAG and its feed as PREVIOUS_FEED; both are
# absent before the first release.
compute_version() {
    local marketing project_build next

    PREVIOUS_FEED="$OUT_DIR/previous-appcast.xml"
    rm -f "$PREVIOUS_FEED"
    PREVIOUS_TAG="$(gh release list --repo "$REPO" --exclude-drafts \
        --exclude-pre-releases --limit 1 \
        --json tagName --jq '.[].tagName')"
    if [[ -z "$PREVIOUS_TAG" ]]; then
        log "no published fork release yet; starting a new feed"
    else
        gh release download --repo "$REPO" --pattern appcast.xml \
            --output "$PREVIOUS_FEED" \
            || fail "cannot download appcast.xml from the latest release ($PREVIOUS_TAG)"
    fi

    read -r marketing project_build < <(python3 "$HELPER" project-version \
        --project "$PROJECT" --target "$SCHEME" --configuration Release)
    next="$(python3 "$HELPER" next-version \
        --project-build "$project_build" \
        --marketing-version "$marketing" \
        --appcast "$PREVIOUS_FEED")"
    BUILD="${next%% *}"
    VERSION="${next#* }"
    MARKETING_VERSION_BASE="$marketing"
    log "next release: $VERSION (build $BUILD)"
}

# Archives without signing; sign_app signs the result with the release
# keychain, which Xcode cannot search because it is not in the search list.
archive_app() {
    local archive="$OUT_DIR/Easydict.xcarchive"
    local archive_command

    archive_command=(
        xcodebuild archive
        -workspace "$WORKSPACE"
        -scheme "$SCHEME"
        -configuration Release
        -destination generic/platform=macOS
        -derivedDataPath "$DERIVED_DATA"
        -scmProvider system
        -archivePath "$archive"
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGNING_REQUIRED=NO
        MARKETING_VERSION="$VERSION"
        CURRENT_PROJECT_VERSION="$BUILD"
        DEPLOYMENT_POSTPROCESSING=YES
        ENABLE_DEBUG_DYLIB=NO
        EASYDICT_RELEASE_PACKAGING=YES
    )

    group "Archiving Easydict $VERSION"
    if ! "${archive_command[@]}" >"$OUT_DIR/archive.log" 2>&1; then
        tail -n 60 "$OUT_DIR/archive.log"
        log "incremental archive failed; retrying with clean DerivedData"
        rm -rf "$DERIVED_DATA" "$archive"
        "${archive_command[@]}" >"$OUT_DIR/archive.log" 2>&1 || {
            tail -n 80 "$OUT_DIR/archive.log"
            fail "archive failed"
        }
    fi

    APP="$OUT_DIR/Easydict.app"
    rm -rf "$APP"
    [[ -d "$archive/Products/Applications/Easydict.app" ]] \
        || fail "the archive does not contain Easydict.app"
    ditto "$archive/Products/Applications/Easydict.app" "$APP"
    endgroup
}

sign_code() {
    run_codesign --force --options runtime --timestamp \
        --keychain "$SIGNING_KEYCHAIN" \
        --sign "$SIGN_IDENTITY_HASH" "$@"
}

# Signs nested code from the inside out, then the app. Sparkle's helpers are
# signed before its framework, as Sparkle documents for manual signing, and
# Downloader.xpc keeps its sandbox entitlements.
sign_app() {
    local frameworks="$APP/Contents/Frameworks"
    local sparkle="$frameworks/Sparkle.framework/Versions/Current"
    local nested item

    group "Signing Easydict.app"
    for nested in PlugIns XPCServices Helpers Library/LoginItems; do
        [[ ! -e "$APP/Contents/$nested" ]] \
            || fail "Contents/$nested needs signing support in sign_app"
    done
    [[ -d "$sparkle" ]] || fail "Sparkle.framework is missing"

    unlock_keychains
    if [[ -e "$sparkle/XPCServices/Downloader.xpc" ]]; then
        sign_code --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
    fi
    for item in "$sparkle/XPCServices/Installer.xpc" "$sparkle/Updater.app" \
        "$sparkle/Autoupdate"; do
        if [[ -e "$item" ]]; then
            sign_code "$item"
        fi
    done

    while IFS= read -r item; do
        sign_code "$item"
    done < <(find "$frameworks" -mindepth 1 -maxdepth 1 \
        \( -name '*.framework' -o -name '*.dylib' \) | sort)

    sign_code --entitlements "$ENTITLEMENTS" "$APP"
    endgroup
}

verify_app() {
    local details

    group "Verifying app signature and metadata"
    [[ "$(plist_value "$APP/Contents/Info.plist" CFBundleShortVersionString)" == "$VERSION" ]] \
        || fail "the app has the wrong version"
    [[ "$(plist_value "$APP/Contents/Info.plist" CFBundleVersion)" == "$BUILD" ]] \
        || fail "the app has the wrong build"
    [[ "$(plist_value "$APP/Contents/Info.plist" SUFeedURL)" == "$FEED_URL" ]] \
        || fail "the app has the wrong SUFeedURL"

    run_codesign --verify --deep --strict --verbose=2 "$APP"
    details="$(run_codesign -dv --verbose=4 "$APP" 2>&1)"
    grep -Eq '^Authority=Developer ID Application: .*\('"$TEAM_ID"'\)$' <<<"$details" \
        || fail "the app is not signed with the Developer ID of team $TEAM_ID"
    grep -Fxq "TeamIdentifier=$TEAM_ID" <<<"$details" \
        || fail "the app has an unexpected TeamIdentifier"
    grep -Fq 'Timestamp=' <<<"$details" || fail "the app signature has no secure timestamp"
    grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$details" \
        || fail "the app is not signed with the hardened runtime"
    if run_codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'get-task-allow'; then
        fail "the app unexpectedly has the get-task-allow entitlement"
    fi
    grep -Fxq "TeamIdentifier=$TEAM_ID" \
        <<<"$(run_codesign -dv "$APP/Contents/Frameworks/Sparkle.framework" 2>&1)" \
        || fail "Sparkle.framework is not signed by team $TEAM_ID"
    endgroup
}

# MARK: - Notarization

# Submits a file and waits for Apple's verdict; prints Apple's log on rejection.
notarize() {
    local file="$1"
    local result attempt submission_id status

    result="$OUT_DIR/notary-$(basename "$file").json"
    for attempt in 1 2 3; do
        unlock_keychains
        log "notarizing $(basename "$file") (attempt $attempt/3)"
        run_notarytool submit "$file" \
            --keychain-profile "$NOTARY_PROFILE" \
            --keychain "$NOTARY_KEYCHAIN" \
            --wait --timeout 1h \
            --output-format json >"$result" 2>"$result.err" || true
        submission_id="$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("id", ""))
except Exception: print("")' "$result")"
        status="$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("status", ""))
except Exception: print("")' "$result")"

        case "$status" in
            Accepted)
                log "Apple accepted $(basename "$file") ($submission_id)"
                return
                ;;
            Invalid | Rejected)
                run_notarytool log "$submission_id" \
                    --keychain-profile "$NOTARY_PROFILE" \
                    --keychain "$NOTARY_KEYCHAIN" || true
                fail "Apple rejected $(basename "$file") ($submission_id)"
                ;;
        esac

        cat "$result.err" >&2 || true
        if [[ -n "$submission_id" ]]; then
            fail "notarization of $(basename "$file") did not finish: ${status:-unknown} ($submission_id)"
        fi
        if ((attempt < 3)); then
            log "upload failed; retrying in 30 seconds"
            sleep 30
        fi
    done
    fail "could not submit $(basename "$file") for notarization"
}

notarize_app() {
    local notary_zip="$OUT_DIR/Easydict-notary.zip"

    group "Notarizing app"
    rm -f "$notary_zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$notary_zip"
    notarize "$notary_zip"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=4 "$APP"
    endgroup
}

package_artifacts() {
    local staging="$OUT_DIR/dmg-root"

    ARTIFACTS="$OUT_DIR/artifacts"
    ZIP="$ARTIFACTS/Easydict.zip"
    DMG="$ARTIFACTS/Easydict.dmg"
    rm -rf "$ARTIFACTS" "$staging"
    mkdir -p "$ARTIFACTS" "$staging"

    group "Packaging ZIP and DMG"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

    ditto "$APP" "$staging/Easydict.app"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname Easydict -srcfolder "$staging" \
        -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    unlock_keychains
    run_codesign --sign "$SIGN_IDENTITY_HASH" --timestamp \
        --keychain "$SIGNING_KEYCHAIN" "$DMG"
    run_codesign --verify --strict --verbose=2 "$DMG"
    endgroup

    group "Notarizing DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature \
        --verbose=4 "$DMG"
    endgroup
}

# MARK: - Sparkle feed and release notes

write_release_notes() {
    local commit_url

    NOTES_MD="$OUT_DIR/notes.md"
    NOTES_HTML="$OUT_DIR/notes.html"
    commit_url="https://github.com/$REPO/commit/$SOURCE_SHA"

    if [[ -n "$PREVIOUS_TAG" ]]; then
        gh api "repos/$REPO/releases/generate-notes" \
            -f tag_name="$VERSION" \
            -f target_commitish="$SOURCE_SHA" \
            -f previous_tag_name="$PREVIOUS_TAG" \
            --jq .body >"$NOTES_MD"
    else
        printf '## What'"'"'s Changed\n* First release of the %s fork, based on Easydict %s.\n' \
            "$REPO" "$MARKETING_VERSION_BASE" >"$NOTES_MD"
    fi
    printf '\nBuilt from %s\n' "$commit_url" >>"$NOTES_MD"
    python3 "$HELPER" notes-html --input "$NOTES_MD" --output "$NOTES_HTML"
}

write_feed() {
    local signature_output signature public_key minimum_system

    group "Signing update and writing appcast"
    signature_output="$("$(sparkle_tool sign_update)" \
        --ed-key-file "$SPARKLE_KEY_FILE" "$ZIP")"
    signature="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<<"$signature_output")"
    [[ -n "$signature" ]] || fail "sign_update produced no signature"

    public_key="$(plist_value "$APP/Contents/Info.plist" SUPublicEDKey)"
    python3 "$HELPER" verify-signature \
        --file "$ZIP" --signature "$signature" --public-key "$public_key"

    minimum_system="$(plist_value "$APP/Contents/Info.plist" LSMinimumSystemVersion)"
    APPCAST="$ARTIFACTS/appcast.xml"
    python3 "$HELPER" appcast \
        --previous "$PREVIOUS_FEED" \
        --output "$APPCAST" \
        --repo "$REPO" \
        --version "$VERSION" \
        --build "$BUILD" \
        --archive "$ZIP" \
        --signature "$signature" \
        --minimum-system "$minimum_system" \
        --notes-html "$NOTES_HTML"
    xmllint --noout "$APPCAST"

    (cd "$ARTIFACTS" && shasum -a 256 Easydict.zip Easydict.dmg >SHA256SUMS.txt)
    endgroup
}

# MARK: - Publish

# Creates the release as a draft, checks every upload, then publishes it so
# the latest-release feed URL only moves once all assets are in place.
publish_release() {
    local existing_draft asset name expected actual

    group "Publishing GitHub release $VERSION"
    existing_draft="$(gh release view "$VERSION" --repo "$REPO" \
        --json isDraft --jq .isDraft 2>/dev/null || true)"
    case "$existing_draft" in
        true)
            log "removing the unpublished draft left by an earlier failed run"
            gh release delete "$VERSION" --repo "$REPO" --yes
            ;;
        false)
            fail "release $VERSION is already published"
            ;;
    esac

    gh release create "$VERSION" \
        "$ZIP" "$DMG" "$APPCAST" "$ARTIFACTS/SHA256SUMS.txt" \
        --repo "$REPO" \
        --target "$SOURCE_SHA" \
        --title "$VERSION" \
        --notes-file "$NOTES_MD" \
        --draft >/dev/null

    for asset in "$ZIP" "$DMG" "$APPCAST" "$ARTIFACTS/SHA256SUMS.txt"; do
        name="$(basename "$asset")"
        expected="$(stat -f %z "$asset")"
        actual="$(gh release view "$VERSION" --repo "$REPO" --json assets \
            --jq ".assets[] | select(.name == \"$name\" and .state == \"uploaded\") | .size")"
        [[ "$actual" == "$expected" ]] \
            || fail "uploaded $name has size '${actual:-missing}', expected $expected"
    done

    gh release edit "$VERSION" --repo "$REPO" --draft=false --latest >/dev/null
    endgroup
}

verify_public_feed() {
    local attempt feed

    group "Verifying public feed"
    for attempt in $(seq 1 20); do
        feed="$(curl -fsSL "$FEED_URL" 2>/dev/null || true)"
        if grep -Fq "<sparkle:version>$BUILD</sparkle:version>" <<<"$feed"; then
            curl -fsSIL -o /dev/null \
                "https://github.com/$REPO/releases/download/$VERSION/Easydict.zip" \
                || fail "public ZIP download is not reachable"
            log "public feed serves $VERSION (checked $attempt times)"
            endgroup
            return
        fi
        sleep 6
    done
    fail "public feed does not serve build $BUILD yet: $FEED_URL"
}

run_release() {
    SOURCE_SHA="${GITHUB_SHA:-$(git -C "$REPO_ROOT" rev-parse HEAD)}"
    [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] \
        || fail "checkout has uncommitted changes"

    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR" "$CACHE_DIR"
    trap lock_keychains EXIT

    preflight
    compute_version
    archive_app
    sign_app
    verify_app
    notarize_app
    package_artifacts
    write_release_notes
    write_feed
    publish_release
    verify_public_feed

    log "published https://github.com/$REPO/releases/tag/$VERSION"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '### Easydict %s\n\nhttps://github.com/%s/releases/tag/%s\n' \
            "$VERSION" "$REPO" "$VERSION" >>"$GITHUB_STEP_SUMMARY"
    fi
}

# MARK: - Sparkle key setup

# Creates the fork's Sparkle key in the login keychain (once), exports it to
# EASYDICT_SPARKLE_KEY_FILE, and writes the public key next to it. An existing
# key is reused, never replaced.
setup_sparkle_key() {
    local generate_keys public_key

    [[ -n "$SPARKLE_KEY_FILE" ]] || fail "set EASYDICT_SPARKLE_KEY_FILE"
    mkdir -p "$CACHE_DIR"
    resolve_packages
    generate_keys="$(sparkle_tool generate_keys)"

    "$generate_keys" --account "$SPARKLE_ACCOUNT" >/dev/null
    if [[ ! -e "$SPARKLE_KEY_FILE" ]]; then
        (umask 077 && "$generate_keys" --account "$SPARKLE_ACCOUNT" \
            -x "$SPARKLE_KEY_FILE")
        chmod 600 "$SPARKLE_KEY_FILE"
    fi
    check_private_file "$SPARKLE_KEY_FILE" "Sparkle private key"

    public_key="$(python3 "$HELPER" public-key --key-file "$SPARKLE_KEY_FILE")"
    [[ "$public_key" == "$("$generate_keys" --account "$SPARKLE_ACCOUNT" -p)" ]] \
        || fail "the exported key does not match keychain account $SPARKLE_ACCOUNT"
    printf '%s\n' "$public_key" >"$SPARKLE_KEY_FILE.pub"
    printf 'SUPublicEDKey: %s\n' "$public_key"
}

main() {
    case "${1:-}" in
        run) run_release ;;
        preflight)
            mkdir -p "$CACHE_DIR"
            trap lock_keychains EXIT
            preflight
            ;;
        setup-sparkle-key) setup_sparkle_key ;;
        *) fail "usage: fork-release.sh run|preflight|setup-sparkle-key" ;;
    esac
}

main "$@"
