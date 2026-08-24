#!/usr/bin/env bash
# Tweak the app's layout numbers without rebuilding.
#
# Values live in UserDefaults and are read when the Preferences window is shown, so
# after setting one: close Preferences (Cmd-W) and reopen it (Cmd-,).
set -euo pipefail
DOMAIN=com.dvir.dictato
KEYS=(sidebarWidth sidebarInset sidebarCorner brandTop brandBottom brandLeading
      contentPadding cardSpacing cardPadding cardCorner
      trafficLightX trafficLightTop trafficLightPitch)

usage() {
    cat <<USAGE
usage: Tools/ui-tune.sh <command>

  list                 show every key, its current override and the shipped default
  set <key> <number>   override a key, then reopen Preferences (Cmd-W, Cmd-,)
  reset [key]          drop one override, or all of them when no key is given
  baked                print the overrides in a form worth pasting back into the code

keys: ${KEYS[*]}
USAGE
}

defaults_for() { grep -A1 "\"$1\"" Sources/Dictato/UITuning.swift | grep -o '[0-9]\+)' | head -1 | tr -d ')'; }

case "${1:-}" in
list)
    printf '%-20s %-10s %s\n' KEY CURRENT DEFAULT
    for k in "${KEYS[@]}"; do
        cur=$(defaults read "$DOMAIN" "$k" 2>/dev/null || echo "-")
        def=$(grep -o "(\"$k\", [0-9]*)" Sources/Dictato/UITuning.swift | grep -o '[0-9]*)' | tr -d ')')
        printf '%-20s %-10s %s\n' "$k" "$cur" "${def:-?}"
    done
    ;;
set)
    [ $# -eq 3 ] || { usage; exit 1; }
    defaults write "$DOMAIN" "$2" -int "$3"
    echo "$2 = $3 — now close Preferences (Cmd-W) and reopen it (Cmd-,)"
    ;;
reset)
    if [ $# -eq 2 ]; then
        defaults delete "$DOMAIN" "$2" 2>/dev/null || true
        echo "$2 back to its shipped value"
    else
        for k in "${KEYS[@]}"; do defaults delete "$DOMAIN" "$k" 2>/dev/null || true; done
        echo "all overrides cleared"
    fi
    echo "close Preferences (Cmd-W) and reopen it (Cmd-,)"
    ;;
baked)
    echo "Overrides to bake into UITuning.swift:"
    for k in "${KEYS[@]}"; do
        cur=$(defaults read "$DOMAIN" "$k" 2>/dev/null || true)
        [ -n "${cur:-}" ] && echo "  $k = $cur"
    done
    ;;
*)
    usage; exit 1
    ;;
esac
