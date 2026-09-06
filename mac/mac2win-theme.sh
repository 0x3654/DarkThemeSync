#!/bin/bash
# Синхронизация темы Windows (VM Parallels) с темой macOS.
# Следит за AppleInterfaceStyle; при смене пишет флаг в VM и запускает задачу MacThemeSync.
PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
VM="${VM_NAME:-Windows 11}"
LAST=""
while true; do
  if defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then MODE=dark; else MODE=light; fi
  if [ "$MODE" != "$LAST" ]; then
    if prlctl exec "$VM" powershell -NoProfile -Command "Set-Content C:\Users\Public\mac_theme.txt '$MODE'; schtasks /Run /TN MacThemeSync" >/dev/null 2>&1; then
      LAST="$MODE"
      echo "$(date '+%H:%M:%S') theme -> $MODE"
    else
      sleep 15   # VM выключена/спит — подождём подольше
    fi
  fi
  sleep 1
done
