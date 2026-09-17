#!/bin/zsh
set -u

human_du() {
  local target="$1"
  if [[ -e "$target" ]]; then
    du -xhd 1 "$target" 2>/dev/null | sort -h | tail -n 25
  fi
}

print '== Data volume =='
df -h /System/Volumes/Data

print '\n== Time Machine local snapshots =='
tmutil listlocalsnapshots / 2>/dev/null || true

print '\n== User Library summary =='
for target in \
  "$HOME/Library/Caches" \
  "$HOME/Library/Logs" \
  "$HOME/Library/Application Support" \
  "$HOME/Library/Containers" \
  "$HOME/Library/Group Containers" \
  "$HOME/Library/Developer" \
  "$HOME/.cache" \
  "$HOME/.npm"; do
  [[ -e "$target" ]] && du -sh "$target" 2>/dev/null
done

print '\n== Largest user caches =='
human_du "$HOME/Library/Caches"

print '\n== Largest Application Support entries =='
human_du "$HOME/Library/Application Support"

print '\n== Largest application containers =='
human_du "$HOME/Library/Containers"

print '\n== Temporary and system support areas =='
for target in /private/var/folders /private/var/vm /private/var/db /Library/Updates /Library/Developer /Library/Caches; do
  [[ -e "$target" ]] && du -sh "$target" 2>/dev/null
done

print '\nRead-only audit complete. Classify findings before proposing cleanup.'
