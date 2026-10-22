#!/usr/bin/env python3
"""Version, release-notes, and Sparkle feed helpers for fork releases.

The shell pipeline owns building, signing, and publishing. This helper keeps
the parts that need structured data in one place: choosing the next build,
rendering GitHub's release notes for Sparkle, writing the appcast, and checking
that the update archive verifies with the public key shipped in the app.
Only the standard library is used so the self-hosted runner needs no packages.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import html
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from base64 import b64decode, b64encode
from email.utils import formatdate
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

# Older items are kept so users on recent builds still see a coherent history.
MAX_FEED_ITEMS = 10


def sparkle_tag(name: str) -> str:
    """Return a namespaced Sparkle XML tag."""
    return f"{{{SPARKLE_NS}}}{name}"


def fail(message: str) -> None:
    print(f"fork_release.py: {message}", file=sys.stderr)
    sys.exit(1)


# MARK: - Version


def feed_builds(appcast: Path | None) -> list[int]:
    """Return every integer `sparkle:version` in an existing feed."""
    if appcast is None or not appcast.is_file():
        return []
    root = ET.parse(appcast).getroot()
    builds = []
    for node in root.iter(sparkle_tag("version")):
        text = (node.text or "").strip()
        if not text.isdigit():
            fail(f"feed contains a non-integer build: {text!r}")
        builds.append(int(text))
    return builds


def command_project_version(args: argparse.Namespace) -> None:
    """Print `<marketing version> <build>` of a target's build configuration."""
    project = json.loads(
        subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(args.project / "project.pbxproj")],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    objects = project["objects"]
    targets = [
        node
        for node in objects.values()
        if node.get("isa") == "PBXNativeTarget" and node.get("name") == args.target
    ]
    if len(targets) != 1:
        fail(f"expected one target named {args.target}, found {len(targets)}")
    configurations = objects[targets[0]["buildConfigurationList"]]["buildConfigurations"]
    for identifier in configurations:
        configuration = objects[identifier]
        if configuration.get("name") == args.configuration:
            settings = configuration["buildSettings"]
            print(settings["MARKETING_VERSION"], settings["CURRENT_PROJECT_VERSION"])
            return
    fail(f"{args.target} has no {args.configuration} configuration")


def command_next_version(args: argparse.Namespace) -> None:
    """Print `<build> <version>` for the next release.

    The build must stay above both the project's build and every published
    fork build, so merging upstream never reuses or lowers a build number.
    """
    if not args.project_build.isdigit():
        fail(f"project build is not an integer: {args.project_build!r}")
    if not re.fullmatch(r"\d+(\.\d+){1,2}", args.marketing_version):
        fail(f"unexpected marketing version: {args.marketing_version!r}")

    previous = feed_builds(args.appcast)
    build = max([int(args.project_build), *previous]) + 1
    print(build, f"{args.marketing_version}.{build}")


# MARK: - Release notes


INLINE_LINK = re.compile(r"\[([^\]]+)\]\((https?://[^)\s]+)\)")
BARE_URL = re.compile(r"(?<![\"=>])(https?://[^\s<]+)")
BOLD = re.compile(r"\*\*(.+?)\*\*")
CODE = re.compile(r"`([^`]+)`")


def link_bare_url(match: re.Match) -> str:
    """Link a bare URL, leaving trailing sentence punctuation outside it."""
    url = match.group(1).rstrip(".,;:!?)")
    return f'<a href="{url}">{url}</a>{match.group(1)[len(url):]}'


def render_inline(text: str) -> str:
    """Render the inline Markdown that GitHub's generated notes use."""
    rendered = html.escape(text, quote=False)
    rendered = CODE.sub(r"<code>\1</code>", rendered)
    rendered = BOLD.sub(r"<strong>\1</strong>", rendered)
    rendered = INLINE_LINK.sub(r'<a href="\2">\1</a>', rendered)
    return BARE_URL.sub(link_bare_url, rendered)


