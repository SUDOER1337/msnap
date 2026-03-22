if pgrep -x "slurp" >/dev/null || pgrep -x "wayfreeze" >/dev/null; then
  echo "Screenshot selection already in progress." >&2
  exit 0
fi

if [[ ${args[--only-copy]} ]]; then
  filepath="$(mktemp -t msnap-XXXXXX.png)"
  find "$(dirname "$filepath")" -maxdepth 1 -name "msnap-*.png" -mmin +5 -delete 2>/dev/null &
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

if [[ ${args[--window]} || ${args[--window-id]} ]]; then
  if [[ ${args[--window-id]} ]]; then
    echo "${args[--window-id]}" > /tmp/xdpw-target-window-id
  else
    rm -f /tmp/xdpw-target-window-id
  fi

  CAPTURE_SCRIPT="${MSNAP_LIB_DIR:-/usr/local/share/msnap}/scripts/capture_window.py"
  if [[ ! -f "$CAPTURE_SCRIPT" ]]; then
    echo "Error: capture_window.py not found at $CAPTURE_SCRIPT" >&2
    exit 1
  fi

  python3 "$CAPTURE_SCRIPT" "$filepath"
  if [[ $? -ne 0 ]]; then
    echo "Error: Window capture failed." >&2
    exit 1
  fi

  captured_via_portal=true
elif [[ ${args[--geometry]} ]]; then
  cmd+=(-g "${args[--geometry]}")
fi

if [[ -z "${captured_via_portal:-}" ]]; then
  if [[ ${args[--freeze]} ]]; then
    if ! command -v wayfreeze >/dev/null 2>&1; then
      echo "missing dependency: wayfreeze (required for --freeze)" >&2
      exit 1
    fi
    wayfreeze_cmd=(wayfreeze)
    [[ -z $use_pointer ]] && wayfreeze_cmd+=(--hide-cursor)
    trap 'kill $wayfreeze_pid 2>/dev/null || true; rm -f "$pipe"' EXIT
    pipe=$(mktemp -u).fifo
    mkfifo "$pipe"
    if [[ ${args[--region]} ]]; then
      "${wayfreeze_cmd[@]}" --after-freeze-timeout 100 --after-freeze-cmd "echo > $pipe" &
      wayfreeze_pid=$!
      read -r < "$pipe"
      geometry=$(slurp -d)
      if [[ -z "$geometry" ]]; then
        trap - EXIT
        kill $wayfreeze_pid 2>/dev/null || true
        rm -f "$pipe"
        exit 1
      fi
      "${cmd[@]}" -g "$geometry" "$filepath"
    else
      "${wayfreeze_cmd[@]}" --after-freeze-timeout 100 --after-freeze-cmd "echo > $pipe" &
      wayfreeze_pid=$!
      read -r < "$pipe"
      "${cmd[@]}" "$filepath"
    fi
    trap - EXIT
    kill $wayfreeze_pid 2>/dev/null || true
    rm -f "$pipe"
  elif [[ ${args[--region]} ]]; then
    geometry=$(slurp -d)
    [[ -z "$geometry" ]] && exit 1
    "${cmd[@]}" -g "$geometry" "$filepath"
  else
    "${cmd[@]}" "$filepath"
  fi
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
