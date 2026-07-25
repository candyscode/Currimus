#!/bin/bash
#
# UI-snapshot regression harness for Currimus.
#
# Drives the app through its DEBUG screenshot routes on a pinned simulator,
# captures a screenshot of every screen, and (in verify mode) diffs each one
# against a committed reference image. It is the codified form of the
# screenshot workflow the app was already built for — the DEBUG routing in
# CurrimusApp/WatchApp exists precisely so every screen can be reached
# deterministically from a launch argument.
#
# Why full-device screenshots rather than view snapshots: the design leans on
# Liquid Glass, .ultraThinMaterial, the native Liquid-Glass tab bar, native
# wheel pickers and MapKit — none of which an in-process ImageRenderer captures
# faithfully. Only a real screenshot shows what the user sees, which is exactly
# what a UI regression test has to guard.
#
# Usage:
#   scripts/ui-snapshot.sh verify [ios|watch|all]   # compare vs references (default)
#   scripts/ui-snapshot.sh record [ios|watch|all]   # (re)write references
#   scripts/ui-snapshot.sh verify all --no-build    # skip the xcodebuild step
#
# Environment overrides:
#   IOS_SIM   (default "iPhone 17 Pro")
#   WATCH_SIM (default "Apple Watch Ultra 3 (49mm)")
#
# No `set -u`: macOS still ships bash 3.2, where expanding an empty indexed
# array under -u raises "unbound variable". pipefail is enough here.
set -o pipefail

# ---------------------------------------------------------------- configuration
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UISNAP="$ROOT/scripts/uisnap"
REF_DIR="$ROOT/Tests/UISnapshots/reference"
WORK_DIR="$ROOT/Tests/UISnapshots/_work"

IOS_SIM="${IOS_SIM:-iPhone 17 Pro}"
WATCH_SIM="${WATCH_SIM:-Apple Watch Ultra 3 (49mm)}"
IOS_BID="com.currimus.app"
WATCH_BID="com.currimus.app.watchkitapp"

# Per-tier diff budgets (bash 3.2 has no associative arrays, so: functions):
#   TOLERANCE = max per-channel delta (0-255) before a pixel counts as changed
#   FRACTION  = share of considered pixels allowed to change (0-1)
tol_for()  { case "$1" in strict) echo 12;;  medium) echo 16;;   loose) echo 18;;   *) echo 12;;    esac; }
frac_for() { case "$1" in strict) echo 0.0020;; medium) echo 0.015;; loose) echo 0.035;; *) echo 0.0020;; esac; }

# The watch system clock + pairing glyph live in the top-right corner; mask them
# out of every watch comparison (x y w h, as fractions of the image).
WATCH_CLOCK_MASK="ignore 0.62 0.0 0.38 0.15"

# Per-route masks (x y w h fractions), for regions that can never match pixel
# for pixel. The road-run detail embeds a live MapKit map whose tiles render
# differently every run, so pixel-comparing it is a guaranteed false failure —
# mask the map card out and let the rest of the screen still be checked.
route_mask() {
  case "$1" in
    detail-road) echo "ignore 0.0 0.43 1.0 0.23" ;;
    *) : ;;
  esac
}

RENDER_WAIT=2.4   # seconds after launch before the screenshot

# ---------------------------------------------------------------- args
MODE="${1:-verify}"; [ $# -ge 1 ] && shift || true
TARGET="all"; NO_BUILD=0
for a in "$@"; do
  case "$a" in
    ios|watch|all) TARGET="$a" ;;
    --no-build) NO_BUILD=1 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done
case "$MODE" in record|verify) ;; *) echo "mode must be record or verify" >&2; exit 2 ;; esac

# ---------------------------------------------------------------- helpers
say() { printf '\033[1m%s\033[0m\n' "$*"; }
udid_for() { xcrun simctl list devices available | grep -F "$1 (" | head -1 | grep -oE '[0-9A-F-]{36}'; }

boot() {   # boot the sim if it isn't already, and wait until it's ready
  local udid="$1"
  local state
  state=$(xcrun simctl list devices | grep -F "$udid" | grep -oE '\((Booted|Shutdown)\)' | tr -d '()')
  if [ "$state" != "Booted" ]; then xcrun simctl boot "$udid" >/dev/null 2>&1; fi
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
}

# Compile the comparator once per run into the work dir (never committed).
COMPARE_BIN="$WORK_DIR/compare"
build_comparator() {
  mkdir -p "$WORK_DIR"
  if ! swiftc -O "$UISNAP/compare.swift" -o "$COMPARE_BIN" 2>"$WORK_DIR/compare-build.log"; then
    echo "failed to compile comparator:" >&2; cat "$WORK_DIR/compare-build.log" >&2; exit 2
  fi
}

FAILS=0; PASSES=0; FAILED_NAMES=()

# capture <udid> <bid> <name> <args...>  → screenshot into $CAND
capture() {
  local udid="$1" bid="$2" name="$3"; shift 3
  xcrun simctl terminate "$udid" "$bid" >/dev/null 2>&1
  xcrun simctl launch "$udid" "$bid" "$@" >/dev/null 2>&1
  sleep "$RENDER_WAIT"
  xcrun simctl io "$udid" screenshot "$CAND/$name.png" >/dev/null 2>&1
}

