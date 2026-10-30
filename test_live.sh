#!/bin/bash
# test_live.sh — run the skink-mysql live integration test against a
# real MySQL 8 server in a podman container.
#
#   ./test_live.sh                      # start mysql:8.0, run, stop
#   SKINK_MYSQL_DSN=... ./test_live.sh  # against an existing server
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${MYSQL_IMAGE:-docker.io/library/mysql:8.0}"
PORT="${MYSQL_PORT:-13306}"
DSN="${SKINK_MYSQL_DSN:-}"
CONTAINER=""

SKINK_HOME="${SKINK_HOME:-$HOME/.local/skink/std}"
SKINK_BIN="${SKINK:-$(command -v skink || echo "$HOME/.local/skink/bin/skink")}"

cleanup() {
    [ -n "$CONTAINER" ] && podman rm -f "$CONTAINER" >/dev/null 2>&1
    rm -f "$SCRIPT_DIR/.live_test_bin"
}
trap cleanup EXIT

if [ -z "$DSN" ]; then
    if ! command -v podman >/dev/null 2>&1; then
        echo "SKIP: podman not available and SKINK_MYSQL_DSN unset"
        exit 0
    fi
    CONTAINER=$(podman run -d --rm \
        -e MYSQL_ROOT_PASSWORD=rootpw \
        -e MYSQL_ROOT_HOST=% \
        -e MYSQL_USER=skink \
        -e MYSQL_PASSWORD=skinktest \
        -e MYSQL_DATABASE=skinkdb \
        -p "127.0.0.1:$PORT:3306" "$IMAGE")
    echo "started mysql container $CONTAINER on :$PORT"
    # Wait for readiness — mysqladmin ping inside the container.
    for i in $(seq 1 120); do
        if podman exec "$CONTAINER" mysqladmin ping -h 127.0.0.1 -uroot -prootpw >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    sleep 1
    DSN="mysql://skink:skinktest@127.0.0.1:$PORT/skinkdb"
    export SKINK_MYSQL_ROOT_DSN="mysql://root:rootpw@127.0.0.1:$PORT/skinkdb"
fi

SKINK_HOME="$SKINK_HOME" "$SKINK_BIN" -o "$SCRIPT_DIR/.live_test_bin" "$SCRIPT_DIR/live_test.skink" || exit 1
SKINK_MYSQL_DSN="$DSN" "$SCRIPT_DIR/.live_test_bin"
