# Conditioning assertions for bodycam's `onlineFix` player setting
# (the couch-launcher row declared in games/bodycam/default.nix).
#
# Drives the REAL bodycam module through the same `.apply` path the
# launcher uses (pkgs/launcher/launcher.py build_expr) and asserts, at
# evaluation time on the module config, that the row is published and
# that everything the online fix needs switches with it:
#
#   1. settingsSchema (passthru on the wrapper, baked into the
#      launcher manifest) carries one bool row keyed `onlineFix`,
#      shipped default false.
#   2. Off (the default): the overlay holds only the materialized
#      dataArchive base lower, no steamBridge bwrap binds, no emu env.
#   3. On: the fix tree rides as the first overlay lower above the
#      base, the Steam install binds appear, and the three env vars
#      are set.
#
# Evaluation only: nothing here builds the fix FOD or a wrapper, so the
# check itself can never fetch game bytes.
{
  lib,
  pkgs,
  game,
}:
let
  on = game.apply { onlineFix = true; };
  rows = builtins.filter (r: r.key == "onlineFix") (game.outputs.wrapper.passthru.settingsSchema);
  baseLower = "$STROM_GAMEDIR/.strom-data/5606be923449";
  lowersOff = game.bwrap.overlay.lowers;
  lowersOn = on.bwrap.overlay.lowers;
in
lib.throwIfNot (builtins.length rows == 1)
  "bodycam-onlinefix: settingsSchema has ${toString (builtins.length rows)} onlineFix rows, expected exactly 1"
  (
    lib.throwIfNot ((builtins.head rows).kind == "bool")
      "bodycam-onlinefix: onlineFix row is not a bool"
      (
        lib.throwIfNot ((builtins.head rows).default == false)
          "bodycam-onlinefix: onlineFix row does not ship default false"
          (
            lib.throwIfNot (lowersOff == [ baseLower ])
              "bodycam-onlinefix: onlineFix off still mounts ${toString (builtins.length lowersOff)} lowers, expected only the base ${baseLower}"
              (
                lib.throwIfNot
                  (
                    builtins.length lowersOn == 2
                    && lib.hasPrefix "/nix/store/" (builtins.head lowersOn)
                    && lib.hasInfix "bodycam-onlinefix" (builtins.head lowersOn)
                    && builtins.elemAt lowersOn 1 == baseLower
                  )
                  "bodycam-onlinefix: onlineFix on must mount the fix tree as the first lower above ${baseLower}"
                  (
                    lib.throwIfNot
                      (
                        game.steamBridge == false
                        && !(game.bwrap.ro-bind-try ? "$HOME/.local/share/Steam")
                        && !(game.bwrap.bind-try ? "$HOME/.steam")
                      )
                      "bodycam-onlinefix: onlineFix off must not bridge the host Steam install"
                      (
                        lib.throwIfNot
                          (
                            on.steamBridge == true
                            && (on.bwrap.ro-bind-try ? "$HOME/.local/share/Steam")
                            && (on.bwrap.bind-try ? "$HOME/.steam")
                          )
                          "bodycam-onlinefix: onlineFix on must bridge the host Steam install"
                          (
                            lib.throwIfNot (game.env == { }) "bodycam-onlinefix: onlineFix off still sets env" (
                              lib.throwIfNot
                                (
                                  on.env.SteamAppId or null == "2406770"
                                  && on.env.SteamGameId or null == "2406770"
                                  && on.env.WINEDLLOVERRIDES or null == "winmm=n,b"
                                )
                                "bodycam-onlinefix: onlineFix on must set SteamAppId/SteamGameId/WINEDLLOVERRIDES"
                                (
                                  pkgs.runCommand "bodycam-onlinefix-check" { } ''
                                    echo "bodycam-onlinefix: schema row published; overlay, steamBridge and env all switch with onlineFix" >&2
                                    touch "$out"
                                  ''
                                )
                            )
                          )
                      )
                  )
              )
          )
      )
  )
