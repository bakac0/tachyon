let fs = require("fs");
let common = require("core.common");
let as_string = common.as_string;

const FLOWSEAL_STRATEGIES_ZIP = "https://github.com/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip";
const FLOWSEAL_CACHE = "/etc/tachyon/flowseal_strategies.json";
const FLOWSEAL_WORK_DIR = "/tmp/tachyon-flowseal-import";
const FLOWSEAL_FAKE_DIR = "FLOWSEAL_FAKE_DIR";

function shell_command(command) {
    return common.command_success(command);
}

function file_nonempty(path) {
    let st = fs.stat(path);
    return st != null && int(st.size || 0) > 0;
}

function slug(value) {
    value = lc(as_string(value));
    value = replace(value, /[^a-z0-9]+/g, "_");
    value = replace(value, /^_+|_+$/g, "");
    return value == "" ? "flowseal_strategy" : value;
}

function trim_token(token) {
    token = trim(as_string(token));
    token = replace(token, "\"", "");
    token = replace(token, "'", "");
    return token;
}

function unsupported_token(token) {
    token = trim_token(token);
    return index(token, "%LISTS%") >= 0 ||
        index(token, "%BIN%service") >= 0 ||
        index(token, "--wf-") == 0 ||
        index(token, "--hostlist-exclude=") == 0 ||
        index(token, "--ipset=") == 0 ||
        index(token, "--ipset-exclude=") == 0;
}

