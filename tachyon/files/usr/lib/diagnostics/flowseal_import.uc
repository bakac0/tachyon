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
        if (token == "" || unsupported_token(token))
            continue;
        token = replace(token, "%BIN%", FLOWSEAL_FAKE_DIR + "/");
        if (index(token, "\\") >= 0)
            token = replace(token, "\\", "/");
        push(output, token);
    }
    return join(output, " ");
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
    return {
        id: "flowseal_import_" + slug(name),
        name: "Flowseal " + name,
        engine: "zapret",
        args: join(args, " --new "),
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
    if (!shell_command(download) || !file_nonempty(zip))
        download = "wget -q -O " + common.shell_quote(zip) + " --timeout=90 " + common.shell_quote(FLOWSEAL_STRATEGIES_ZIP);
    if (!shell_command(download) || !file_nonempty(zip))
        return cached();
    if (!shell_command("unzip -oq " + common.shell_quote(zip) + " -d " + common.shell_quote(FLOWSEAL_WORK_DIR)))
        return cached();

    let files = common.command_output("find " + common.shell_quote(base) + " -type f -name 'general*.bat' ! -name 'general (ALT5).bat' -print");
    let strategies = [];
    for (let path in split(as_string(files), "\n")) {
        path = trim(path);
        if (path == "") continue;
        let parsed = parse_file(path);
        if (parsed != null)
            push(strategies, parsed);
    }
    if (length(strategies) == 0)
        return cached();

    let result = {
        source_url: FLOWSEAL_STRATEGIES_ZIP,
        source_ref: "main",
        imported_at: time(),
        strategies: strategies
    };
    common.ensure_dir("/etc/tachyon");
    common.write_json_file(FLOWSEAL_CACHE, result);
    return result;
}

function load(refresh) {
    let result = import_flowseal(refresh === true);
    return result == null ? { source_url: "fallback", source_ref: "builtin", strategies: [] } : result;
}

return {
    load: load,
    parse_file: parse_file,
    import_flowseal: import_flowseal,
    FLOWSEAL_STRATEGIES_ZIP: FLOWSEAL_STRATEGIES_ZIP
};
