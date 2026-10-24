#!/usr/bin/env bash
# Export the project for the web (WebXR) into build/web/, and optionally serve it.
#
# Usage:
#   ./build-web.sh [options]
#
# Options:
#   --no-export   skip the Godot export and use the existing build/web/
#   --serve       serve build/web/ at http://localhost:PORT (default 8000)
#   --quest       with --serve, also forward the port to a USB-connected Quest
#                 (adb reverse) so its browser can open http://localhost:PORT
#   --port N      port for --serve
#
# Browsers only allow WebXR on HTTPS pages or on localhost. --quest uses
# localhost on the headset, so no certificate is needed. To use it from another
# device, host build/web/ on any HTTPS static host. The export is
# single-threaded, so it needs no special (COOP/COEP) headers.
set -euo pipefail

EXPORT=1
SERVE=0
QUEST=0
PORT=8000

while [[ $# -gt 0 ]]; do
	case "$1" in
		--no-export) EXPORT=0 ;;
		--serve) SERVE=1 ;;
		--quest) QUEST=1 ;;
		--port) PORT="$2"; shift ;;
		*) echo "Unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

cd "$(dirname "$0")"

if [[ "$EXPORT" == 1 ]]; then
	mkdir -p build/web
	godot --headless --import
	godot --headless --export-release "Web" build/web/index.html
	echo "Exported to build/web/"
fi

if [[ "$SERVE" == 0 ]]; then
	exit 0
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
	echo "Port $PORT is already in use (an earlier server still running?):" >&2
	lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | grep -v WARNING >&2 || true
	echo "Stop it, or pick another port with --port N." >&2
	exit 1
fi

if [[ "$QUEST" == 1 ]]; then
	ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
	[[ -x "$ADB" ]] || ADB=adb
	# Godot shuts adb down when it exits (editor setting "Shutdown ADB on Exit"),
	# so after an export the headset takes a few seconds to reconnect.
	"$ADB" start-server >/dev/null 2>&1 || true
	state=""
	for _ in $(seq 20); do
		state="$("$ADB" get-state 2>/dev/null || true)"
		[[ "$state" == device ]] && break
		sleep 0.5
	done
	if [[ "$state" != device ]]; then
		echo "No Quest ready over USB. Connected devices:" >&2
		"$ADB" devices >&2 || true
		if "$ADB" devices | grep -q unauthorized; then
			echo "Put the headset on and accept 'Allow USB debugging' (tick 'Always allow'), then run this again." >&2
		fi
		exit 1
	fi
	"$ADB" reverse "tcp:$PORT" "tcp:$PORT"
	echo "On the Quest, open http://localhost:$PORT in the browser"
fi

echo "Serving build/web/ at http://localhost:$PORT (Ctrl+C to stop)"
exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory build/web
