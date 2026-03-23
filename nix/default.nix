{
  lib,
  stdenvNoCC,
  makeBinaryWrapper,
  bash,
  coreutils,
  grim,
  slurp,
  wl-clipboard,
  libnotify,
  wayfreeze,
  satty,
  gpu-screen-recorder,
  ffmpeg,
  quickshell,
  lswt,
  python3,
  glib,
  gobject-introspection,
  gst_all_1,
  pipewire,
}:
let
  pythonEnv = python3.withPackages (ps: with ps; [ pygobject3 ]);

  giTypelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    glib
    gobject-introspection
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
  ];

  gstPluginPath = lib.makeSearchPath "lib/gstreamer-1.0" [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    pipewire
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "msnap";
  version = lib.strings.trim (builtins.readFile ../VERSION);

  src = builtins.path {
    path = ../.;
    name = "source";
  };

  nativeBuildInputs = [ makeBinaryWrapper ];

  dontConfigure = true;

  buildPhase = ''
    make build \
      PREFIX="$out" \
      BINDIR="$out/bin" \
      DATADIR="$out/share" \
      SYSCONFDIR="$out/etc/xdg" \
      LOCALSTATEDIR="$out/var/lib"
  '';

  installPhase = ''
    make install \
      PREFIX="$out" \
      BINDIR="$out/bin" \
      DATADIR="$out/share" \
      SYSCONFDIR="$out/etc/xdg" \
      LOCALSTATEDIR="$out/var/lib" \
      DESTDIR=""

    substituteInPlace "$out/bin/msnap" \
      --replace-fail '#!/usr/bin/env bash' '#!${bash}/bin/bash'

    substituteInPlace "$out/share/msnap/scripts/capture_window.py" \
      --replace-fail '#!/usr/bin/env python3' '#!${pythonEnv}/bin/python3'

    wrapProgram "$out/share/msnap/scripts/capture_window.py" \
      --prefix GI_TYPELIB_PATH : "${giTypelibPath}" \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${gstPluginPath}"

    wrapProgram "$out/share/msnap/xdpw_chooser.sh" \
      --prefix PATH : "${lib.makeBinPath [ bash coreutils quickshell ]}"

    wrapProgram "$out/bin/msnap" \
      --prefix PATH : ${lib.makeBinPath [
        grim
        slurp
        wl-clipboard
        libnotify
        wayfreeze
        satty
        gpu-screen-recorder
        ffmpeg
        quickshell
        lswt
      ]}
  '';

  meta = {
    description = "Screenshot and screencast utility for mangowm";
    homepage = "https://github.com/atheeq-rhxn/msnap";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    platforms = lib.platforms.linux;
    mainProgram = "msnap";
  };
})
