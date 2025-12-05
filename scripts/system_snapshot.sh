#!/usr/bin/env bash
set -euo pipefail

source /home/docker/.env 2>/dev/null || true

timestamp=$(date -Iseconds)

# Helper to capture command output safely
safe() {
  local cmd="$1"
  bash -c "$cmd" 2>/dev/null || echo ""
}

# ---- Docker Metrics ----
docker_stats=$(docker stats --no-stream --format '{{json .}}' | jq -s '.')
docker_ps=$(docker ps --format '{{json .}}' | jq -s '.')

# ---- SMART ----
smart_sda=$(safe "sudo smartctl -a /dev/sda --json")
smart_sdb=$(safe "sudo smartctl -a /dev/sdb --json")
smart_nvme=$(safe "sudo smartctl -a /dev/nvme0n1 --json")

# ---- RAID ----
raid=$(safe "sudo mdadm --detail /dev/md0")

# ---- Btrfs ----
btrfs_scrub=$(safe "btrfs scrub status /")
btrfs_device=$(safe "btrfs device stats /")
btrfs_balance=$(safe "btrfs balance status /")

# ---- VM ----
vm_stats=$(safe "virsh domstats haos")
vm_mem=$(safe "virsh dommemstat haos")

# ---- MergerFS Tiering ----
ssd="/mnt/plexcache/media"
hdd="/home/docker/shared/media_volume/media"

ssd_kb=$(du -s "$ssd" 2>/dev/null | awk '{print $1}')
hdd_kb=$(du -s "$hdd" 2>/dev/null | awk '{print $1}')

# ---- System Load ----
read load1 load5 load15 _ < /proc/loadavg

# ---- Memory ----
mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
mem_free=$(grep MemAvailable /proc/meminfo | awk '{print $2}')

# ---- Extra Disk Metrics ----
iostat_json=$(safe "iostat -dxk 1 1 | jq -R -s '.'")
df_json=$(safe "df -kP | jq -R -s '.'")
df_inode_json=$(safe "df -iP | jq -R -s '.'")
lsblk_json=$(safe "lsblk -OJ")
mounts=$(safe "mount -v | jq -R -s '.'")

# I/O scheduler per block device
scheduler_json=$(safe "for dev in /sys/block/*/queue/scheduler; do echo -n \"\${dev%/queue/scheduler}: \"; cat \"\$dev\"; done | jq -R -s '.'")

# Pressure Stall Information
psi_io=$(safe "cat /proc/pressure/io | jq -R -s('.')")

# Quick SMART health summary
smart_health_sda=$(safe "sudo smartctl -H /dev/sda --json")
smart_health_sdb=$(safe "sudo smartctl -H /dev/sdb --json")
smart_health_nvme=$(safe "sudo smartctl -H /dev/nvme0n1 --json")

# ---- Construct the JSON ----
jq -n \
  --arg timestamp "$timestamp" \
  --argjson docker_stats "$docker_stats" \
  --argjson docker_ps "$docker_ps" \
  --argjson smart_sda "${smart_sda:-null}" \
  --argjson smart_sdb "${smart_sdb:-null}" \
  --argjson smart_nvme "${smart_nvme:-null}" \
  --arg raid "$raid" \
  --arg btrfs_scrub "$btrfs_scrub" \
  --arg btrfs_device "$btrfs_device" \
  --arg btrfs_balance "$btrfs_balance" \
  --arg vm_stats "$vm_stats" \
  --arg vm_mem "$vm_mem" \
  --arg ssd_kb "$ssd_kb" \
  --arg hdd_kb "$hdd_kb" \
  --arg load1 "$load1" \
  --arg load5 "$load5" \
  --arg load15 "$load15" \
  --arg mem_total "$mem_total" \
  --arg mem_free "$mem_free" \
  --argjson iostat_json "$iostat_json" \
  --argjson df_json "$df_json" \
  --argjson df_inode_json "$df_inode_json" \
  --argjson lsblk_json "$lsblk_json" \
  --arg mounts "$mounts" \
  --arg scheduler_json "$scheduler_json" \
  --arg psi_io "$psi_io" \
  --argjson smart_health_sda "${smart_health_sda:-null}" \
  --argjson smart_health_sdb "${smart_health_sdb:-null}" \
  --argjson smart_health_nvme "${smart_health_nvme:-null}" \
  '
{
  timestamp: $timestamp,
  docker: {
    stats: $docker_stats,
    ps: $docker_ps
  },
  disks: {
    smart: {
      sda: $smart_sda,
      sdb: $smart_sdb,
      nvme0n1: $smart_nvme
    },
    smart_health: {
      sda: $smart_health_sda,
      sdb: $smart_health_sdb,
      nvme0n1: $smart_health_nvme
    },
    usage: {
      df: $df_json,
      df_inodes: $df_inode_json,
      lsblk: $lsblk_json,
      mounts: $mounts
    },
    io: {
      iostat: $iostat_json,
      scheduler: $scheduler_json,
      psi: $psi_io
    },
    raid: $raid
  },
  btrfs: {
    scrub: $btrfs_scrub,
    device: $btrfs_device,
    balance: $btrfs_balance
  },
  vm: {
    haos: {
      stats: $vm_stats,
      mem: $vm_mem
    }
  },
  mergerfs: {
    SSD_KB: ($ssd_kb|tonumber),
    HDD_KB: ($hdd_kb|tonumber)
  },
  system: {
    load1: ($load1|tonumber),
    load5: ($load5|tonumber),
    load15: ($load15|tonumber),
    MemTotalKB: ($mem_total|tonumber),
    MemFreeKB: ($mem_free|tonumber)
  }
}
'
