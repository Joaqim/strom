# OpenSSL 1.1.1 (final release 1.1.1w, EOL 2023-09-11) as a compat
# carrier for games whose bundled binaries DT_NEEDED libssl.so.1.1 /
# libcrypto.so.1.1 with OPENSSL_1_1_x symbol versions. nixpkgs removed
# the EOL openssl_1_1 attr; current openssl 3 can never satisfy the
# version gates, so the only real carrier is 1.1.1 itself.
#
# Resurrected from nixpkgs' unified openssl expression at commit
# eeb32698f853 ("openssl_1_1: 1.1.1v -> 1.1.1w", 2023-11, the last
# version bump before the attr's removal), trimmed to the
# shared-libraries consumer: same Configure mechanics, flags and
# patches; the bin/dev/man output splitting and c_rehash wrapper of the
# upstream expression are dropped and install_sw replaces install.
{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  perl,
  removeReferencesTo,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "openssl";
  version = "1.1.1w";

  src = fetchurl {
    url = "https://www.openssl.org/source/${finalAttrs.pname}-${finalAttrs.version}.tar.gz";
    hash = "sha256-zzCYlQy02FOtlcCEHx+cbT3BAtzPys1SHZOSUgi3asg=";
  };

  patches = [
    ./nix-ssl-cert-file.patch
    ./use-etc-ssl-certs.patch
  ];

  postPatch = ''
    patchShebangs Configure
    substituteInPlace config --replace '/usr/bin/env' '${buildPackages.coreutils}/bin/env'
  '';

  # The FHS env links /lib only; keep everything under one output.
  outputs = [ "out" ];

  nativeBuildInputs = [ perl ];

  strictDeps = true;

  # Upstream bakes the Configure target into configureScript (with
  # configurePlatforms = []) because Configure takes a target name, not
  # --host flags. x86_64-linux only — meta.platforms matches.
  configurePlatforms = [ ];
  configureScript = "./Configure linux-x86_64";

  configureFlags = [
    "shared"
    "--libdir=lib"
    "--openssldir=etc/ssl"
  ];

  enableParallelBuilding = true;

  installFlags = [ "install_sw" ];

  postInstall = ''
    rm -rf "$out"/bin "$out"/etc
  '';

  # -Wno-error guards: gcc >= 14 makes implicit declarations, int
  # conversions and pointer-type mismatches errors by default and 1.1.1
  # predates that toolchain. gcc 15 renamed -Wimplicit-int-conversion to
  # -Wint-conversion; the older name is an unknown-option error.
  env.NIX_CFLAGS_COMPILE = toString (
    lib.optionals (stdenv.cc.isGNU or false) [
      "-Wno-error=implicit-function-declaration"
      "-Wno-error=int-conversion"
      "-Wno-error=incompatible-pointer-types"
    ]
  );

  meta = {
    description = "OpenSSL 1.1.1 compat carrier (shared libraries only)";
    homepage = "https://www.openssl.org/";
    license = lib.licenses.openssl;
    platforms = lib.platforms.linux;
  };
})
