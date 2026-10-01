#!/usr/bin/env bash
# Muxes "name S1 - 01.mkv" from VIDEO_DIR with "name S1 - 01.mka" from AUDIO_DIR.
# Files are matched by name. Streams are copied as-is (no re-encoding).
#
# Usage:
#   ./mux.sh VIDEO_DIR AUDIO_DIR [OUT_DIR]
#
#   OUT_DIR defaults to VIDEO_DIR/muxed.
#   REPLACE_AUDIO=1 ./mux.sh ...   drop the original audio from the video, keep only the .mka audio

set -uo pipefail

if (( $# < 2 )); then
    echo "Usage: $0 VIDEO_DIR AUDIO_DIR [OUT_DIR]" >&2
    exit 1
fi

VIDEO_DIR="$1"
AUDIO_DIR="$2"
OUT_DIR="${3:-$VIDEO_DIR/muxed}"
REPLACE_AUDIO="${REPLACE_AUDIO:-0}"

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is required." >&2; exit 1; }
[[ -d "$VIDEO_DIR" ]] || { echo "Video directory not found: $VIDEO_DIR" >&2; exit 1; }
[[ -d "$AUDIO_DIR" ]] || { echo "Audio directory not found: $AUDIO_DIR" >&2; exit 1; }
mkdir -p "$OUT_DIR"
shopt -s nullglob

ok=0; skipped=0; failed=0

for video in "$VIDEO_DIR"/*.mkv; do
    name="$(basename "$video" .mkv)"
    audio="$AUDIO_DIR/$name.mka"
    out="$OUT_DIR/$name.mkv"

    if [[ ! -f "$audio" ]]; then
        echo "⚠ no audio for: $name"
        skipped=$((skipped + 1)); continue
    fi
    if [[ -e "$out" ]]; then
        echo "↷ already done: $name"
        skipped=$((skipped + 1)); continue
    fi

    # Take every stream from the video (video, audio, subtitles, attachments),
    # optionally drop its audio, then add all audio streams from the .mka
    maps=(-map 0)
    [[ "$REPLACE_AUDIO" == 1 ]] && maps+=(-map -0:a)
    maps+=(-map 1:a)

    echo "→ $name"
    if ffmpeg -hide_banner -loglevel error -n \
            -i "$video" -i "$audio" "${maps[@]}" -c copy "$out"; then
        ok=$((ok + 1))
    else
        echo "✗ failed: $name" >&2
        rm -f "$out"
        failed=$((failed + 1))
    fi
done

echo
echo "Done: $ok, skipped: $skipped, failed: $failed → $OUT_DIR"