def render_notes(markdown: str) -> str:
    """Render headings, bullet lists, and paragraphs to Sparkle HTML."""
    markdown = re.sub(r"<!--.*?-->", "", markdown, flags=re.DOTALL)
    blocks: list[str] = []
    list_items: list[str] = []
    paragraph: list[str] = []

    def flush() -> None:
        if list_items:
            blocks.append("<ul>\n" + "\n".join(list_items) + "\n</ul>")
            list_items.clear()
        if paragraph:
            blocks.append("<p>" + " ".join(paragraph) + "</p>")
            paragraph.clear()

    for raw_line in markdown.splitlines():
        line = raw_line.strip()
        heading = re.match(r"(#{1,4})\s+(.*)", line)
        bullet = re.match(r"[*-]\s+(.*)", line)
        if not line:
            flush()
        elif heading:
            flush()
            level = len(heading.group(1))
            blocks.append(f"<h{level}>{render_inline(heading.group(2))}</h{level}>")
        elif bullet:
            if paragraph:
                flush()
            list_items.append(f"<li>{render_inline(bullet.group(1))}</li>")
        else:
            if list_items:
                flush()
            paragraph.append(render_inline(line))
    flush()
    return "\n".join(blocks)


def command_notes_html(args: argparse.Namespace) -> None:
    args.output.write_text(render_notes(args.input.read_text()) + "\n")


# MARK: - Ed25519 verification (RFC 8032, section 6)

ED_P = 2**255 - 19
ED_Q = 2**252 + 27742317777372353535851937790883648493
ED_D = -121665 * pow(121666, ED_P - 2, ED_P) % ED_P
ED_SQRT_M1 = pow(2, (ED_P - 1) // 4, ED_P)


def ed_add(p1: tuple, p2: tuple) -> tuple:
    a = (p1[1] - p1[0]) * (p2[1] - p2[0]) % ED_P
    b = (p1[1] + p1[0]) * (p2[1] + p2[0]) % ED_P
    c = 2 * p1[3] * p2[3] * ED_D % ED_P
    d = 2 * p1[2] * p2[2] % ED_P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f, g * h, f * g, e * h)


def ed_mul(scalar: int, point: tuple) -> tuple:
    result = (0, 1, 1, 0)
    while scalar > 0:
        if scalar & 1:
            result = ed_add(result, point)
        point = ed_add(point, point)
        scalar >>= 1
    return result


def ed_equal(p1: tuple, p2: tuple) -> bool:
    return (p1[0] * p2[2] - p2[0] * p1[2]) % ED_P == 0 and (
        p1[1] * p2[2] - p2[1] * p1[2]
    ) % ED_P == 0


def ed_recover_x(y: int, sign: int) -> int | None:
    if y >= ED_P:
        return None
    x2 = (y * y - 1) * pow(ED_D * y * y + 1, ED_P - 2, ED_P)
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (ED_P + 3) // 8, ED_P)
    if (x * x - x2) % ED_P != 0:
        x = x * ED_SQRT_M1 % ED_P
    if (x * x - x2) % ED_P != 0:
        return None
    if (x & 1) != sign:
        x = ED_P - x
    return x


def ed_decompress(data: bytes) -> tuple | None:
    y = int.from_bytes(data, "little")
    sign = y >> 255
    y &= (1 << 255) - 1
    x = ed_recover_x(y, sign)
    return None if x is None else (x, y, 1, x * y % ED_P)


ED_G_Y = 4 * pow(5, ED_P - 2, ED_P) % ED_P
ED_G_X = ed_recover_x(ED_G_Y, 0)
ED_G = (ED_G_X, ED_G_Y, 1, ED_G_X * ED_G_Y % ED_P)


def ed25519_verify(public_key: bytes, message: bytes, signature: bytes) -> bool:
    if len(public_key) != 32 or len(signature) != 64:
        return False
    a_point = ed_decompress(public_key)
    r_point = ed_decompress(signature[:32])
    if a_point is None or r_point is None:
        return False
    s = int.from_bytes(signature[32:], "little")
    if s >= ED_Q:
        return False
    digest = hashlib.sha512(signature[:32] + public_key + message).digest()
    h = int.from_bytes(digest, "little") % ED_Q
    return ed_equal(ed_mul(s, ED_G), ed_add(r_point, ed_mul(h, a_point)))


def ed_compress(point: tuple) -> bytes:
    z_inverse = pow(point[2], ED_P - 2, ED_P)
    x = point[0] * z_inverse % ED_P
    y = point[1] * z_inverse % ED_P
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")


def sparkle_public_key(private_key: bytes) -> bytes:
    """Return the public key of a key file exported by Sparkle's generate_keys.

    Sparkle exports a 32-byte seed; older tools wrote the seed followed by
    the public key (64 bytes) or an expanded key followed by it (96 bytes).
    """
    if len(private_key) == 32:
        digest = hashlib.sha512(private_key).digest()
        scalar = int.from_bytes(digest[:32], "little")
        scalar &= (1 << 254) - 8
        scalar |= 1 << 254
        return ed_compress(ed_mul(scalar, ED_G))
    if len(private_key) in (64, 96):
        return private_key[-32:]
    fail(f"unsupported Sparkle private key length: {len(private_key)} bytes")
    return b""


