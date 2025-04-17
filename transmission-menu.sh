#!/usr/bin/bash

get_status_name() {
  status_code="$1"
  case "$status_code" in
    0) echo "Stopped";;
    1) echo "Check queue";;
    2) echo "Checking";;
    3) echo "Download Queue";;
    4) echo "Downloading";;
    5) echo "Seed Queue";;
    6) echo "Seeding";;
  esac
}

display_detail() {
  torrent_id="$1"

  raw_detail=$(
    transmission-remote -j -t"$torrent_id" -l \
    | jq ".arguments.torrents.[]"
  )

  raw_status=$(jq -r ".status" <<< "$raw_detail")
  raw_eta=$(jq -r ".eta" <<< "$raw_detail")
  raw_speed=$(jq -r ".rateDownload" <<< "$raw_detail")
  raw_size_left=$(jq -r ".leftUntilDone" <<< "$raw_detail")
  raw_size=$(jq -r ".sizeWhenDone" <<< "$raw_detail")

  # avoid division by 0
  raw_size_or_one=$( [[ "$raw_size" -eq 0 ]] && echo 1 || echo "$raw_size" )

  downloaded=$(( raw_size - raw_size_left ))
  percentage=$(( downloaded * 100 / raw_size_or_one ))

  status=$(get_status_name "$raw_status")

  eta=$( [[ "$raw_eta" -lt 0 ]] && echo "N/A" || echo "${raw_eta}s" )

  size=$(numfmt --to=iec --suffix=B "$raw_size")
  downloaded=$(numfmt --to=iec --suffix=B "$downloaded")
  speed=$(numfmt --to=iec --suffix=B "$raw_speed")

  processed="${status} ${downloaded}/${size} (${percentage}%) at ${speed}/s ETA: ${eta}"
  rofi -dmenu -i -p "Detail" <<< "$processed"
}

map_name_to_tid() {
  torrents=$(transmission-remote -j -l | jq -c ".arguments.torrents")
  [[ -z "$torrents" ]] && return

  declare -A name_to_tid

  # Map name: id
  while IFS= read -r torrent; do
    name=$(jq -r ".name" <<< "$torrent")
    tid=$(jq -r ".id" <<< "$torrent")
    name_to_tid["$name"]="$tid"
  done < <(jq -c ".[]" <<< "$torrents")

  # Make a string out of the HASHMAP
  serialized=$(declare -p name_to_tid)
  echo "$serialized"
}

control_torrent() {
  torrent_id="$1"
  controls=( "Remove" "Stop" "Resume" "Kill daemon" )

  selected_control=$(printf '%s\n' "${controls[@]}" | rofi -dmenu -i -p "Controls")
  [[ -z "$selected_control" ]] && return

  case "$selected_control" in
    "Remove")
      transmission-remote -t "$torrent_id" -r
      # Kill daemon if it was the last running download
      torrents=$(transmission-remote -j -l | jq -c ".arguments.torrents")
      [[ -z "$torrents" ]] && killall transmission-daemon
      ;;
    "Stop") transmission-remote -t "$torrent_id" -S;;
    "Resume") transmission-remote -t "$torrent_id" -s;;
    "Kill daemon") killall transmission-daemon;;
  esac
}
