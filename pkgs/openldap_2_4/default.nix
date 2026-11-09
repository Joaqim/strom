# OpenLDAP 2.4 (final 2.4 release 2.4.58, superseded 2022) as a compat
# carrier for games whose bundled binaries DT_NEEDED the 2.4-era
# libldap_r-2.4.so.2 / liblber-2.4.so.2 sonames with OPENLDAP_2.4_2
# symbol versions. openldap >= 2.5 dropped libldap_r (the threaded
# variant merged into libldap) and renamed the pair to libldap.so.2 /
# liblber.so.2, so current nixpkgs can never satisfy those version
# gates.
#
# Resurrected from nixpkgs' openldap expression at commit c33650807407
# ("openldap: 2.4.57 -> 2.4.58", the last 2.4-series bump), trimmed to
# the libraries-only consumer: no slapd (configure --disable-slapd
# removes the server, its overlays and backends), no SASL, no TLS
# backend (libcurl's LDAP support speaks plaintext ldap:// URLs; the
# bundled binaries link the sonames for symbol resolution, and a TLS
# backend would drag this EOL series' crypto choices further in).
# Libraries only: install keeps libldap, libldap_r and liblber.
{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "openldap";
  version = "2.4.58";

  src = fetchurl {
    url = "https://www.openldap.org/software/download/OpenLDAP/openldap-release/${finalAttrs.pname}-${finalAttrs.version}.tgz";
    hash = "sha256-V7WSVL4V0L9qmrPVFMHAV3ewISMpFTMTSofJRGj49Hs=";
  };

  outputs = [ "out" ];

  enableParallelBuilding = true;

  makeFlags = [
    "STRIP="
    "prefix=$(out)"
  ];

  configureFlags = [
    "--disable-slapd"
    "--disable-dependency-tracking"
    "--without-cyrus-sasl"
    "--without-tls"
  ];

  # 2.4 is a K&R-era codebase compiled against pre-C99 semantics:
  # include/ac/string.h declares fallback prototypes like
  # `int (strcasecmp)();` which C23 (gcc >= 15's default) reads as
  # (void) and rejects as conflicting with glibc's, and configure's own
  # probes use implicit-int main(), which as a hard error makes
  # configure abort with "broken POSIX regex!". One switch restores the
  # semantics the tree was written for instead of flag-by-flag
  # downgrades.
  env.NIX_CFLAGS_COMPILE = lib.optionalString (stdenv.cc.isGNU or false) "-std=gnu89";

  # Debian's libldap-symbol-versions patch (openldap-team packaging,
  # bullseye era), which the bundled libcurl's OPENLDAP_2.4_2 verneed
  # demands: upstream 2.4 exports unversioned symbols only, and the
  # Debian-built consumers of the era carry DT_VERNEED entries the
  # loader enforces. The patch's autoconf half (OL_SYMBOL_VERSIONING
  # detection) is replaced by hardcoding the flags: this derivation
  # targets one linker (GNU ld) on one platform.
  postPatch = ''
    cat > libraries/libldap/libldap.map <<'EOF'
    OPENLDAP_2.4_2 {
      global:
        ldap_*;
        ldif_*;
      local:
        *;
    };
    EOF
    cat > libraries/liblber/liblber.map <<'EOF'
    OPENLDAP_2.4_2 {
      global:
        ber_*;
        der_alloc;
        lutil_*;
      local:
        *;
    };
    EOF
    substituteInPlace build/top.mk --replace-fail \
      '$(CC) $(LT_CFLAGS) $(LDFLAGS) $(LTFLAGS_LIB)' \
      '$(CC) $(LT_CFLAGS) $(LDFLAGS) $(LTFLAGS_LIB) $(VERSION_FLAGS)'
    echo 'VERSION_FLAGS = -Wl,--version-script=libldap.map' >> libraries/libldap/Makefile.in
    echo 'VERSION_FLAGS = -Wl,--version-script=../libldap/libldap.map' >> libraries/libldap_r/Makefile.in
    echo 'VERSION_FLAGS = -Wl,--version-script=liblber.map' >> libraries/liblber/Makefile.in
  '';

  # Only the libraries tree; clients and admin tools stay unbuilt. The
  # top-level build generates include/ldap_config.h before descending;
  # jumping straight into libraries/ skips that, so generate it first.
  preBuild = ''
    make -C include ldap_config.h
  '';

  buildFlags = [ "-C libraries" ];
  installFlags = [ "-C libraries" ];

  postInstall = ''
    rm -rf "$out"/bin "$out"/sbin "$out"/etc "$out"/var "$out"/share
    rm -f "$out"/lib/*.a "$out"/lib/*.la
  '';

  meta = {
    description = "OpenLDAP 2.4 compat carrier (libldap_r and liblber only)";
    homepage = "https://www.openldap.org/";
    license = lib.licenses.openldap;
    platforms = lib.platforms.linux;
  };
})
