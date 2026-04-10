#!/bin/sh

change_dns () {
    RESOLV_FILE="/var/run/resolv.conf"
    
    if [ ! -f "$RESOLV_FILE" ]; then
        return 1
    fi

    sed -i '/^nameserver/d' "$RESOLV_FILE"

    echo "nameserver 1.1.1.1" >> "$RESOLV_FILE"
    echo "nameserver 1.0.0.1" >> "$RESOLV_FILE"
}

# If SCRIPT_DIR not set, determine it. Then source optional repo config.
if [ -z "$SCRIPT_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
fi

if [ -f "$SCRIPT_DIR/../kindle_config.sh" ]; then
    . "$SCRIPT_DIR/../kindle_config.sh"
elif [ -f "$SCRIPT_DIR/kindle_config.sh" ]; then
    . "$SCRIPT_DIR/kindle_config.sh"
elif [ -f "./kindle_config.sh" ]; then
    . "./kindle_config.sh"
fi

# Centralized logging helper
# Writes timestamped entries to LOG_FILE. Defaults to $TMP_DIR/kindlefetch.log
LOG_FILE="${LOG_FILE:-${TMP_DIR:-/tmp}/kindlefetch.log}"
# Defaults (can be overridden in kindle_config.sh or environment)
DEBUG_MODE="${DEBUG_MODE:-false}"
# When set to "true", skip interactive prompts and assume defaults (useful for automated testing)
AUTO_CONFIRM="${AUTO_CONFIRM:-true}"
# Default Kindle documents path
KINDLE_DOCUMENTS="${KINDLE_DOCUMENTS:-/mnt/us/documents}"
# Download retry settings
DOWNLOAD_RETRIES="${DOWNLOAD_RETRIES:-3}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-180}"

ensure_log_dir() {
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" 2>/dev/null || :
    fi
}

log() {
    ensure_log_dir
    local level="$1"; shift || true
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date)"
    echo "$ts [$level] $msg" >> "$LOG_FILE"
}

# Append interesting snippets from an HTML/headers file to the log (not full page)
log_page_snippet() {
    local tag="$1"; shift || true
    local file="$1"; shift || true
# Centralized logging helper
# Writes timestamped entries to LOG_FILE. Defaults to $TMP_DIR/kindlefetch.log
    [ -f "$file" ] || return 0
    ensure_log_dir
    echo "---- $tag $(date '+%Y-%m-%dT%H:%M:%S%z') ----" >> "$LOG_FILE"
    grep -E 'Checking your browser|c_token=|href="/dl/|Content-Type:|Content-Length:|Location:' "$file" 2>/dev/null | sed 's/^/    /' >> "$LOG_FILE" || true
    echo "---- end $tag ----" >> "$LOG_FILE"
}

load_config() {
    eval "$(base64 -d "$LINK_CONFIG_FILE")"
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        first_time_setup
    fi
}

refresh_curl_security_settings() {
    [ -z "$INSECURE_TLS" ] && INSECURE_TLS=true
    if [ "$INSECURE_TLS" = "true" ]; then
        CURL_INSECURE="--insecure"
    else
        CURL_INSECURE=""
    fi
}

normalize_url() {
    local raw_url="$1"
    local normalized_url

    normalized_url=$(printf "%s" "$raw_url" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s#/*$##')
    [ -z "$normalized_url" ] && {
        echo ""
        return 0
    }

    case "$normalized_url" in
        http://*|https://*)
            ;;
        *)
            normalized_url="https://$normalized_url"
            ;;
    esac

    echo "$normalized_url"
}

is_http_url() {
    case "$1" in
        http://*|https://*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

load_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "Version file wasn't found!"
        sleep 2
        echo "Creating version file"
        sleep 2
        get_version
    fi
}

sanitize_filename() {
    echo "$1" | sed -e 's/[^[:alnum:]\._-]/_/g' -e 's/ /_/g'
}

get_json_value() {
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"/\1/" || \
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*[^,}]*" | sed "s/\"$2\"[[:space:]]*:[[:space:]]*\([^,}]*\)/\1/"
}

ensure_config_dir() {
    local config_dir="$(dirname "$CONFIG_FILE")"
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi
}

cleanup() {
    rm -f "$TMP_DIR"/kindle_books.list \
          "$TMP_DIR"/kindle_folders.list \
          "$TMP_DIR"/search_results.json \
          "$TMP_DIR"/last_search_*
    rm -f "$SCRIPT_DIR/tmp/current_filters" \
          "$SCRIPT_DIR/tmp/current_filter_params"
}

get_version() {
    local api_response="$("$CURL_BIN" $CURL_INSECURE -s -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/justrals/KindleFetch/commits")" || {
        echo "Failed to fetch version from GitHub API" >&2
        echo "unknown"
        return
    }

    local latest_sha="$(echo "$api_response" | grep -m1 '"sha":' | cut -d'"' -f4 | cut -c1-7)"
    
    echo "$latest_sha" > "$VERSION_FILE"
    load_version
}