def command_public_key(args: argparse.Namespace) -> None:
    """Print the base64 public key that matches a Sparkle private key file."""
    private_key = b64decode(args.key_file.read_text().strip(), validate=True)
    print(b64encode(sparkle_public_key(private_key)).decode())


def command_verify_signature(args: argparse.Namespace) -> None:
    """Fail unless the archive verifies with the key embedded in the app."""
    public_key = b64decode(args.public_key, validate=True)
    signature = b64decode(args.signature, validate=True)
    if not ed25519_verify(public_key, args.file.read_bytes(), signature):
        fail(
            f"{args.file.name} does not verify with SUPublicEDKey; "
            "the Sparkle private key does not match the app"
        )
    print(f"{args.file.name}: EdDSA signature matches SUPublicEDKey")


# MARK: - Appcast


def build_item(args: argparse.Namespace) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = args.version
    ET.SubElement(item, "pubDate").text = formatdate(localtime=True)
    ET.SubElement(item, "description").text = args.notes_html.read_text().strip()
    ET.SubElement(item, sparkle_tag("version")).text = args.build
    ET.SubElement(item, sparkle_tag("shortVersionString")).text = args.version
    ET.SubElement(item, sparkle_tag("fullReleaseNotesLink")).text = (
        f"https://github.com/{args.repo}/releases/tag/{args.version}"
    )
    ET.SubElement(item, sparkle_tag("minimumSystemVersion")).text = args.minimum_system
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": f"https://github.com/{args.repo}/releases/download/"
            f"{args.version}/{args.archive.name}",
            "length": str(args.archive.stat().st_size),
            "type": "application/octet-stream",
            sparkle_tag("edSignature"): args.signature,
        },
    )
    return item


def command_appcast(args: argparse.Namespace) -> None:
    """Write a feed with the new item first, followed by recent fork items."""
    previous_items: list[ET.Element] = []
    if args.previous is not None and args.previous.is_file():
        channel = ET.parse(args.previous).getroot().find("channel")
        if channel is None:
            fail("previous appcast has no channel")
        previous_items = [copy.deepcopy(item) for item in channel.findall("item")]

    if args.build in {
        (item.findtext(sparkle_tag("version")) or "").strip() for item in previous_items
    }:
        fail(f"build {args.build} is already in the published feed")

    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Easydict"
    channel.append(build_item(args))
    channel.extend(previous_items[: MAX_FEED_ITEMS - 1])

    ET.indent(rss, space="    ")
    tree = ET.ElementTree(rss)
    tree.write(args.output, encoding="UTF-8", xml_declaration=True)
    with args.output.open("a") as feed:
        feed.write("\n")


# MARK: - CLI


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    project_version = commands.add_parser("project-version")
    project_version.add_argument("--project", type=Path, required=True)
    project_version.add_argument("--target", default="Easydict")
    project_version.add_argument("--configuration", default="Release")
    project_version.set_defaults(handler=command_project_version)

    next_version = commands.add_parser("next-version")
    next_version.add_argument("--project-build", required=True)
    next_version.add_argument("--marketing-version", required=True)
    next_version.add_argument("--appcast", type=Path)
    next_version.set_defaults(handler=command_next_version)

    notes = commands.add_parser("notes-html")
    notes.add_argument("--input", type=Path, required=True)
    notes.add_argument("--output", type=Path, required=True)
    notes.set_defaults(handler=command_notes_html)

    public_key = commands.add_parser("public-key")
    public_key.add_argument("--key-file", type=Path, required=True)
    public_key.set_defaults(handler=command_public_key)

    verify = commands.add_parser("verify-signature")
    verify.add_argument("--file", type=Path, required=True)
    verify.add_argument("--signature", required=True)
    verify.add_argument("--public-key", required=True)
    verify.set_defaults(handler=command_verify_signature)

    appcast = commands.add_parser("appcast")
    appcast.add_argument("--previous", type=Path)
    appcast.add_argument("--output", type=Path, required=True)
    appcast.add_argument("--repo", required=True)
    appcast.add_argument("--version", required=True)
    appcast.add_argument("--build", required=True)
    appcast.add_argument("--archive", type=Path, required=True)
    appcast.add_argument("--signature", required=True)
    appcast.add_argument("--minimum-system", required=True)
    appcast.add_argument("--notes-html", type=Path, required=True)
    appcast.set_defaults(handler=command_appcast)

    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
