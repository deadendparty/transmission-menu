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
get_downloads() {
  raw_downloads="transmission-remote -l"

  # Removes the header and footer
  downloads=$(eval $raw_downloads | awk 'NR > 2 {print payload} {payload=$0}')

  # Return if there's no downloads
  if [ -z "$downloads" ]; then return; fi

  # Get the average percentage of all downloads
  percentages=$(echo "$downloads" | awk -F'\\s\\s+' '{printf "%.3s\n", $3}')
  done=$(echo -e "$percentages" | awk '{ mean += $1 } END { printf "%.0f\n", mean/NR }')

  # Get the average ratio from all downloads
  ratios=$(echo "$downloads" | awk -F'\\s\\s+' '{ print  $8}')
  ratio=$(echo -e "$ratios" | awk '{ mean += $1 } END { printf "%.2f\n", mean/NR }')

  # Get fields (related to all downloads) from the footer
  have=$(eval "$raw_downloads" | awk -F'\\s\\s+' '{ field = $2 } END { print field }')
  up=$(eval "$raw_downloads" | awk -F'\\s\\s+' '{ field = $3 } END { print field }')
  down=$(eval "$raw_downloads" | awk -F'\\s\\s+' '{ field = $4 } END { print field }')

  # Echo the downloads with the extra option
  all_option="    all   ${done}%   ${have}  N/A         ${up}     ${down}   ${ratio}  N/A      all"
  echo "$all_option" $'\n' "$downloads"
}


list_download_titles() {
  # Downloads argument
  downloads="$1"

  # Exit if there's no downloads
  if [ -z "$downloads" ]; then exit; fi

  # Extract the downloads' title
  titles=$(echo "$downloads" | awk -F'\\s\\s+' '{print $10}')

  # List the titles (Select to proceed, return otherwise)
  selected_title=$(echo "$titles"| rofi -dmenu -i -p "Title") || return

  # Return the download of the selected title
  echo "$downloads" | grep -F "$selected_title"
}


get_download_details() {
  # Selected download argument
  selected_download="$1"

  # Exit if there's no selected download
  if [ -z "$selected_download" ]; then exit; fi

  # Extract the downloads' details
  status=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $9}')
  done=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $3}')
  have=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $4}')
  eta=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $5}')
  up=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $6}')
  down=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $7}')
  ratio=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $8}')

  # Format the downloads' details
  details=(
    "Status: ${status}"
    "Done: ${done}"
    "Have: ${have}"
    "ETA: ${eta}"
    "Up: ${up}"
    "Down: ${down}"
    "Ratio: ${ratio}"
  )

  # List the details (exit if nothing's been selected)
  printf '%s\n' "${details[@]}" | rofi -dmenu -i -p "Details" > /dev/null || exit
}


control_download() {
  # Selected download argument
  selected_download="$1"

  # Grep its id (number or all)
  download_id=$(echo "$selected_download" | awk -F'\\s\\s+' '{print $2}' | grep -Po "(\d+|all)")

  # Control options
  controls=( "Remove" "Stop" "Resume" "Kill daemon" )

  # List the control (select to perform an action, exit otherwise)
  selected_control=$(printf '%s\n' "${controls[@]}" | rofi -dmenu -i -p "Controls") || exit

  # Perform action
  case $selected_control in
    Remove) 
      transmission-remote -t $download_id -r

      # Kill daemon if there's no downloads
      downloads=$(get_downloads)
      if [ -z "$downloads" ]; then
        killall transmission-daemon
      fi
      ;;
    Stop) transmission-remote -t $download_id -S;;
    Resume) transmission-remote -t $download_id -s;;
    "Kill daemon") killall transmission-daemon;;
  esac
}


downloads=$(get_downloads)
selected_download=$(list_download_titles "$downloads")
get_download_details "$selected_download"
control_download "$selected_download"
