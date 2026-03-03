# notify_saved fp msg type [skip_annotate]
#   type: "shot" or "cast"
#   skip_annotate: any non-empty value suppresses the Annotate action
notify_saved() {
  local fp="$1"
  local msg="$2"
  local type="$3"
  local skip_annotate="${4:-}"

  local app title icon
  if [[ "$type" == "shot" ]]; then
    app="msnap-shot"
    title="Screenshot saved"
    icon="$fp"
  else
    app="msnap-cast"
    title="Recording saved"
    icon="video-x-generic"
  fi

  local notify_actions=(-A "open=Open File" -A "folder=Open Folder")
  [[ "$type" == "shot" && -z "${args[--annotate]}" && -z "$skip_annotate" ]] \
    && notify_actions+=(-A "annotate=Annotate")

  local action
  action=$(notify-send "$title" "$msg" \
    -i "$icon" -a "$app" \
    "${notify_actions[@]}")

  case "$action" in
    open)
      xdg-open "$fp" >/dev/null 2>&1
      ;;
    folder)
      xdg-open "$(dirname "$fp")" >/dev/null 2>&1
      ;;
    annotate)
      satty --filename "$fp" --output-filename "$fp" \
        --actions-on-enter save-to-file --early-exit --disable-notifications
      notify_saved "$fp" "Annotated image saved in <i>${fp}</i>." "shot" "skip"
      ;;
  esac
}
