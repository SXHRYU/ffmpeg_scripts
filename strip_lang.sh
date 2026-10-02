#!/usr/bin/env bash
# Removes audio tracks with the given language tag from .mkv files, without re-encoding.
#
# Usage:
#   ./strip-audio.sh PATH TAG             PATH is a .mkv file or a directory with .mkv files
#   INPLACE=1 ./strip-audio.sh PATH TAG   overwrite the sources instead of writing to stripped/
#
# No track with TAG               -> error and a list of the file's audio tracks
# Removal would leave no audio    -> warning, the file is left alone (e.g. a single audio track)

set -uo pipefail

(( $# == 2 )) || { echo "Usage: $0 PATH TAG" >&2; exit 1; }
TAG="$(tr '[:upper:]' '[:lower:]' <<< "$2")"
INPLACE="${INPLACE:-0}"
shopt -s nullglob
[[ -d "$1" ]] && files=("$1"/*.mkv) || files=("$1")

ok=0; skipped=0; failed=0

for f in "${files[@]}"; do
    name="$(basename "$f")"
    dir="$(dirname "$f")"
    [[ -f "$f" ]] || { echo "✗ not found: $f" >&2; failed=$((failed + 1)); continue; }

    # One line per audio track: "index,language"
    tracks="$(ffprobe -v error -select_streams a -show_entries stream=index:stream_tags=language -of csv=p=0 "$f")"
    total=$(grep -c . <<< "$tracks")
    matched=($(awk -F, -v t="$TAG" 'tolower($2) == t { print $1 }' <<< "$tracks"))

    if (( ${#matched[@]} == 0 )); then
        echo "✗ no audio track tagged '$TAG' in $name, available tracks:" >&2
        ffprobe -v error -select_streams a -of compact=p=0 \
            -show_entries stream=index,codec_name:stream_tags=language,title "$f" | sed 's/^/    /' >&2
        failed=$((failed + 1)); continue
    fi
    if (( ${#matched[@]} == total )); then
        echo "⚠ removing '$TAG' would leave no audio ($total track(s)), skipping: $name"
        skipped=$((skipped + 1)); continue
    fi

    if [[ "$INPLACE" == 1 ]]; then
        out="$dir/.$name.tmp.mkv"
    else
        out="$dir/stripped/$name"
        [[ -e "$out" ]] && { echo "↷ already done: $name"; skipped=$((skipped + 1)); continue; }
        mkdir -p "$dir/stripped"
    fi

    # Keep every stream except the matched audio tracks; the first remaining audio becomes default
    maps=(-map 0)
    for i in "${matched[@]}"; do maps+=(-map "-0:$i"); done

    echo "→ $name"
    if ffmpeg -hide_banner -loglevel error -y -i "$f" "${maps[@]}" -c copy \
            -disposition:a 0 -disposition:a:0 default "$out"; then
        [[ "$INPLACE" == 1 ]] && mv -f "$out" "$f"
        ok=$((ok + 1))
    else
        echo "✗ ffmpeg failed: $name" >&2
        rm -f "$out"
        failed=$((failed + 1))
    fi
done

echo
echo "Processed: $ok, skipped: $skipped, errors: $failed"
(( failed == 0 ))
