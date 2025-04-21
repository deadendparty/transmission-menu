#!/usr/bin/bash


display_detail() {
  torrent_id="$1"
  local -n download_status="$2"  # make a reference to DOWNLOAD_STATUS

  raw_detail=$(
    transmission-remote -j -t"$torrent_id" -l \
    | jq ".arguments.torrents.[]"
  )

  status_code=$(jq -r ".status" <<< "$raw_detail")
  raw_eta=$(jq -r ".eta" <<< "$raw_detail")
  raw_speed=$(jq -r ".rateDownload" <<< "$raw_detail")
  raw_size_left=$(jq -r ".leftUntilDone" <<< "$raw_detail")
  raw_size=$(jq -r ".sizeWhenDone" <<< "$raw_detail")

  # avoid division by 0
  raw_size_or_one=$( [[ "$raw_size" -eq 0 ]] && echo 1 || echo "$raw_size" )

  downloaded=$(( raw_size - raw_size_left ))
  percentage=$(( downloaded * 100 / raw_size_or_one ))

  status="${download_status["$status_code"]}"

  eta=$( [[ "$raw_eta" -lt 0 ]] && echo "N/A" || echo "${raw_eta}s" )

  size=$(numfmt --to=iec --suffix=B "$raw_size")
  downloaded=$(numfmt --to=iec --suffix=B "$downloaded")
  speed=$(numfmt --to=iec --suffix=B "$raw_speed")

  processed="${status} ${downloaded}/${size} (${percentage}%) at ${speed}/s ETA: ${eta}"
  rofi -dmenu -i -p "Detail" <<< "$processed"
}

map_name_to_tid() {
  torrents=$(transmission-remote -j -l | jq -c ".arguments.torrents.[]")
  [[ -z "$torrents" ]] && return

  declare -A name_to_tid

  # Map name: id
  while IFS= read -r torrent; do
    name=$(jq -r ".name" <<< "$torrent")
    tid=$(jq -r ".id" <<< "$torrent")
    name_to_tid["$name"]="$tid"
  done <<< "$torrents"

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
      torrents=$(transmission-remote -j -l | jq -c ".arguments.torrents.[]")
      [[ -z "$torrents" ]] && killall transmission-daemon
      ;;
    "Stop") transmission-remote -t "$torrent_id" -S;;
    "Resume") transmission-remote -t "$torrent_id" -s;;
    "Kill daemon") killall transmission-daemon;;
  esac
}

# Ensure the daemon is running
[[ $(pidof transmission-daemon) ]] || exit

serialized_map=$(map_name_to_tid)
eval "$serialized_map"
# name_to_tid HASHMAP is now available

names=$(printf '%s\n' "${!name_to_tid[@]}")  # separated by \n
selected_name=$(rofi -dmenu -i -p "Name" <<< "$names")
[[ -z "$selected_name" ]] && exit

declare -A DOWNLOAD_STATUS=(
  [0]="Stopped"
  [1]="Check Queue"
  [2]="Checking"
  [3]="Download Queue"
  [4]="Downloading"
  [5]="Seed Queue"
  [6]="Seeding"
)

torrent_id="${name_to_tid["$selected_name"]}"

# ESC - Refresh
# ENTER - Proceed to control selected torrent
while [[ -z "$confirmation_detail" ]]; do
  confirmation_detail=$(display_detail "$torrent_id" "DOWNLOAD_STATUS")
done

control_torrent "$torrent_id"
