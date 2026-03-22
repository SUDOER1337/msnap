manifest="@MANIFEST_PATH@"
binary_path="${BASH_SOURCE[0]}"

nix_managed=false
[[ "$binary_path" == /nix/store/* ]] && nix_managed=true

if [[ "$nix_managed" == true ]]; then
  echo "Error: 'msnap uninstall' is not supported for Nix-managed installations." >&2
  echo "To uninstall, remove 'msnap' from your Nix flake." >&2
  exit 1
fi

if [[ ! -f "$manifest" ]]; then
  echo "Error: No manifest found. Was msnap installed with 'make install'?" >&2
  exit 1
fi

if [[ -z "${args[--force]:-}" ]]; then
  file_count=$(wc -l < "$manifest")
  echo "This will remove $file_count files from your system."
  read -p "Continue? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "Uninstalling..."
removed=0
failed=0
while IFS= read -r dest; do
  if [[ -f "$dest" ]]; then
    rm -f "$dest" && ((removed++)) || ((failed++))
  fi
done < "$manifest"
rm -f "$manifest"
echo "Removed $removed file(s)."

rm -f "$manifest" && echo "Removed manifest: $manifest" || echo "Failed to remove manifest: $manifest" >&2

# Restore portal config backup or remove msnap-installed config
PORTAL_CONFIG_DIR="/home/atheeq/.config/xdg-desktop-portal-wlr"
if [[ -f "${PORTAL_CONFIG_DIR}/config.bak" ]]; then
    mv "${PORTAL_CONFIG_DIR}/config.bak" "${PORTAL_CONFIG_DIR}/config"
    echo "Restored portal config from backup."
else
    rm -f "${PORTAL_CONFIG_DIR}/config"
fi

echo "msnap uninstalled."
