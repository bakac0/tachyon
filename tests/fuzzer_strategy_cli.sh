#!/usr/bin/env bash
set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TACHYON_LIB="$ROOT_DIR/tachyon/files/usr/lib"
FUZZER="$ROOT_DIR/tachyon/files/usr/lib/diagnostics/fuzzer.uc"
BYEDPI_VALIDATOR="$ROOT_DIR/tachyon/files/usr/lib/providers/byedpi/validator.uc"
ZAPRET_VALIDATOR="$ROOT_DIR/tachyon/files/usr/lib/providers/zapret/validator.uc"
ZAPRET2_VALIDATOR="$ROOT_DIR/tachyon/files/usr/lib/providers/zapret2/validator.uc"
TACHYON_BIN="$ROOT_DIR/tachyon/files/usr/bin/tachyon"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# 1. Check strategies JSON output
strategies_json="$(ucode -L "$TACHYON_LIB" -- "$FUZZER" strategies)"
[ -n "$strategies_json" ] || fail "fuzzer strategies returned empty output"

# Validate JSON structure using node
JSON_VALUE="$strategies_json" node <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
if (typeof val.available_engines !== 'object') {
  console.error("Missing available_engines");
  process.exit(1);
}
if (!Array.isArray(val.zapret2) || val.zapret2.length === 0) {
  console.error("Missing zapret2 strategies");
  process.exit(1);
}
if (!Array.isArray(val.zapret) || val.zapret.length === 0) {
  console.error("Missing zapret strategies");
  process.exit(1);
}
if (!Array.isArray(val.byedpi) || val.byedpi.length === 0) {
  console.error("Missing byedpi strategies");
  process.exit(1);
}
if (!Array.isArray(val.flowseal) || val.flowseal.length < 10) {
  console.error("Missing Flowseal strategy list");
  process.exit(1);
}
for (const s of val.flowseal) {
  if (typeof s.args !== "string" || s.args.trim() === "") {
    console.error("Flowseal strategy has empty args:", s);
    process.exit(1);
  }
}
if (!val.target_suites || !val.target_suites.discord_voice_suite) {
  console.error("Missing Discord voice target suite");
  process.exit(1);
}
const voice = val.flowseal.filter((s) => s.voice === true);
if (voice.length < 3) {
  console.error("Missing Flowseal Discord voice fake matrix");
  process.exit(1);
}
for (const s of voice) {
  if (!s.args.includes("--filter-udp=19294-19344,50000-50100") ||
      !s.args.includes("--filter-l7=discord,stun") ||
      !s.args.includes("--dpi-desync-fake-discord=") ||
      !s.args.includes("--dpi-desync-fake-stun=")) {
    console.error("Invalid Flowseal voice strategy:", s);
    process.exit(1);
  }
}
NODE

# 2. Check each strategy passes its respective engine validator
byedpi_args="$(JSON_VALUE="$strategies_json" node - <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
for (const s of val.byedpi) {
  console.log(s.args);
}
NODE
)"

while IFS= read -r args; do
  [ -n "$args" ] || continue
  check="$(ucode -L "$TACHYON_LIB" -- "$BYEDPI_VALIDATOR" validate-json "$args")"
  JSON_VALUE="$check" node - <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
if (!val.valid) {
  console.error("ByeDPI strategy invalid:", val);
  process.exit(1);
}
NODE
done <<< "$byedpi_args"

zapret_args="$(JSON_VALUE="$strategies_json" node - <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
for (const s of val.zapret) {
  console.log(s.args);
}
NODE
)"

while IFS= read -r args; do
  [ -n "$args" ] || continue
  check="$(ucode -L "$TACHYON_LIB" -- "$ZAPRET_VALIDATOR" validate-json nfqws "$args")"
  JSON_VALUE="$check" node - <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
if (!val.valid) {
  console.error("Zapret strategy invalid:", val);
  process.exit(1);
}
NODE
done <<< "$zapret_args"

flowseal_args="$(JSON_VALUE="$strategies_json" node - <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
for (const s of val.flowseal) console.log(s.args);
NODE
)"
while IFS= read -r args; do
  [ -n "$args" ] || continue
  check="$(ucode -L "$TACHYON_LIB" -- "$ZAPRET_VALIDATOR" validate-json nfqws "$args")"
  JSON_VALUE="$check" node - <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
if (!val.valid) {
  console.error("Flowseal strategy invalid:", val);
  process.exit(1);
}
NODE
done <<< "$flowseal_args"

zapret2_args="$(JSON_VALUE="$strategies_json" node - <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
for (const s of val.zapret2) {
  console.log(s.args);
}
NODE
)"

while IFS= read -r args; do
  [ -n "$args" ] || continue
  check="$(ucode -L "$TACHYON_LIB" -- "$ZAPRET2_VALIDATOR" validate-json nfqws2 "$args")"
  JSON_VALUE="$check" node - <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
if (!val.valid) {
  console.error("Zapret2 strategy invalid:", val);
  process.exit(1);
}
NODE
done <<< "$zapret2_args"

# 3. Check status returns clean default state
status_json="$(ucode -L "$TACHYON_LIB" -- "$FUZZER" status)"
JSON_VALUE="$status_json" node <<'NODE'
const val = JSON.parse(process.env.JSON_VALUE);
if (val.running !== false) {
  console.error("Default fuzzer status should have running: false");
  process.exit(1);
}
if (!Array.isArray(val.results)) {
  console.error("Results should be an array");
  process.exit(1);
}
NODE

