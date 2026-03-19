REPO="https://github.com/atheeq-rhxn/msnap"
manifest="@MANIFEST_PATH@"
binary_path="${BASH_SOURCE[0]}"

nix_managed=false
[[ "$binary_path" == /nix/store/* ]] && nix_managed=true

if [[ -n "${args[--version]:-}" ]]; then
  target_version="${args[--version]#v}"
else
  target_version=$(git ls-remote --tags --sort=version:refname "$REPO" 2>/dev/null \
    | grep -v '\^{}' \
    | tail -1 \
    | awk -F'refs/tags/v' '{print $2}') \
    || { echo "Error: Could not reach GitHub. Check your internet connection." >&2; exit 1; }
fi

if [[ "${args[--check]:-}" ]]; then
  if [[ "$version" == "$target_version" ]]; then
    echo "msnap is up to date (v${version})."
    exit 0
  else
    echo "Update available: v${version} -> v${target_version}"
    if [[ "$nix_managed" == true ]]; then
      echo "To update your Nix-managed install, run:" >&2
      echo "  nix flake update msnap  (in your system flake directory)" >&2
      echo "  nixos-rebuild switch" >&2
    fi
    exit 1
  fi
fi

if [[ "$nix_managed" == true ]]; then
  echo "Error: 'msnap update' is not supported for Nix-managed installations." >&2
  echo "To update, run:" >&2
  echo "  nix flake update msnap  (in your system flake directory)" >&2
  echo "  nixos-rebuild switch" >&2
  echo "" >&2
  echo "Tip: Use 'msnap update --check' to check for new versions without installing." >&2
  exit 1
fi

if [[ ! -f "$manifest" ]]; then
  echo "Error: No manifest found. Was msnap installed with 'make install'?" >&2
  exit 1
fi

if [[ "$version" == "$target_version" && -z "${args[--force]:-}" ]]; then
  echo "Already up to date (v${version}). Use --force to reinstall."
  exit 0
fi

bin_path=$(head -1 "$manifest")
if [[ ! -w "$(dirname "$bin_path")" ]]; then
  echo "Error: No write permission on $(dirname "$bin_path"). Try running with sudo." >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading msnap v${target_version}..."
curl -fsSL "${REPO}/archive/refs/tags/v${target_version}.tar.gz" -o "${tmp}/msnap.tar.gz" \
  || { echo "Error: Download failed." >&2; exit 1; }

tar -xzf "${tmp}/msnap.tar.gz" -C "$tmp" \
  || { echo "Error: Failed to extract archive." >&2; exit 1; }

src="${tmp}/msnap-${target_version}"
[[ -d "$src" ]] || { echo "Error: Unexpected archive layout." >&2; exit 1; }

gui_dir=$(grep -m1 '\.qml$' "$manifest" | xargs dirname)
icon_file=$(grep -m1 'hicolor' "$manifest")

echo "Installing..."
while IFS= read -r dest; do
  case "$dest" in
    *.conf) ;;
    *.desktop)
      sed "s|@GUI_PATH@|${gui_dir}|g" "${src}/assets/msnap.desktop.in" \
        | sed "s|@ICON_PATH@|${icon_file}|g" \
        | install -m644 /dev/stdin "$dest" \
        || { echo "Error: Failed to install $(basename "$dest")." >&2; exit 1; } ;;
    */hicolor/*)
      install -m644 "${src}/assets/icons/msnap.svg" "$dest" \
        || { echo "Error: Failed to install $(basename "$dest")." >&2; exit 1; } ;;
    */msnap/gui/Config.qml)
      sed "s|@BIN_PATH@|${bin_path}|g" "${src}/gui/Config.qml" \
        | install -m644 /dev/stdin "$dest" \
        || { echo "Error: Failed to install Config.qml." >&2; exit 1; } ;;
    */msnap/*)
      install -m644 "${src}/${dest#*/msnap/}" "$dest" \
        || { echo "Error: Failed to install $(basename "$dest")." >&2; exit 1; } ;;
    *)
      sed "s|@GUI_PATH@|${gui_dir}|g" "${src}/cli/msnap" \
        | install -m755 /dev/stdin "$dest" \
        || { echo "Error: Failed to install binary." >&2; exit 1; } ;;
  esac
done < "$manifest"

echo "msnap updated to v${target_version}."
notify-send "msnap updated" "Updated to v${target_version}" -a msnap 2>/dev/null || true
