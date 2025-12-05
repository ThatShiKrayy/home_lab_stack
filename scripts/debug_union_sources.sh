#!/bin/bash
set -euo pipefail

LOG="/tmp/mergerfs_union_debug.log"
> "$LOG"

declare -a SOURCES=(
  "/mnt/plexcache/media/Movies"
  "/mnt/plexcache/media/TV"
  "/home/docker/shared/media_volume/media/Movies"
  "/home/docker/shared/media_volume/media/TV"
)

echo "[DEBUG] Scanning MergerFS source directories..." | tee -a "$LOG"

for dir in "${SOURCES[@]}"; do
  echo -e "\n===== $dir =====" | tee -a "$LOG"

  if [ ! -d "$dir" ]; then
    echo "[ERROR] Directory not found!" | tee -a "$LOG"
    continue
  fi

  count=$(find "$dir" -mindepth 1 | wc -l)

  if [[ "$count" -eq 0 ]]; then
    echo "[WARNING] Directory is empty." | tee -a "$LOG"
  else
    find "$dir" -type f -printf '%T@ %p\n' | sort -n | head -10 | awk '{print $2}' | tee -a "$LOG"
  fi
done

echo -e "\n[RESULT] Full log written to: $LOG"
