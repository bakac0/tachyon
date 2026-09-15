#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAKEFILE="$ROOT_DIR/tachyon/Makefile"
BUILD_SH="$ROOT_DIR/build.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -f "$MAKEFILE" ] || fail "tachyon/Makefile not found"
[ -f "$BUILD_SH" ] || fail "build.sh not found"

# Release packages are produced by build.sh, while the OpenWrt feed build uses
# tachyon/Makefile. Both must ship an identical file inventory or installs
# silently lose hotplug handlers, the agent CGI and reset defaults.
required_sources=(
  "files/etc/init.d/tachyon"
  "files/etc/init.d/tachyon-torrserver-direct"
  "files/etc/config/tachyon"
  "files/usr/bin/tachyon"
  "files/etc/hotplug.d/iface/99-tachyon-wan-monitor"
  "files/usr/lib/cgi-bin/tachyon-agent"
  "files/usr/share/tachyon/servicecheck_profiles.json"
)

for rel in "${required_sources[@]}"; do
  [ -f "$ROOT_DIR/tachyon/$rel" ] || fail "source file missing: tachyon/$rel"
  grep -Fq "$rel" "$MAKEFILE" || fail "Makefile no longer ships $rel — update tests/package_inventory.sh"
  grep -Fq "$rel" "$BUILD_SH" || fail "build.sh does not package $rel (diverges from Makefile)"
done

# Flowseal presets depend on architecture-independent fake packet samples;
# zapret installation must provision the complete upstream .bin set.
grep -Fq 'function ensure_flowseal_fake_files' "$ROOT_DIR/tachyon/files/usr/lib/components/action.uc" ||
  fail "zapret installer must provision Flowseal fake .bin files"
for fake in \
  ACTIVE_DISCORD_UDP.bin ACTIVE_GAME_UDP.bin quic_initial_www_google_com.bin \
  stun.bin stun2.bin tls_clienthello_4pda_to.bin tls_clienthello_max_ru.bin \
  tls_clienthello_sochi_park.bin tls_clienthello_www_google_com.bin; do
  grep -Fq "\"$fake\"" "$ROOT_DIR/tachyon/files/usr/lib/components/action.uc" ||
    fail "zapret installer missing Flowseal fake asset $fake"
done

# Derived file installed only by the packaging recipes (not present in files/).
grep -Fq '/usr/lib/tachyon/defaults/config' "$MAKEFILE" ||
  fail "Makefile no longer installs defaults/config"
grep -Fq 'usr/lib/tachyon/defaults/config' "$BUILD_SH" ||
  fail "build.sh does not package /usr/lib/tachyon/defaults/config (reset_settings would break)"

# Secrets-bearing files must not be world-readable in release packages.
grep -Eq 'chmod 0600 .*etc/config/tachyon' "$BUILD_SH" ||
  fail "build.sh must enforce mode 0600 on /etc/config/tachyon"
grep -Eq 'chmod 0600 .*usr/lib/tachyon/defaults/config' "$BUILD_SH" ||
  fail "build.sh must enforce mode 0600 on defaults/config"

printf 'package inventory checks passed\n'