# 4. Check tachyon CLI command map contains fuzzer commands
grep -q 'fuzzer_start:' "$TACHYON_BIN" || fail "tachyon CLI missing fuzzer_start"
grep -q 'fuzzer_status:' "$TACHYON_BIN" || fail "tachyon CLI missing fuzzer_status"
grep -q 'fuzzer_stop:' "$TACHYON_BIN" || fail "tachyon CLI missing fuzzer_stop"
grep -q 'fuzzer_apply:' "$TACHYON_BIN" || fail "tachyon CLI missing fuzzer_apply"
grep -q 'fuzzer_strategies:' "$TACHYON_BIN" || fail "tachyon CLI missing fuzzer_strategies"
grep -q 'fuzzer_generate:' "$TACHYON_BIN" || fail "tachyon CLI missing fuzzer_generate"
grep -q 'fuzzer_ai_synthesize:' "$TACHYON_BIN" || fail "tachyon CLI missing fuzzer_ai_synthesize"
grep -q 'discord_voice_suite' "$FUZZER" || fail "fuzzer missing Discord voice suite"
grep -q 'voice_probe' "$FUZZER" || fail "fuzzer missing Discord voice probe"
grep -q 'passed_checks' "$FUZZER" || fail "fuzzer missing check-count scoring"
grep -q 'mode == "flowseal"' "$FUZZER" || fail "fuzzer missing direct Flowseal mode"
grep -q 'diagnostics.flowseal_import' "$FUZZER" || fail "fuzzer missing Flowseal importer"
grep -q 'FLOWSEAL_STRATEGIES_ZIP' "$ROOT_DIR/tachyon/files/usr/lib/diagnostics/flowseal_import.uc" || fail "Flowseal importer missing upstream archive URL"
grep -q 'unzip' "$ROOT_DIR/tachyon/files/usr/lib/diagnostics/flowseal_import.uc" || fail "Flowseal importer missing archive extraction"
grep -q 'join(" ", output)' "$ROOT_DIR/tachyon/files/usr/lib/diagnostics/flowseal_import.uc" || fail "Flowseal importer must use ucode join separator-first order"
grep -q 'join(" --new ", args)' "$ROOT_DIR/tachyon/files/usr/lib/diagnostics/flowseal_import.uc" || fail "Flowseal importer must join parsed strategy args"
grep -q 'FLOWSEAL_FAKE_DIR/g' "$FUZZER" || fail "fuzzer must replace every Flowseal fake path occurrence"
grep -q 'Flowseal fake asset path was not resolved' "$FUZZER" || fail "fuzzer must reject unresolved Flowseal fake paths"
grep -q 'voice_profile_ready' "$FUZZER" || fail "voice probe must use a typed readiness verdict"
grep -q 'flowseal_source' "$FUZZER" || fail "fuzzer status must expose Flowseal import source"
if grep -q 'udp://discord-voice' "$FUZZER"; then fail "voice probe must not expose a fake UDP URL"; fi
grep -q 'fuzzer_flowseal_update:' "$TACHYON_BIN" || fail "tachyon CLI missing Flowseal update command"

# 5. Check combinatorial strategies generation
combo_tmp="$(mktemp "${TMPDIR:-/tmp}/fuzzer_combo_XXXXXX")"
trap 'rm -f "$combo_tmp"' EXIT
ucode -L "$TACHYON_LIB" -- "$FUZZER" strategies combinatorial > "$combo_tmp"
COMBO_FILE="$combo_tmp" node <<'NODE'
const fs = require('fs');
const raw = fs.readFileSync(process.env.COMBO_FILE, 'utf8');
const val = JSON.parse(raw);
if (!Array.isArray(val.zapret2) || val.zapret2.length < 30) {
  console.error("Combinatorial zapret2 should have >= 30 strategies, got:", val.zapret2 ? val.zapret2.length : 0);
  process.exit(1);
}
if (!Array.isArray(val.zapret) || val.zapret.length < 20) {
  console.error("Combinatorial zapret should have >= 20 strategies, got:", val.zapret ? val.zapret.length : 0);
  process.exit(1);
}
if (!Array.isArray(val.byedpi) || val.byedpi.length < 20) {
  console.error("Combinatorial byedpi should have >= 20 strategies, got:", val.byedpi ? val.byedpi.length : 0);
  process.exit(1);
}
console.log("Generated matrix: Zapret2=" + val.zapret2.length + ", Zapret=" + val.zapret.length + ", ByeDPI=" + val.byedpi.length);
NODE

# 6. Check zapret2 Lua library resolution from LIB_DIR
lua_res="$(TACHYON_LIB="$TACHYON_LIB" ucode -L "$TACHYON_LIB" -e '
let fs = require("fs");
let LIB_DIR = getenv("TACHYON_LIB") || "/usr/lib/tachyon";
let candidate_dirs = [
    getenv("ZAPRET2_PROVIDER_LUA_DIR"),
    LIB_DIR + "/providers/zapret2/lua",
    "/usr/lib/tachyon/providers/zapret2/lua"
];
let lua_scripts = [ "zapret-lib.lua", "zapret-antidpi.lua", "zapret-auto.lua" ];
let flags = "";
for (let script in lua_scripts) {
    let found = null;
    for (let d in candidate_dirs) {
        if (!d || fs.stat(d) == null) continue;
        let p = d + "/" + script;
        if (fs.stat(p) != null) { found = p; break; }
        if (fs.stat(p + ".gz") != null) { found = p + ".gz"; break; }
    }
    if (found != null) flags += sprintf("--lua-init=@%s ", found);
}
print(flags);
')"
echo "$lua_res" | grep -q 'zapret-lib.lua' || fail "missing zapret-lib.lua in resolved lua flags"
echo "$lua_res" | grep -q 'zapret-antidpi.lua' || fail "missing zapret-antidpi.lua in resolved lua flags"
echo "$lua_res" | grep -q 'zapret-auto.lua' || fail "missing zapret-auto.lua in resolved lua flags"

printf 'PASS: fuzzer_strategy_cli\n'
