#!/usr/bin/env bash
# Export the project for Meta Quest 3 (Android APK) and install it with adb.
#
# Usage:
#   ./deploy-quest.sh [options]
#
# Options:
#   --no-export   skip the Godot export and install the existing APK
#   --no-launch   install only, don't start the app
#   --release     export a release build instead of a debug build
#
# Requirements: JDK 17 (Godot's Java SDK path is set in its editor settings), the
# Android SDK, the Quest in developer mode, and `adb` on PATH. With several
# devices attached, set ANDROID_SERIAL to pick one.
set -euo pipefail

EXPORT=1
LAUNCH=1
MODE=debug
PACKAGE=org.example.framecube
APK=build/frame-cube-quest.apk

# Use the same adb as Godot (the Android SDK's). A different adb version makes the two
# restart each other's server, and the Quest then asks to allow USB debugging again.
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
[[ -x "$ADB" ]] || ADB=adb

for arg in "$@"; do
	case "$arg" in
		--no-export) EXPORT=0 ;;
		--no-launch) LAUNCH=0 ;;
		--release) MODE=release ;;
		*) echo "Unknown option: $arg" >&2; exit 2 ;;
	esac
done

cd "$(dirname "$0")"

if [[ "$EXPORT" == 1 ]]; then
	mkdir -p build
	export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
	godot --headless --import
	godot --headless --export-"$MODE" "Quest 3" "$APK"
fi

[[ -f "$APK" ]] || { echo "No APK at $APK" >&2; exit 1; }

# Godot's export restarts adb, and the Quest then asks to allow USB debugging again
# (tick "Always allow" in that prompt to stop it). Wait for the headset to be
# authorised instead of failing right away.
state=""
for _ in $(seq 1 30); do
	state="$("$ADB" get-state 2>/dev/null || true)"
	[[ "$state" == "device" ]] && break
	[[ -n "$state" || -z "$("$ADB" devices | awk 'NR>1 && NF')" ]] || true
	sleep 2
done
if [[ "$state" != "device" ]]; then
	echo "No authorised Quest found. Plug it in, put on the headset and accept the" >&2
	echo "USB debugging prompt, then check that 'adb devices' lists it as 'device'." >&2
	"$ADB" devices >&2 || true
	exit 1
fi

"$ADB" install -r "$APK"

if [[ "$LAUNCH" == 1 ]]; then
	"$ADB" shell am force-stop "$PACKAGE" || true
	"$ADB" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null
	echo "Launched $PACKAGE. Logs: $ADB logcat -s godot"
fi