# run_platform <ios|watch> <udid> <bid> <routes-file> <extra-mask...>
run_platform() {
  local plat="$1" udid="$2" bid="$3" routes="$4"; shift 4
  local mask=("$@")
  local ref="$REF_DIR/$plat"
  CAND="$WORK_DIR/candidate/$plat"
  local diff="$WORK_DIR/diff/$plat"
  mkdir -p "$ref" "$CAND" "$diff"

  while IFS='|' read -r rawname rawtier rawargs; do
    # skip blanks / comments
    [ -z "${rawname// }" ] && continue
    case "$rawname" in \#*) continue ;; esac
    local name tier
    name="$(echo "$rawname" | xargs)"
    tier="$(echo "$rawtier" | xargs)"
    # shellcheck disable=SC2206
    local args=( $rawargs )   # intentional word-split into launch tokens

    capture "$udid" "$bid" "$name" "${args[@]}"

    if [ "$MODE" = record ]; then
      cp "$CAND/$name.png" "$ref/$name.png"
      printf '  rec  %-18s %s\n' "$name" "$tier"
      continue
    fi

    # verify
    if [ ! -f "$ref/$name.png" ]; then
      printf '  \033[33mMISS\033[0m %-18s no reference — run: record\n' "$name"
      FAILS=$((FAILS+1)); FAILED_NAMES+=("$plat/$name (no reference)"); continue
    fi
    # shellcheck disable=SC2206
    local rmask=( $(route_mask "$name") )   # extra per-route ignore rects, if any
    local out
    out=$("$COMPARE_BIN" "$ref/$name.png" "$CAND/$name.png" "$diff/$name.png" \
          "$(tol_for "$tier")" "$(frac_for "$tier")" "${mask[@]}" "${rmask[@]}" 2>&1)
    if [ $? -eq 0 ]; then
      printf '  \033[32mok\033[0m   %-18s %s\n' "$name" "$out"
      PASSES=$((PASSES+1))
    else
      printf '  \033[31mFAIL\033[0m %-18s %s\n' "$name" "$out"
      FAILS=$((FAILS+1)); FAILED_NAMES+=("$plat/$name")
    fi
  done < "$routes"
}

# ---------------------------------------------------------------- build
build_if_needed() {
  [ "$NO_BUILD" = 1 ] && return 0
  if [ "$TARGET" = ios ] || [ "$TARGET" = all ]; then
    say "Building Currimus (iOS, Debug)…"
    xcodebuild -project "$ROOT/Currimus.xcodeproj" -scheme Currimus -configuration Debug \
      -destination "platform=iOS Simulator,name=$IOS_SIM" -derivedDataPath "$ROOT/build" \
      build >/dev/null 2>&1 || { echo "iOS build failed" >&2; exit 2; }
  fi
  if [ "$TARGET" = watch ] || [ "$TARGET" = all ]; then
    say "Building CurrimusWatch (watchOS, Debug)…"
    xcodebuild -project "$ROOT/Currimus.xcodeproj" -scheme CurrimusWatch -configuration Debug \
      -destination "platform=watchOS Simulator,name=$WATCH_SIM" -derivedDataPath "$ROOT/build" \
      build >/dev/null 2>&1 || { echo "watch build failed" >&2; exit 2; }
  fi
}

# ---------------------------------------------------------------- run
say "UI snapshots · mode=$MODE · target=$TARGET"
build_comparator
build_if_needed

if [ "$TARGET" = ios ] || [ "$TARGET" = all ]; then
  UDID=$(udid_for "$IOS_SIM"); [ -z "$UDID" ] && { echo "no simulator named '$IOS_SIM'" >&2; exit 2; }
  say "iOS · $IOS_SIM"
  boot "$UDID"
  APP=$(find "$ROOT/build/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "Currimus.app" | head -1)
  [ -n "$APP" ] && xcrun simctl install "$UDID" "$APP" >/dev/null 2>&1
  # Pin the status bar so the clock/battery never move under the comparison.
  xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged \
    --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName " " >/dev/null 2>&1
  run_platform ios "$UDID" "$IOS_BID" "$UISNAP/ios-routes.txt"
fi

if [ "$TARGET" = watch ] || [ "$TARGET" = all ]; then
  UDID=$(udid_for "$WATCH_SIM"); [ -z "$UDID" ] && { echo "no simulator named '$WATCH_SIM'" >&2; exit 2; }
  say "watchOS · $WATCH_SIM"
  boot "$UDID"
  APP=$(find "$ROOT/build/Build/Products/Debug-watchsimulator" -maxdepth 1 -name "CurrimusWatch.app" | head -1)
  [ -n "$APP" ] && xcrun simctl install "$UDID" "$APP" >/dev/null 2>&1
  run_platform watch "$UDID" "$WATCH_BID" "$UISNAP/watch-routes.txt" $WATCH_CLOCK_MASK
fi

# ---------------------------------------------------------------- summary
echo
if [ "$MODE" = record ]; then
  say "Recorded references into Tests/UISnapshots/reference/"
  exit 0
fi
if [ "$FAILS" -eq 0 ]; then
  say "✓ all $PASSES snapshots match"
  exit 0
else
  say "✗ $FAILS changed, $PASSES matched"
  printf '   %s\n' "${FAILED_NAMES[@]}"
  echo "   diffs: Tests/UISnapshots/_work/diff/  (magenta = changed, blue = masked)"
  exit 1
fi
