{
  self,
  lib,
  pkgs,
  fetchIpfs,
  p7zip,
}:

let
  # Operator drop: /var/lib/steam/game-archives/Gloomwood.zip
  # (2,968,764,784 bytes, sha256 08d77176...c62706e), an AnkerGames
  # pre-installed tree of the Windows build, not an installer. Added to
  # the local kubo daemon (system ipfs service, repo /var/lib/ipfs,
  # PeerID 12D3KooWDoqC29n4gsnVVpPLwiw6q9caJukL91GAqFVmEpQmhZfH) as
  # both CIDv0 QmdxLvpmDGwK3U7eKF9Ugt6bTdZCwgJZMeijvUosqkeUzs and the
  # CIDv1 below; the v1 root is what the gateway serves for a file of
  # this size (AGENTS.md, 44 MiB rule), verified by range GET
  # (206, zip magic) on 127.0.0.1:8080. Upstream identity: GOG product
  # 1332747658, Steam appid 1150760. No non-IPFS mirror of these bytes
  # exists (paid GOG/Steam builds are the only official source), so
  # fallbackUrl stays empty.
  src = fetchIpfs {
    cid = "bafybeielhwosgtn2heuvbhozoee2u3msrcs2kisd3nn4denthbofrwka4i";
    fallbackUrl = "";
    hash = "sha256-CNdxdkycPaYqUxmZX4RxEkMc1yVaeGxuq7PVv/xicG4=";
    name = "gloomwood-ankergames.zip";
  };
in
self.lib.mkGame { inherit lib pkgs; } {
  name = "gloomwood";

  inherit src;

  nativeBuildInputs = [ p7zip ];

  # AnkerGames zip layout: Gloomwood/ (Gloomwood.exe + Gloomwood_Data/
  # + UnityPlayer.dll + UnityCrashHandler64.exe) beside root-level
  # debris (AnkerGames advert .url, "Read Me.txt", "Run Me!.bat").
  # Copying only the Gloomwood/ subtree drops the debris without a
  # separate rm. The zip is 7-Zip-made (every entry compression
  # method 93, LZMA), which Info-ZIP unzip refuses outright; extract
  # with p7zip.
  buildScript = ''
    mkdir -p "$out"
    7z x -y -o"$TMPDIR/extract" "$src" > /dev/null
    cp -r "$TMPDIR/extract/Gloomwood/"* "$out"/
  '';

  runtime = "proton";

  executable = "Gloomwood.exe";

  # Unity persistentDataPath AppData/LocalLow/<company>/<product>; the
  # company string is taken verbatim from Gloomwood_Data/app.info line 1
  # ("Dillon Rogers"), product from line 2 ("Gloomwood"). Phase 2
  # interactive audit (launch, write a save, find newer dirs) still
  # pending with the operator.
  saveLocations = [ "AppData/LocalLow/Dillon Rogers/Gloomwood" ];

  gamescope = {
    output-width = 1920;
    output-height = 1080;
    nested-width = 1920;
    nested-height = 1080;
    flags = {
      "-r" = "60";
      "--expose-wayland" = true;
    };
  };

  meta = {
    description = "Gloomwood (New Blood Interactive 2022, Victorian stealth immersive sim, Unity Mono via Proton)";
    platforms = [ "x86_64-linux" ];
    mainProgram = "gloomwood";
  };
}
