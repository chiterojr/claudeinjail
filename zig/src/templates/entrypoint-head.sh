#!/bin/bash
set -e

if [ "$TAILSCALE_ENABLED" = "true" ]; then
  TS_LOG="/dev/null"
  [ "$TS_VERBOSE" = "true" ] && TS_LOG="/tmp/tailscaled.log"
  echo "Starting Tailscale daemon..."
  tailscaled --state=/var/lib/tailscale/tailscaled.state >"$TS_LOG" 2>&1 &
  TAILSCALED_PID=$!

  # Wait for tailscaled socket (up to 15 seconds)
  for i in $(seq 1 30); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 0.5
  done

  if [ ! -S /var/run/tailscale/tailscaled.sock ]; then
    echo "Error: tailscaled failed to start."
    [ -f "$TS_LOG" ] && cat "$TS_LOG"
    [ "$TS_LOG" = "/dev/null" ] && echo "Retry with --verbose for details."
    exit 1
  fi

  # Build tailscale up args
  TS_ARGS="--accept-routes --authkey=$TS_AUTHKEY --hostname=$TS_HOSTNAME"
  [ -n "$TS_EXIT_NODE" ] && TS_ARGS="$TS_ARGS --exit-node=$TS_EXIT_NODE --exit-node-allow-lan-access"

  echo "Connecting to Tailscale network..."
  tailscale up $TS_ARGS

  if ! tailscale status >/dev/null 2>&1; then
    echo "Error: Tailscale failed to connect."
    [ -f "$TS_LOG" ] && cat "$TS_LOG"
    [ "$TS_LOG" = "/dev/null" ] && echo "Retry with --verbose for details."
    kill $TAILSCALED_PID 2>/dev/null
    exit 1
  fi

  echo "Tailscale connected as $(tailscale ip -4 2>/dev/null || echo 'unknown')."
  echo ""
fi

