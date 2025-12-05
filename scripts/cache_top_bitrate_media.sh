#!/usr/bin/env bash

########################################################################
# cache_top_bitrate_media.sh — CLEAN PARSING FIXED VERSION
########################################################################

trap '' SIGPIPE
set -euo pipefail

# CONFIG
UNION_ROOT="/home/docker/shared/media_volume/media"
MOVIES_DIR="$UNION_ROOT/Movies"
TV_DIR="$UNION_ROOT/TV"
CACHE_ROOT="/mnt/plexcache/media"

MAX_CANDIDATES=15
THRESHOLD_USED_PERCENT=85
MIN_FREE_PERCENT=15

RSYNC_OPTS=(
  --recursive --links --hard-links
  --partial --inplace --progress
  --no-perms --no-owner --no-group --no-times --omit-dir-times
)

log() { printf '[CACHE] [%s] %s\n' "$(date '+%F %T')" "$*"; }

# SANITY
[[ -d "$MOVIES_DIR" ]] || { log "Missing $MOVIES_DIR"; exit 1; }
[[ -d "$TV_DIR"     ]] || { log "Missing $TV_DIR"; exit 1; }
mkdir -p "$CACHE_ROOT"

# ENUMERATE FILES
log "Scanning Movies + TV for video files..."

mapfile -d '' files < <(
  find "$MOVIES_DIR" "$TV_DIR" -type f \
    \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.avi' \) \
    -print0
)

(( ${#files[@]} == 0 )) && { log "No media files - quitting"; exit 0; }

# BITRATE SCAN
log "Calculating bit-rates (ffprobe)..."

bitrate_list=()

for file in "${files[@]}"; do
    log "ffprobe: $(basename "$file")"

    bitrate=0

    if raw=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=bit_rate \
            -of default=nw=1:nk=1 "$file" | grep -E '^[0-9]+$'); then
        bitrate=$raw

    elif raw=$(ffprobe -v error \
            -show_entries format=bit_rate \
            -of default=nw=1:nk=1 "$file" | grep -E '^[0-9]+$'); then
        bitrate=$raw

    else
        duration=$(ffprobe -v error -show_entries format=duration \
                   -of csv=p=0 "$file" || echo 0)
        size=$(stat -c %s "$file")
        if (( $(echo "$duration > 0" | bc -l) )); then
            bitrate=$(( (size * 8) / duration ))
        fi
    fi

    (( bitrate > 0 )) && bitrate_list+=("${bitrate}"$'\t'"${file}")
done

(( ${#bitrate_list[@]} == 0 )) && { log "No measurable bitrates - quitting"; exit 0; }

# TOP FILES
mapfile -t sorted_candidates < <(
  printf '%s\n' "${bitrate_list[@]}" |
    sort -nr 2>/dev/null |
    head -n "$MAX_CANDIDATES"
)

log "Top candidates:"
printf '%s\n' "${sorted_candidates[@]}"

# DETERMINE CACHE TARGETS
to_cache=()

for clean in "${sorted_candidates[@]}"; do
    IFS=$'\t' read -r bitrate full_path <<< "$clean"

    rel_path="${full_path#$UNION_ROOT/}"
    ssd_path="${CACHE_ROOT}/${rel_path}"

    [[ -f "$ssd_path" ]] && continue

    mkdir -p "$(dirname "$ssd_path")"
    to_cache+=("${bitrate}"$'\t'"${full_path}"$'\t'"${ssd_path}")
done

(( ${#to_cache[@]} == 0 )) && { log "All top files already cached."; exit 0; }

# COPY TO SSD
cache_used_pct() {
  df --output=pcent "$CACHE_ROOT" | tail -n1 | tr -dc '0-9'
}

for clean in "${to_cache[@]}"; do
    IFS=$'\t' read -r bitrate src_path ssd_path <<< "$clean"

    used_before=$(cache_used_pct)
    if (( used_before >= (100 - MIN_FREE_PERCENT) )); then
        log "Cache at ${used_before}% - stopping"
        break
    fi

    mbps=$(( bitrate / 1000000 ))
    log "Caching $(basename "$src_path") (${mbps} Mbps)..."

    rsync "${RSYNC_OPTS[@]}" "$src_path" "$ssd_path" || {
        rc=$?
        if (( rc == 23 || rc == 24 )); then
            log "Non-fatal rsync warning ($rc)"
        else
            log "Fatal rsync error $rc"; exit $rc;
        fi
    }

    log "Done: $(basename "$src_path")"
done

# CACHE PRUNE
used_percent=$(cache_used_pct)

if (( used_percent >= THRESHOLD_USED_PERCENT )); then
  log "Cache ${used_percent}% >= ${THRESHOLD_USED_PERCENT}% - pruning LRU..."

  while IFS= read -r -d '' file; do
    log "Deleting $file"
    rm -f "$file"

    used_percent=$(cache_used_pct)
    (( used_percent < THRESHOLD_USED_PERCENT )) && break
  done < <(
    find "$CACHE_ROOT" -type f -printf '%T@\t%p\0' |
      sort -z -n | awk -F '\t' '{print $2}'
  )

  log "Post-prune usage: ${used_percent}%"
else
  log "Cache at ${used_percent}% - pruning not needed."
fi

exit 0
