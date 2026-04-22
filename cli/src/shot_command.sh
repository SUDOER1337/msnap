if pgrep -x "slurp" >/dev/null || pgrep -x "wayfreeze" >/dev/null; then
  echo "Screenshot selection already in progress." >&2
  exit 0
fi

if [[ ${args[--only-copy]} ]]; then
  filepath="$(mktemp -t msnap-XXXXXX.png)"
  # Clean up old temp files synchronously to avoid race conditions
  find "$(dirname "$filepath")" -maxdepth 1 -name "msnap-*.png" -mmin +5 -delete 2>/dev/null || true
else
  output_dir="${args[--output]:-${ini[shot_output_dir]:-${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots}}"
  filename_pattern="${args[--filename]:-${ini[shot_filename_pattern]:-%Y%m%d%H%M%S.png}}"
  filename="$(date +"$filename_pattern")"
  filepath="$output_dir/$filename"
  mkdir -p "$output_dir"
fi

cmd=(grim)

use_pointer=""
{ [[ ${ini[shot_pointer_default]} == true ]] || [[ ${args[--pointer]} ]]; } && use_pointer=true
[[ $use_pointer ]] && cmd+=(-c)

if [[ ${args[--window]} ]]; then
  if ! command -v mmsg >/dev/null 2>&1; then
    echo "missing dependency: mmsg (required for --window)" >&2
    exit 1
  fi
  geometry=$(mmsg -x | awk '/x / {x=$3} /y / {y=$3} /width / {w=$3} /height / {h=$3} END {print x","y" "w"x"h}')
  if [[ -z "$geometry" ]]; then
    echo "Error: No active window found or mmsg failed." >&2
    exit 1
  fi
  cmd+=(-g "$geometry")
elif [[ ${args[--geometry]} ]]; then
  cmd+=(-g "${args[--geometry]}")
fi

if [[ ${args[--freeze]} ]]; then
  if ! command -v wayfreeze >/dev/null 2>&1; then
    echo "missing dependency: wayfreeze (required for --freeze)" >&2
    exit 1
  fi
  wayfreeze_cmd=(wayfreeze)
  [[ -z $use_pointer ]] && wayfreeze_cmd+=(--hide-cursor)
  pipe=$(mktemp -u).fifo
  mkfifo "$pipe"
  wayfreeze_pid=""
  cleanup_wayfreeze() {
    [[ -n "$wayfreeze_pid" ]] && kill "$wayfreeze_pid" 2>/dev/null || true
    rm -f "$pipe"
  }
  trap cleanup_wayfreeze EXIT
  
  if [[ ${args[--region]} ]]; then
    "${wayfreeze_cmd[@]}" --after-freeze-timeout 100 --after-freeze-cmd "echo > $pipe" &
    wayfreeze_pid=$!
    # Add 10 second timeout to prevent indefinite blocking if wayfreeze hangs
    if ! read -t 10 -r < "$pipe"; then
      echo "Error: wayfreeze timeout" >&2
      kill "$wayfreeze_pid" 2>/dev/null || true
      rm -f "$pipe"
      trap - EXIT
      exit 1
    fi
    geometry=$(slurp -d)
    if [[ -z "$geometry" ]]; then
      kill "$wayfreeze_pid" 2>/dev/null || true
      rm -f "$pipe"
      trap - EXIT
      exit 1
    fi
    "${cmd[@]}" -g "$geometry" "$filepath"
  else
    "${wayfreeze_cmd[@]}" --after-freeze-timeout 100 --after-freeze-cmd "echo > $pipe" &
    wayfreeze_pid=$!
    # Add 10 second timeout to prevent indefinite blocking if wayfreeze hangs
    if ! read -t 10 -r < "$pipe"; then
      echo "Error: wayfreeze timeout" >&2
      kill "$wayfreeze_pid" 2>/dev/null || true
      rm -f "$pipe"
      trap - EXIT
      exit 1
    fi
    "${cmd[@]}" "$filepath"
  fi
  trap - EXIT
  kill "$wayfreeze_pid" 2>/dev/null || true
  rm -f "$pipe"
elif [[ ${args[--region]} ]]; then
  geometry=$(slurp -d)
  [[ -z "$geometry" ]] && exit 1
  "${cmd[@]}" -g "$geometry" "$filepath"
else
  "${cmd[@]}" "$filepath"
fi

if [[ ${args[--annotate]} ]]; then
  satty --filename "$filepath" --output-filename "$filepath" \
    --actions-on-enter save-to-file --early-exit --disable-notifications
fi

if [[ ${args[--only-copy]} ]]; then
  wl-copy < "$filepath"
  notify-send "Screenshot captured" "Image copied to the clipboard." \
    -i "$filepath" -a msnap
else
  if [[ ! ${args[--no-copy]} ]]; then
    wl-copy < "$filepath"
    message="Image saved in <i>${filepath}</i> and copied to the clipboard."
  else
    message="Image saved in <i>${filepath}</i>."
  fi
  notify_saved "$filepath" "$message" "shot"
fi
