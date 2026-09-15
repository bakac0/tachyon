# StressOzz Zapret-Manager: Flowseal Strategy Import

Research date: 2026-09-16

Primary sources:

- [StressOzz/Zapret-Manager](https://github.com/StressOzz/Zapret-Manager)
- [`Zapret-Manager.sh`](https://github.com/StressOzz/Zapret-Manager/blob/main/Zapret-Manager.sh)
- [`Strategies.md`](https://github.com/StressOzz/Zapret-Manager/blob/main/Strategies.md)
- [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube)

## Executive summary

StressOzz uses a deliberately narrow importer rather than a general Windows-to-Linux strategy compiler:

1. Download the current Flowseal repository as a ZIP archive.
2. Find `general*.bat` files in the extracted tree.
3. Keep only lines whose prefixes match a whitelist of Discord, game, Google and general web filters.
4. Turn each selected file into a named strategy block.
5. Remove Windows-only list and IP-set arguments.
6. Replace the known Flowseal TLS fake path with the local Zapret fake-file path.
7. Store the resulting blocks in the device configuration and apply them as `NFQWS_OPT`.

This is effective because it avoids importing desktop-only commands, but it also means unsupported options are silently discarded and the result depends on the exact syntax used by the current Flowseal repository.

## Acquisition and discovery

The manager downloads Flowseal's `main.zip` into a temporary directory, installs `unzip` when needed, and extracts it. It then searches for `general*.bat`; `general (ALT5).bat` is explicitly excluded.

The source is the moving `main` branch rather than a tag or commit. There is no visible commit pinning, archive signature validation, or checksum verification in this import path. The temporary extraction directory is removed after the import.

## What is imported

The importer keeps only lines beginning with one of these filter forms:

- Discord/game UDP ranges: `19294-19344,50000-50100`.
- Game TCP and UDP filters represented by Flowseal variables.
- Discord alternate TCP ports: `2053,2083,2087,2096,8443`.
- Google TLS traffic using `list-google.txt`.
- General TCP traffic using `list-general.txt`.

The selected lines are written below a `#<filename>` heading. A simple delimiter transformation turns a command containing several `--...` arguments into one argument per line. This is formatting, not semantic parsing: the importer does not build an AST, validate option combinations, or translate every Flowseal variable.

## Normalization and discarded data

The script performs a small number of targeted transformations:

- `%BIN%tls_clienthello_www_google_com.bin` becomes `/opt/zapret/files/fake/tls_clienthello_www_google_com.bin`.
- Windows list arguments referencing `%LISTS%` are removed where they are not usable by the target installation.
- `--ipset`, `--ipset-exclude`, and user-list variants are removed from the generated output.
- The generated block is therefore dependent on the target path `/opt/zapret/files/fake` and on the target's own host-list configuration.

The native strategy documentation shows the same target-side representation: explicit `--filter-*` arguments, local `/opt/zapret/files/fake/...` paths, and multiline `NFQWS_OPT` blocks. See [`Strategies.md`](https://github.com/StressOzz/Zapret-Manager/blob/main/Strategies.md).

## Installation of fake binaries

Zapret-Manager has a separate helper that downloads missing fake binaries from Flowseal's `main/bin` directory into `/opt/zapret/files/fake`. It runs only when the Zapret installation and configuration are present, and it does not overwrite an existing file.

This is the important operational dependency: importing a strategy is not enough if the referenced `.bin` file is absent. The helper is useful as a fallback, but its moving-branch download model should be treated as a supply-chain risk unless the consumer adds a pinned revision and integrity checks.

## Applying and testing

The Flowseal menu caches the generated strategy file and offers a refresh action. On selection, it extracts the named block, replaces the existing `NFQWS_OPT` section in the UCI configuration, extends the TCP/UDP port lists needed by Discord and games, and restarts Zapret. The README also exposes testing and automatic strategy-selection flows for the imported strategies.

The Tachyon implementation now keeps Discord Voice as a separate Flowseal profile family. These profiles follow Flowseal's upstream voice block: UDP ports `19294-19344,50000-50100`, `--filter-l7=discord,stun`, and paired `--dpi-desync-fake-discord` / `--dpi-desync-fake-stun` assets. See the upstream [`general.bat`](https://github.com/Flowseal/zapret-discord-youtube/blob/main/general.bat).

For Discord runs, Tachyon scores the number of checks passed before latency and throughput. HTTP/API/CDN checks remain deterministic; a Flowseal voice candidate additionally gets a voice-profile readiness check that confirms the required UDP filter and both fake files are present. This is intentionally not presented as a real Discord channel join: an authenticated Discord/WebRTC client is still required to prove microphone and audio reception.

## Implications for Tachyon

The useful design to borrow is the source adapter boundary:

```text
Flowseal archive -> candidate .bat files -> whitelist extractor -> normalizer
                 -> Tachyon strategy validator -> named flowseal profiles
```

Tachyon should improve the weak points of the shell importer:

- Pin a release or commit by default; make updates explicit.
- Download into a temporary directory and install atomically.
- Keep the source filename and skipped-line reason for diagnostics.
- Resolve fake files through Tachyon's configured provider directory, not a hard-coded `/opt` path.
- Validate every generated profile before exposing it to the runtime.
- Report unsupported arguments instead of silently dropping them.
- Verify required `.bin` files by expected size and SHA-256 before activation.
- Never download from Flowseal during router boot; use an explicit update/install action.

The Zapret installer already follows the relevant Zapret-Manager behavior: it creates the provider fake directory, downloads only missing Flowseal files from `main/bin`, and fails the installation if a required file cannot be downloaded. Because older Zapret installations predate the Flowseal manifest, run `tachyon component_action install zapret` once after upgrading Tachyon to repair missing assets.

Tachyon now uses this design as a generated cache: `flowseal` mode refreshes the upstream archive, extracts `general*.bat`, writes normalized profiles to `/etc/tachyon/flowseal_strategies.json`, and falls back to the built-in compatibility list only when download/import fails. The runtime continues to consume the same validated strategy representation.

The explicit refresh command is:

```sh
tachyon fuzzer_flowseal_update
```

Its JSON result exposes the source URL, source ref, import timestamp, and imported profile count. A Discord voice readiness result is represented as structured fields (`transport: "udp"`, `port_range`, `voice: true`, `dpi_verdict: "voice_profile_ready"`), not as a fabricated `udp://` URL.

## Conclusion

StressOzz's approach is a pragmatic compatibility filter, not a complete compiler. It demonstrates that automatic Flowseal support is feasible, but a robust Tachyon implementation should preserve the same extraction idea while adding pinned sources, explicit diagnostics, path abstraction, validation, atomic asset installation, and integrity verification.
