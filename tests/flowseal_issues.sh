#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TACHYON_LIB="$ROOT_DIR/tachyon/files/usr/lib"
IMPORTER="$TACHYON_LIB/diagnostics/flowseal_import.uc"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tachyon-flowseal-issues.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cat >"$WORK_DIR/unsafe.bat" <<'BAT'
--filter-tcp=80,443;touch /tmp/flowseal-injection
BAT

cat >"$WORK_DIR/invalid.bat" <<'BAT'
--filter-tcp=80,443 --unknown-option=value
BAT

cat >"$WORK_DIR/valid.bat" <<'BAT'
--filter-tcp=80,443 --dpi-desync=fake ^
--filter-udp=%GameFilterUDP% --dpi-desync=fake
BAT

IMPORTER="$IMPORTER" WORK_DIR="$WORK_DIR" ucode -L "$TACHYON_LIB" -e '
let fs = require("fs");
let importer = require("diagnostics.flowseal_import");
let dir = getenv("WORK_DIR");
let unsafe = importer.parse_file(dir + "/unsafe.bat");
if (unsafe != null) die("unsafe BAT must be rejected");
let invalid = importer.parse_file(dir + "/invalid.bat");
if (invalid != null) die("unvalidated BAT must be rejected");
let valid = importer.parse_file(dir + "/valid.bat");
if (valid == null) die("valid BAT must be imported");
if (index(valid.args, " --new  --new ") >= 0) die("strategy sections must not contain a duplicated separator");
if (index(valid.args, "19294-19344") < 0) die("GameFilterUDP must be resolved");
print("flowseal importer issue tests passed\n");
' 

grep -Fq 'download_ok' "$TACHYON_LIB/diagnostics/flowseal_import.uc" || {
  echo 'F1 regression guard missing download result state' >&2
  exit 1
}

grep -Fq 'flowseal_score' "$ROOT_DIR/tachyon/files/usr/lib/diagnostics/fuzzer.uc" || {
  echo 'C2 regression guard missing common score normalization' >&2
  exit 1
}
grep -Fq 'total_checks = http_url_count' "$ROOT_DIR/tachyon/files/usr/lib/diagnostics/fuzzer.uc" || {
  echo 'C3 regression guard: voice readiness must not count as network success' >&2
  exit 1
}
grep -Fq 'curl TLS handshake failed (exit 35)' "$ROOT_DIR/tachyon/files/usr/lib/diagnostics/fuzzer.uc" || {
  echo 'F3 regression guard missing TLS error classification' >&2
  exit 1
}
