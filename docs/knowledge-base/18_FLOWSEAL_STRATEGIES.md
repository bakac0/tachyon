# Flowseal strategy import

Дата проверки: 2026-09-15.

## Источники

- [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) — список `general*.bat` и описание назначения стратегий.
- [Flowseal `bin/`](https://github.com/Flowseal/zapret-discord-youtube/tree/main/bin) — перечень fake `.bin`-файлов, используемых стратегиями.
- [Flowseal `general.bat`](https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/general.bat) и [general (ALT4).bat](https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/general%20%28ALT4%29.bat) — исходные nfqws-совместимые параметры для базового и badseq/multisplit профилей.

## Зафиксированный контракт

Tachyon публикует Flowseal-профили отдельным ключом `flowseal` в результате `diagnostics/fuzzer.uc strategies`. Профили сохраняют `engine: "zapret"`, поэтому их проверяет общий nfqws validator и применяет тот же UCI-маршрут, что и native zapret presets.

Путь fake-файлов не зашит в стратегию: маркер `FLOWSEAL_FAKE_DIR` разворачивается в каталог provider runtime при fuzzing и при apply. Это сохраняет работоспособность при нестандартном `ZAPRET_PROVIDER_FILES_DIR`.

## Runtime assets

При установке компонента `zapret` Tachyon проверяет и при отсутствии скачивает из upstream Flowseal полный набор архитектурно-независимых `.bin` из каталога `bin/`. В него входят Discord/game UDP, QUIC, STUN и TLS ClientHello samples, включая файлы для ALT10/ALT13 профилей. Установка считается неуспешной, если любой требуемый файл не доставлен.
