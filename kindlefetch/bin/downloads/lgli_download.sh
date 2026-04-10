#!/bin/sh

lgli_download() {
    local index="$1"
    
    if [ ! -f "$TMP_DIR/search_results.json" ]; then
        echo "No search results found" >&2
        return 1
    fi
    
    local book_info="$(awk -v i="$index" 'BEGIN{RS="\\{"; FS="\\}"} NR==i+2{print $1}' "$TMP_DIR"/search_results.json)"
    if [ -z "$book_info" ]; then
        echo "Invalid book selection"
        return 1
    fi
    
    local md5="$(get_json_value "$book_info" "md5")"
    local title="$(get_json_value "$book_info" "title")"
    local format="$(get_json_value "$book_info" "format")"
    
    log "INFO" "lgli_download start index=$index md5=$md5 title='$title' format=$format"
    printf "\nDownloading: $title"

    local clean_title="$(sanitize_filename "$title" | tr -d ' ')"

    printf '\nDo you want to change filename? [y/N]: '
    read -r confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        echo -n "Enter your custom filename: "
        read -r custom_filename
        if [ -n "$custom_filename" ]; then
            local clean_title="$(sanitize_filename "$custom_filename" | tr -d ' ')"
        else
            echo "Invalid filename. Proceeding with original filename."
        fi
    else
        echo "Proceeding with original filename."
    fi
    
    if [ ! -w "$KINDLE_DOCUMENTS" ]; then
        log "ERROR" "No write permission in $KINDLE_DOCUMENTS"
        echo "No write permission in $KINDLE_DOCUMENTS" >&2
        return 1
    fi

    if [ "$CREATE_SUBFOLDERS" = "true" ]; then
        local book_folder="$KINDLE_DOCUMENTS/$clean_title"
        if ! mkdir -p "$book_folder"; then
            echo "Failed to create folder '$book_folder'" >&2
            return 1
        fi
        local final_location="$book_folder/$clean_title.$format"
    else
        local final_location="$KINDLE_DOCUMENTS/$clean_title.$format"
    fi

    if [ -e "$final_location" ] && [ ! -w "$final_location" ]; then
        echo "No permission to overwrite $final_location" >&2
        return 1
    fi

    printf '\nFetching download page...\n'
    local tmp_dir="${SCRIPT_DIR}/tmp"
    mkdir -p "$tmp_dir"
    local lgli_page_tmp="$tmp_dir/lgli_page_$$.html"
    local lgli_curl_err="$tmp_dir/lgli_curl_$$.log"
    local lgli_content
    lgli_content="$("$CURL_BIN" $CURL_INSECURE -s -L "$LGLI_URL/ads.php?md5=$md5" 2>"$lgli_curl_err")" || {
        log "ERROR" "lgli fetch failed md5=$md5"
        echo "Failed to fetch book page" >&2
        [ -s "$lgli_curl_err" ] && sed -n '1,60p' "$lgli_curl_err" | sed 's/^/    /' >> "$LOG_FILE" || true
        rm -f "$lgli_curl_err" >/dev/null 2>&1 || true
        return 1
    }
    printf "%s" "$lgli_content" > "$lgli_page_tmp"

    local download_link
    download_link="$(echo "$lgli_content" | grep -o -m 1 'href="[^"]*get\.php[^"]*"' | cut -d'"' -f2)"
    if [ -z "$download_link" ]; then
        log "ERROR" "lgli parse failed for md5=$md5"
        echo "Failed to parse download link" >&2
        log_page_snippet "lgli_page" "$lgli_page_tmp"
        rm -f "$lgli_page_tmp" "$lgli_curl_err" >/dev/null 2>&1 || true
        return 1
    fi

    local download_url="$LGLI_URL/$download_link"
    echo "Downloading from: $download_url"
    
    printf '\nProgress (Press Ctrl + c to stop):\n'

    log "INFO" "lgli downloading from $download_url to $final_location"
    local dl_verbose_tmp="$tmp_dir/lgli_dl_verbose_$$.log"
    local dl_http_code
    dl_http_code="$("$CURL_BIN" $CURL_INSECURE -L -s -S -w "%{http_code}" -o "$final_location" "$download_url" 2>"$dl_verbose_tmp")"
    if [ "$dl_http_code" = "200" ]; then
        log "INFO" "lgli download successful md5=$md5 saved to $final_location"
        printf '\nDownload successful!\n'
        echo "Saved to: $final_location"
        rm -f "$lgli_page_tmp" "$lgli_curl_err" "$dl_verbose_tmp" >/dev/null 2>&1 || true
        return 0
    else
        log "ERROR" "lgli download failed md5=$md5 http_code=$dl_http_code"
        [ -f "$dl_verbose_tmp" ] && sed -n '1,240p' "$dl_verbose_tmp" | sed 's/^/    /' >> "$LOG_FILE" || true
        printf '\nDownload failed.' >&2
        rm -f "$lgli_page_tmp" "$lgli_curl_err" "$dl_verbose_tmp" >/dev/null 2>&1 || true
        return 1
    fi
}