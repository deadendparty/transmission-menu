#!/usr/bin/bash


display_detail() {
  local torrent_id="$1"
  local -n status_code_to_name="$2"  # Reference to $2

  local raw_detail
  raw_detail=$(
    transmission-remote -j -t"$torrent_id" -l |
      jq ".arguments.torrents.[]"
  )

  local status_code raw_eta raw_speed raw_size_left raw_size
  status_code=$(jq -r ".status" <<< "$raw_detail")
  raw_eta=$(jq -r ".eta" <<< "$raw_detail")
  raw_speed=$(jq -r ".rateDownload" <<< "$raw_detail")
  raw_size_left=$(jq -r ".leftUntilDone" <<< "$raw_detail")
  raw_size=$(jq -r ".sizeWhenDone" <<< "$raw_detail")

  # Processing
  local raw_size_or_one raw_downloaded percentage status eta
  raw_size_or_one=$( [[ "$raw_size" -eq 0 ]] && echo 1 || echo "$raw_size" )
  raw_downloaded=$(( raw_size - raw_size_left ))
  percentage=$(( raw_downloaded * 100 / raw_size_or_one ))
  status="${status_code_to_name["$status_code"]}"
  eta=$( [[ "$raw_eta" -lt 0 ]] && echo "N/A" || echo "${raw_eta}s" )

  local downloaded size speed
  downloaded=$(numfmt --to=iec --suffix=B "$raw_downloaded")
  size=$(numfmt --to=iec --suffix=B "$raw_size")
  speed=$(numfmt --to=iec --suffix=B "$raw_speed")

  local detail=(
    "$status" "${downloaded}/${size} (${percentage}%)"
    "at ${speed}/s" "ETA: ${eta}"
  )
  printf '%s\n' "${detail[@]}" | rofi -dmenu -i -p "Detail"
}

map_name_to_tid() {
  local torrents
  torrents=$(transmission-remote -j -l | jq -c ".arguments.torrents.[]")
  [[ -z "$torrents" ]] && return

  local torrent name tid
  local -A name_to_tid

  while IFS= read -r torrent; do
    name=$(jq -r ".name" <<< "$torrent")
    tid=$(jq -r ".id" <<< "$torrent")
    name_to_tid["$name"]="$tid"
  done <<< "$torrents"

  # Make a string out of the HASHMAP
  declare -p name_to_tid
}

perform_operation() {
  local torrent_id="$1"

  local operations=( "Remove" "Stop" "Resume" "Kill daemon" )
  local selected
  selected=$(
    printf '%s\n' "${operations[@]}" |
      rofi -dmenu -i -p "Controls"
  )
  [[ -z "$selected" ]] && return

  case "$selected" in
    "Remove")
      transmission-remote -t "$torrent_id" -r
      local torrents
      torrents=$(transmission-remote -j -l | jq -c ".arguments.torrents.[]")
      # Kill daemon if it was the last running download
      [[ -z "$torrents" ]] && killall transmission-daemon
      ;;
    "Stop") transmission-remote -t "$torrent_id" -S;;
    "Resume") transmission-remote -t "$torrent_id" -s;;
    "Kill daemon") killall transmission-daemon;;
  esac
}

load_menus() {
  local name_to_tid
  eval "$(map_name_to_tid)"

  # Display the torrent's names
  names=$(printf '%s\n' "${!name_to_tid[@]}")
  selected_name=$(rofi -dmenu -i -p "Name" <<< "$names")
  [[ -z "$selected_name" ]] && exit

  # Display the torrent's details
  torrent_id="${name_to_tid["$selected_name"]}"
  local -A STATUS_CODE_TO_NAME=(
    [0]="Stopped"
    [1]="Check Queue"
    [2]="Checking"
    [3]="Download Queue"
    [4]="Downloading"
    [5]="Seed Queue"
    [6]="Seeding"
  )
  # ESC - Refresh
  # ENTER - Proceed to control selected torrent
  while [[ -z "$confirmation_detail" ]]; do
    confirmation_detail=$(display_detail "$torrent_id" "STATUS_CODE_TO_NAME")
  done

  # Perform operations on the selected torrent
  perform_operation "$torrent_id"
}

# Ensure the daemon is running
[[ $(pidof transmission-daemon) ]] || exit

load_menus
