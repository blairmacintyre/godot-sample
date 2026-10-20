#!/usr/bin/env bash
# Export the project for Linux ARM64, copy it to the Steam Frame over SSH, and
# (re)start it there as a user service named "frame-cube".
#
# Usage:
#   ./deploy.sh [options] [host]
#
# Options:
#   --no-export   skip the Godot export and deploy the existing build/
#   --stop        stop the app on the Frame and exit
#   --restart     restart the app without exporting or copying
#
# The default host is the Frame's USB network address. SSH connections are
# shared (ControlMaster), so you enter the steamos password at most once per 2 hours.
set -euo pipefail

EXPORT=1
COPY=1
ACTION=deploy
HOST=10.86.200.233

for arg in "$@"; do
	case "$arg" in
		--no-export) EXPORT=0 ;;
		--stop) ACTION=stop ;;
		--restart) ACTION=restart; EXPORT=0; COPY=0 ;;
		-*) echo "Unknown option: $arg" >&2; exit 2 ;;
		*) HOST="$arg" ;;
	esac
done

REMOTE="steamos@$HOST"
UNIT=frame-cube
REMOTE_DIR='$HOME/frame-cube'
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/frame.sock" -o ControlPersist=2h)

cd "$(dirname "$0")"

remote() { ssh "${SSH_OPTS[@]}" "$REMOTE" "$@"; }

stop_app() {
	remote "systemctl --user stop $UNIT 2>/dev/null; systemctl --user reset-failed $UNIT 2>/dev/null; true"
}

start_app() {
	remote "systemd-run --user --unit=$UNIT \
		--working-directory=$REMOTE_DIR \
		--setenv=XDG_RUNTIME_DIR=/run/user/\$(id -u) \
		--setenv=DISPLAY=:0 \
		$REMOTE_DIR/frame-cube.arm64 --xr-mode on"
}

if [[ "$ACTION" == stop ]]; then
	stop_app
	echo "Stopped $UNIT on $HOST"
	exit 0
fi

if [[ "$EXPORT" == 1 ]]; then
	mkdir -p build
	godot --headless --import
	godot --headless --export-release "Steam Frame Arm64" build/frame-cube.arm64
fi

# Stop first so the binary isn't busy while it is overwritten.
stop_app

if [[ "$COPY" == 1 ]]; then
	remote "mkdir -p $REMOTE_DIR"
	scp "${SSH_OPTS[@]}" build/frame-cube.arm64 build/frame-cube.pck "$REMOTE:frame-cube/"
	remote "chmod +x $REMOTE_DIR/frame-cube.arm64"
fi

start_app
sleep 3
if remote "systemctl --user is-active --quiet $UNIT"; then
	echo "Running on $HOST. Logs: ssh $REMOTE journalctl --user -u $UNIT -f"
else
	echo "App failed to start. Recent log:" >&2
	remote "journalctl --user -u $UNIT --no-pager -n 20" >&2
	exit 1
fi
