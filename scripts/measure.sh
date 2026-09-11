#!/bin/bash
# Sums physical footprint of an app and its WebKit/Chromium helper processes.
sum() { # $1 = label, $2 = grep pattern for the executable path
  ps -Ao pid=,rss=,comm= | grep -E "$2" | awk -v l="$1" '{s+=$2; n++} END {printf "%-22s %6.0f MB  (%d processes)\n", l, s/1024, n}'
}
sum "Electron Mattermost" "/Applications/Mattermost.app/"
# WebKit content processes are launched by launchd; attribute them by responsible pid.
if pgrep -xq MatterMemory; then
  ps -Ao pid=,rss=,comm= | grep -E "MatterMemory.app/|com.apple.WebKit" | awk 'BEGIN{s=0} {s+=$2; n++} END {printf "%-22s %6.0f MB  (%d processes, incl. any other WebKit apps)\n", "MatterMemory (ps)", s/1024, n}'
  echo "Exact per-app figure: see the readout in MatterMemory's top bar (uses responsible-process attribution)."
else
  echo "MatterMemory is not running."
fi
