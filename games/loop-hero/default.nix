{
  self,
  lib,
  pkgs,
  fetchIpfs,
  unzip,
  autoPatchelfHook,
  stdenv,
}:

let
  # EOL compat carriers for the bundled libcurl's version-gated legacy
  # sonames (OPENSSL_1_1_x, OPENLDAP_2.4_2 symbol versions): the only
  # real providers, since nixpkgs dropped both series. See the
  # targetPkgs comment for the chain.
  openssl_1_1 = pkgs.callPackage ../../pkgs/openssl_1_1 { };
  openldap_2_4 = pkgs.callPackage ../../pkgs/openldap_2_4 { };

  # GOG Linux release of Loop Hero (1.1054 / build 55873). The mojosetup
  # .sh installer is a shell-script header followed by a zip archive, so
  # unzip handles it directly. Layout: data/noarch/game/Loop_Hero (ELF),
  # run.sh, libsteam_api.so, assets/, plus assets/linuxlibs/ (bundled
  # libcurl/libopenal/librtmp.so.0; no libssl/libcrypto anywhere in the
  # payload despite DT_NEEDEDs for the 1.1 sonames).
  installer = fetchIpfs {
    cid = "QmQSAMV6PnygfoLfYrNwXtCm5RzGdqu8p56qxPz3DahtPn";
    fallbackUrl = "https://archive.org/download/loop-hero-linux-gog-phoenix-games-lab/Game%2Floop_hero_1_1054_55873.sh";
    hash = "sha256-qItSj+ADA8ehsp96GZmdYIgKvof+Kz/JQteG0NAGSV8=";
    name = "loop-hero-linux-gog-1.1054.sh";
  };

  gameData = stdenv.mkDerivation {
    pname = "loop-hero-data";
    version = "1.1054";

    dontUnpack = true;

    nativeBuildInputs = [
      unzip
      autoPatchelfHook
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc
      glibc
      libGL
      libGLU
      libxkbcommon
      libpulseaudio
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXxf86vm
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      openssl
      openal
    ];

    # The bundled libcurl/libopenal/libssl 1.1/librtmp need autoPatchelf
    # to find their dependencies, but skip the binary so autoPatchelf
    # doesn't strip its bundled-lib RPATH; we set it manually below.
    # The bundled curl chain's sonames split in two: current-generation
    # ones nixpkgs still carries (zlib, nghttp2, psl, rtmp, gssapi/krb5,
    # the gnutls family) — resolved at runtime from the FHS env's
    # targetPkgs, which autoPatchelf cannot see because they are not
    # buildInputs here — and genuinely-legacy ones nothing carries:
    # openssl 1.1 (the bundle ships its own in assets/linuxlibs) and
    # OpenLDAP 2.4's libldap_r-2.4.so.2/liblber-2.4.so.2 (openldap >= 2.5
    # dropped libldap_r and moved to libldap.so.2/liblber.so.2). Suppress
    # autoPatchelf's complaints for all of them.
    autoPatchelfIgnoreMissingDeps = [
      "libssl.so.1.1"
      "libcrypto.so.1.1"
      "librtmp.so.1"
      "libpsl.so.5"
      "libgssapi_krb5.so.2"
      "libldap_r-2.4.so.2"
      "liblber-2.4.so.2"
      "libz.so.1"
      "libgnutls.so.30"
      "libhogweed.so.6"
      "libnettle.so.8"
      "libgmp.so.10"
      "libnghttp2.so.14"
      "libidn2.so.0"
    ];

    buildPhase = ''
      runHook preBuild
      unzip -q ${installer} || true
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r data/noarch/game/* "$out"/
      chmod +x "$out/Loop_Hero"
      runHook postInstall
    '';

    dontStrip = true;
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "loop-hero";

  ipfsSources = [ installer ];
  src = gameData;

  buildScript = ''
    mkdir -p "$out"
    cp -r "$src"/* "$out"/
  '';

  # The bundled libssl 1.1 / libcrypto 1.1 in assets/linuxlibs/ are
  # ancient and dlopen'd at runtime by libcurl. Use the FHS env so the
  # game's LD_LIBRARY_PATH=./assets/linuxlibs/ in run.sh resolves
  # correctly while still picking up libGL / libX11 / libopenal from
  # the system tree.
  runtime = "custom";
  executable = "Loop_Hero";

  targetPkgs =
    p: with p; [
      libGL
      libGLU
      libglvnd
      libxkbcommon
      libpulseaudio
      alsa-lib
      dbus
      mesa
      vulkan-loader
      xorg.libX11
      xorg.libXext
      xorg.libXrandr
      xorg.libXxf86vm
      xorg.libXcursor
      xorg.libXi
      xorg.libXinerama
      xorg.libxcb
      # The bundled assets/linuxlibs/librtmp.so.0 DT_NEEDEDs the gnutls
      # family (libgnutls.so.30, libhogweed.so.6, libnettle.so.8,
      # libgmp.so.10), which autoPatchelfIgnoreMissingDeps skips on the
      # assumption the FHS env provides them at runtime -- but the env
      # shipped none of them. buildEnv links only the packages named
      # here, never their runtime deps, so gnutls's whole DT_NEEDED
      # closure is listed explicitly (same fix as lib/proton.nix for the
      # proton runtime, commit 7bcd260): nettle (libnettle + libhogweed),
      # gmp, libtasn1, libunistring, libidn2, p11-kit, and libffi for
      # p11-kit. Soname set measured on gnutls 3.8.13 from the locked
      # nixpkgs.
      gnutls
      nettle
      gmp
      libtasn1
      libunistring
      libidn2
      p11-kit
      libffi
      # The rest of the bundled libcurl's DT_NEEDED chain that nixpkgs
      # still carries: zlib (also a direct DT_NEEDED of the Loop_Hero
      # binary), nghttp2, psl, rtmp (.so.1 — the bundle's librtmp.so.0
      # is stale, nothing needs it), krb5's gssapi, and sndio for the
      # bundled libopenal. The version-gated legacy tail — openssl 1.1
      # (libssl.so.1.1 / libcrypto.so.1.1, also direct DT_NEEDEDs of
      # the binary) and openldap 2.4's libldap_r-2.4.so.2 /
      # liblber-2.4.so.2 — comes from the compat carriers above; the
      # bundled-linuxlibs prefix keeps nothing shadowed.
      zlib
      nghttp2
      libpsl
      rtmpdump
      libkrb5
      sndio
      openssl_1_1
      openldap_2_4
    ];

  env = {
    # The bundled libcurl + libopenal must win over anything the FHS
    # layer exposes, so the game dir's linuxlibs (relative to the
    # wrapper's overlay cwd) comes first. A recipe-set LD_LIBRARY_PATH
    # fully replaces the strom-fhs default (/usr/lib:/usr/lib64), and the
    # loader's built-in search reaches the env's /lib64 but not /usr/lib
    # or /lib, so the FHS dirs must be restated here or nothing the env
    # ships there — libGL, libX11, the gnutls closure in targetPkgs —
    # resolves at runtime.
    LD_LIBRARY_PATH = "assets/linuxlibs:/usr/lib:/usr/lib64";
  };

  # The GameMaker Linux Runner ("YoYo Games Linux Runner V1.3")
  # enumerates every /dev/input/event* node as a joystick. On a
  # laptop that includes the touchpad: its absolute X/Y axes get
  # interpreted as analog stick input (range 0..1337 mapped into
  # signed 16-bit), so the game's UI cursor is pulled to a corner
  # and menu clicks land on the wrong button. The runner ignores
  # -nodirectinput, so mask /dev/input entirely. Mouse + keyboard
  # still work via Xwayland; controller users can use Steam Input
  # or unset this. Same workaround as anno-1503/anno-1602-ad.
  bwrap.tmpfs = [ "/dev/input" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      # The GameMaker runner uses XGrabPointer / raw X11 input. Under
      # gamescope's nested Xwayland, pointer events are only delivered
      # to the focused surface; force-grab-cursor keeps the cursor and
      # button events locked to the game window so menu clicks land.
      "--force-grab-cursor" = true;
    };
  };

  meta = {
    description = "Loop Hero (native Linux, GOG v1.1054 build 55873)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "loop-hero";
  };
}