check_for_updates() {
    local current_sha="$(load_version)"
    
    local latest_sha="$("$CURL_BIN" $CURL_INSECURE -s -H "Accept: application/vnd.github.v3+json" \
        -H "Cache-Control: no-cache" \
        "https://api.github.com/repos/justrals/KindleFetch/commits?per_page=1" | \
        grep -oE '"sha": "[0-9a-f]+"' | head -1 | cut -d'"' -f4 | cut -c1-7)"
    
    if [ -n "$latest_sha" ] && [ "$current_sha" != "$latest_sha" ]; then
        UPDATE_AVAILABLE=true
        return 0
    else
        return 1
    fi
}

save_config() {
    {
        echo "KINDLE_DOCUMENTS=\"$KINDLE_DOCUMENTS\""
        echo "CREATE_SUBFOLDERS=\"$CREATE_SUBFOLDERS\""
        echo "DEBUG_MODE=\"$DEBUG_MODE\""
        echo "AUTO_CONFIRM=\"$AUTO_CONFIRM\""
        echo "DOWNLOAD_RETRIES=\"$DOWNLOAD_RETRIES\""
        echo "DOWNLOAD_TIMEOUT=\"$DOWNLOAD_TIMEOUT\""
        echo "LOG_FILE=\"$LOG_FILE\""
        echo "COMPACT_OUTPUT=\"$COMPACT_OUTPUT\""
        echo "ENFORCE_DNS=\"$ENFORCE_DNS\""
        echo "ZLIB_AUTH=\"$ZLIB_AUTH\""
        echo "ZLIB_USERNAME=\"$ZLIB_USERNAME\""
        echo "RESULTS_PER_PAGE=\"$RESULTS_PER_PAGE\""
        echo "ANNAS_URL=\"$ANNAS_URL\""
        echo "LGLI_URL=\"$LGLI_URL\""
        echo "ZLIB_URL=\"$ZLIB_URL\""
        echo "INSECURE_TLS=\"$INSECURE_TLS\""
    } > "$CONFIG_FILE"
}

zlib_login() {
    local zlib_login="$1"
    local zlib_password="$2"

    printf '\nLogging in to Z-Library...'

    local response="$("$CURL_BIN" $CURL_INSECURE -s -L -c "$ZLIB_COOKIES_FILE" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Accept: application/json" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        -X POST -d "email=$zlib_login&password=$zlib_password" \
        "$ZLIB_URL/eapi/user/login")"

    local zlib_username="$(get_json_value "$response" "name" | tr -d '\r\n')"

    if [ -n "$zlib_username" ]; then
        printf "\nSuccessfully logged in as $zlib_username!"
        ZLIB_USERNAME="$zlib_username"
        sleep 2
    else
        printf "\nLogin failed." >&2
        printf "\n$response" | head -n1
        sleep 2
        return 1
    fi
}

find_working_url() {
    for url in "$@"; do
         code=$("$CURL_BIN" $CURL_INSECURE -s -o /dev/null -w '%{http_code}' \
             --max-time 8 -L "$url")

        [ "$code" = "000" ] && continue
        [ "$code" -ge 500 ] && continue

        echo "$url"
        return 0
    done
    return 1
}

find_working_zlib_url() {
    for url in "$@"; do
        local normalized_url
        local code
        local probe_body
        local probe_headers
        local probe_result
        local http_code
        local browser_ua="${ZLIB_BROWSER_UA:-Mozilla/5.0 (Windows NT 10.0; Win64; x64)}"

        normalized_url=$(normalize_url "$url")
        [ -z "$normalized_url" ] && continue

        # Quick connectivity check on the site root
        code=$("$CURL_BIN" $CURL_INSECURE -s -o /dev/null -w '%{http_code}' --max-time 8 -L "$normalized_url")
        [ "$code" = "000" ] && continue
        [ "$code" -ge 500 ] && continue

        # Probe an md5 page and detect JS challenge pages that require a real browser
        probe_body="$SCRIPT_DIR/tmp/zlib_probe.html"
        probe_headers="$SCRIPT_DIR/tmp/zlib_probe_headers.txt"
        mkdir -p "$SCRIPT_DIR/tmp"

        probe_result=$("$CURL_BIN" $CURL_INSECURE -s -L -D "$probe_headers" -o "$probe_body" -A "$browser_ua" -w '%{http_code}' --max-time 10 "$normalized_url/md5/d41d8cd98f00b204e9800998ecf8427e")
        http_code="$probe_result"

        [ "$http_code" = "000" ] && continue
        [ "$http_code" -ge 500 ] && continue

        # If page contains known JS challenge markers, skip this mirror
        if grep -qi 'Checking your browser\|c_token=\|Wait a moment, checking your browser\|Cookies are required' "$probe_body" 2>/dev/null; then
            continue
        fi

        # Mirror appears reachable and not presenting a browser challenge
        echo "$normalized_url"
        return 0
    done
    return 1
}