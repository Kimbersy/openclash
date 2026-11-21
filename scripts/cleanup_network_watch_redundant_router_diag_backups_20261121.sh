#!/bin/sh
# One-time safe cleanup: only byte-identical, redundant dated router-diag backups.
# Live failover, diag, semantic DNS-fix backup, incident evidence and active logs are never deleted.
set -eu
DIR='/mnt/sata1-4/network-watch'
cd "$DIR" || { echo 'HOLD: network-watch directory missing'; exit 1; }
[ "$(pwd -P)" = "$DIR" ] || { echo 'HOLD: unexpected resolved working directory'; exit 1; }
command -v cmp >/dev/null 2>&1 || { echo 'HOLD: cmp command unavailable'; exit 1; }
[ -f router-diag.sh ] || { echo 'HOLD: current router-diag.sh missing'; exit 1; }
[ -f router-diag.sh.bak.20260929-234327 ] || { echo 'HOLD: newest dated router-diag backup missing'; exit 1; }
echo 'PRESERVED: router-diag.sh (active source file)'
echo 'PRESERVED: router-diag.sh.bak.20260929-234327 (dated fallback)'
echo 'PRESERVED: router-diag.sh.bak-dnsfix (named fallback)'
echo 'PRESERVED: openclash-failover* (active log and distinct rollback versions)'
echo 'PRESERVED: incident/logread/pid-on-burst evidence'
deleted=0
for file in router-diag.sh.bak.20260929-234305 router-diag.sh.bak.20260929-234310; do
  [ -f "$file" ] || { echo "SKIP_MISSING: $file"; continue; }
  [ ! -L "$file" ] || { echo "SKIP_SYMLINK: $file"; continue; }
  # Redundant ONLY if an intact byte-identical latest dated backup is retained.
  if cmp -s "$file" router-diag.sh.bak.20260929-234327; then
    # Do not remove backups with explicit external hooks.
    if grep -F -q "$file" /etc/crontabs/root /etc/rc.local 2>/dev/null; then
      echo "SKIP_REFERENCED: $file"
    else
      rm -f "$file"
      echo "DELETED_IDENTICAL_DATED_BACKUP: $file"
      deleted=$((deleted + 1))
    fi
  else
    echo "PRESERVED_CONTENT_DIFFERS: $file"
  fi
done
echo "DELETED_COUNT=$deleted"
echo 'CLEANUP_SCOPE=ONLY_TWO_EXACT_DATED_ROUTER_DIAG_BACKUPS'
