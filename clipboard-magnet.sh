#!/usr/bin/bash

start_magnet() {
  magnet="$1"

  transmission-daemon
  # Might take a while due to the daemons' lazyness
  until transmission-remote -a "$magnet" -s > /dev/null 2>&1; do
    sleep 0.25;
  done
}

clipboard=$(xclip -o -selection clipboard 2> /dev/null)
[[ "$clipboard" == "magnet:?"* ]] && start_magnet "$clipboard"
