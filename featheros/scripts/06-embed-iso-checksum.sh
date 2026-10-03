#!/usr/bin/env bash
#
# 06-embed-iso-checksum.sh
#
# BUILD-TIME. Run this as the last step after the FeatherOS ISO is
# otherwise finished. Embeds a checksum INTO the ISO itself using
# implantisomd5 (from Alpine's isomd5sum package) — this is the same
# mechanism Fedora/Ubuntu use for their "verify media" boot option.
#
# How it works: implantisomd5 writes the checksum into unused padding
# space within the ISO9660 structure, computed over the rest of the
# ISO's content. This doesn't change the ISO's file layout or size.
# checkisomd5 (used at boot — see iso-integrity-check.sh) re-derives
# the same checksum from the booted media and compares.
#
# Install the tool first (on the Alpine build host):
#   apk add isomd5sum
#
# Usage: ./06-embed-iso-checksum.sh /path/to/featheros.iso
#
set -euo pipefail

ISO_PATH="${1:-}"
if [ -z "$ISO_PATH" ] || [ ! -f "$ISO_PATH" ]; then
    echo "Usage: $0 /path/to/featheros.iso" >&2
    exit 1
fi

if ! command -v implantisomd5 >/dev/null 2>&1; then
    echo "implantisomd5 not found." >&2
    echo "Install it: apk add isomd5sum" >&2
    exit 1
fi

echo "Embedding checksum into: $ISO_PATH"
implantisomd5 "$ISO_PATH"
echo "Done. Verify with: checkisomd5 $ISO_PATH"
echo
echo "Note: this detects corruption (bad download, bad USB burn) —"
echo "it is not a defense against deliberate tampering by someone who"
echo "can also re-embed a matching checksum after modifying the ISO."
echo "That would need cryptographic signing with a trust anchor"
echo "outside the ISO itself (e.g. a detached GPG signature published"
echo "separately), which is a reasonable thing to add later but is a"
echo "different mechanism from this one."