function safe_flowseal_token(token) {
    token = trim_token(token);
    if (token == "") return true;
    // A downloaded BAT is data, never a shell fragment.  Reject separators,
    // substitutions, redirections and command syntax before any runtime use.
    if (match(token, /[;&|`$<>\n\r]/) != null) return false;
    if (index(token, "\\") >= 0 && index(token, "\\\\") >= 0) return false;
    return match(token, /^--[a-z0-9][a-z0-9-]*(=[a-zA-Z0-9_.,:+%\/=~-]+)?$/) != null;
}

function validate_imported_line(args) {
    try {
        let validator = require("providers.zapret.validator");
        let result = validator.validate_strategy("nfqws", args, "");
        return result != null && result.valid == true;
    } catch (e) {
        // Import must fail closed when the common validator is unavailable.
        return false;
    }
}

function normalize_line(line) {
    line = trim(as_string(line));
    if (line == "" || substr(line, 0, 2) == "::" || substr(line, 0, 1) == ":")
        return "";
    if (substr(line, length(line) - 1, 1) == "^")
        line = trim(substr(line, 0, length(line) - 1));

    let tokens = split(line, /[ \t]+/);
    let output = [];
    for (let token in tokens) {
        token = trim_token(token);
        if (token == "" || unsupported_token(token) || !safe_flowseal_token(token))
            continue;
        token = replace(token, "%BIN%", FLOWSEAL_FAKE_DIR + "/");
        token = replace(token, "%GameFilterTCP%", "80,443,2053,2083,2087,2096,8443");
        token = replace(token, "%GameFilterUDP%", "443,19294-19344,50000-50100");
        token = replace(token, "^!", "!");
        if (index(token, "\\") >= 0)
            token = replace(token, "\\", "/");
        push(output, token);
    }
    if (length(output) == 0 || length(output) != length(tokens))
        return "";
    return join(" ", output);
}

function file_name(path) {
    let m = match(as_string(path), /\/([^\/]+)$/);
    return m && m[1] ? m[1] : as_string(path);
}

function parse_bat(path) {
    let content = fs.readfile(path);
    if (content == null)
        return [];
    content = replace(content, "\r", "");
    let lines = split(content, "\n");
    let args = [];
    for (let line in lines) {
        line = trim(as_string(line));
        if (substr(line, 0, 9) != "--filter-")
            continue;
        let normalized = normalize_line(line);
        if (normalized != "")
            push(args, normalized);
    }
    return args;
}

function parse_file(path) {
    let name = file_name(path);
    if (substr(name, length(name) - 4) == ".bat")
        name = substr(name, 0, length(name) - 4);
    let args = parse_bat(path);
    if (length(args) == 0)
        return null;
    for (let line in args) {
        if (!validate_imported_line(line))
            return null;
    }
    return {
        id: "flowseal_import_" + slug(name),
        name: "Flowseal " + name,
        engine: "zapret",
        args: join(" --new ", args),
        source: path,
        description: "Imported from Flowseal " + name + ".bat",
        imported: true
    };
}

function cached() {
    let value = common.read_json_file(FLOWSEAL_CACHE);
    if (type(value) != "object" || type(value.strategies) != "array" || length(value.strategies) == 0)
        return null;
    return value;
}

function import_flowseal(refresh) {
    if (!refresh) {
        let old = cached();
        if (old != null)
            return old;
    }

    common.ensure_dir(FLOWSEAL_WORK_DIR);
    let zip = FLOWSEAL_WORK_DIR + "/flowseal-main.zip";
    let base = FLOWSEAL_WORK_DIR + "/zapret-discord-youtube-main";
    common.remove_file(zip);
    shell_command("rm -rf " + common.shell_quote(base));

    let download = "curl -fsSL --connect-timeout 10 -m 90 -o " + common.shell_quote(zip) + " " + common.shell_quote(FLOWSEAL_STRATEGIES_ZIP);
    let download_ok = shell_command(download) && file_nonempty(zip);
    if (!download_ok) {
        download = "wget -q -O " + common.shell_quote(zip) + " --timeout=90 " + common.shell_quote(FLOWSEAL_STRATEGIES_ZIP);
        download_ok = shell_command(download) && file_nonempty(zip);
    }
    if (!download_ok)
        return { success: false, error: "Flowseal archive download failed", fallback: cached() };
    if (!shell_command("unzip -oq " + common.shell_quote(zip) + " -d " + common.shell_quote(FLOWSEAL_WORK_DIR)))
        return { success: false, error: "Flowseal archive extraction failed", fallback: cached() };

    let files = common.command_output("find " + common.shell_quote(base) + " -type f -name 'general*.bat' ! -name 'general (ALT5).bat' -print");
    let strategies = [];
    for (let path in split(as_string(files), "\n")) {
        path = trim(path);
        if (path == "") continue;
        let parsed = parse_file(path);
        push(strategies, parsed != null ? parsed : {
            id: "flowseal_rejected_" + slug(file_name(path)),
            name: "Flowseal " + file_name(path),
            engine: "zapret",
            source: path,
            compatible: false,
            rejection_reason: "Unsupported, unsafe or invalid strategy arguments"
        });
    }
    if (length(strategies) == 0)
        return { success: false, error: "No Flowseal strategy candidates found", fallback: cached() };

    let result = {
        source_url: FLOWSEAL_STRATEGIES_ZIP,
        source_ref: "main",
        imported_at: time(),
        strategies: strategies,
        success: true,
        fallback: null
    };
    common.ensure_dir("/etc/tachyon");
    if (!common.write_json_file(FLOWSEAL_CACHE, result))
        return { success: false, error: "Failed to save Flowseal strategy cache", fallback: result };
    return result;
}

function load(refresh) {
    let result = import_flowseal(refresh === true);
    if (result != null && result.success === false) {
        let fallback = result.fallback;
        if (fallback != null) {
            fallback.success = false;
            fallback.error = result.error;
            fallback.fallback = true;
            return fallback;
        }
        return result;
    }
    return result == null ? { source_url: "fallback", source_ref: "builtin", strategies: [], success: false, error: "Flowseal import unavailable" } : result;
}

return {
    load: load,
    parse_file: parse_file,
    import_flowseal: import_flowseal,
    FLOWSEAL_STRATEGIES_ZIP: FLOWSEAL_STRATEGIES_ZIP
};
