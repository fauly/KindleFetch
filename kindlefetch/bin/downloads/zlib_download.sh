#!/bin/sh

zlib_download() {
    local index="$1"
    local tmp_dir="$SCRIPT_DIR/tmp"
    mkdir -p "$tmp_dir"
    local md5_page_tmp="$tmp_dir/zlib_md5_page_$$.html"
    local md5_headers_tmp="$tmp_dir/zlib_md5_headers_$$.txt"
    local md5_curl_err="$tmp_dir/zlib_md5_curl_$$.log"
    local browser_ua="${ZLIB_BROWSER_UA:-Mozilla/5.0 (Windows NT 10.0; Win64; x64)}"
    
    if [ ! -f "$TMP_DIR/search_results.json" ]; then
        echo "No search results found" >&2
        return 1
    fi
    
    local book_info="$(awk -v i="$index" 'BEGIN{RS="\\{"; FS="\\}"} NR==i+2{print $1}' "$TMP_DIR"/search_results.json)"
    if [ -z "$book_info" ]; then
        echo "Invalid book selection" >&2
        return 1
    fi
    
    local md5="$(get_json_value "$book_info" "md5")"

    local zlib_format="$(get_json_value "$book_info" "format" | tr '[:upper:]' '[:lower:]' | tr -d '\r\n')"
    log "INFO" "zlib_download start index=$index md5=$md5 format=$zlib_format title='$title'"

    local md5_result="$("$CURL_BIN" $CURL_INSECURE -s -L -b "$ZLIB_COOKIES_FILE" \
        -A "$browser_ua" -D "$md5_headers_tmp" -o "$md5_page_tmp" \
        -w "%{url_effective} %{http_code}" "$ZLIB_URL/md5/$md5" 2>"$md5_curl_err")"
    local http_code="${md5_result##* }"
    local final_url="${md5_result% *}"
    log "INFO" "zlib md5 fetch final_url='$final_url' http_code=$http_code curl_err_exists=$( [ -s "$md5_curl_err" ] && echo yes || echo no )"

    local book_id="$(echo "$final_url" | sed -n 's#.*/book/\([0-9][0-9]*\)/[a-z0-9]\+#\1#p')"
    local book_hash="$(echo "$final_url" | sed -n 's#.*/book/[0-9][0-9]*/\([a-z0-9]\+\).*#\1#p')"
    local book_slug="$(echo "$final_url" | sed -n 's#.*/book/\([^/?#]\+\).*#\1#p')"

    local ddl=""
    local title="$(get_json_value "$book_info" "title" | tr -d '\r\n')"
    local ext="$(echo "$zlib_format" | sed 's/ .*//')"

    if [ -n "$book_id" ] && [ -n "$book_hash" ]; then
        response="$("$CURL_BIN" $CURL_INSECURE -s -b "$ZLIB_COOKIES_FILE" \
            -H "Accept: application/json" \
            -H "User-Agent: $browser_ua" \
            "$ZLIB_URL/eapi/book/$book_id/$book_hash/file")"
        ddl="$(get_json_value "$response" "downloadLink" | sed 's#\\\/##g' | tr -d '\r\n')"
        if [ -z "$ext" ]; then
            ext="$(get_json_value "$response" "extension" | tr -d '\r\n')"
        fi
        log "INFO" "zlib API response parsed ddl='$ddl' ext='$ext'"
    elif [ -n "$book_slug" ]; then
        ddl="$(grep -oE 'href=\"(/dl/[^\"]+)\"' "$md5_page_tmp" | sed 's/href=\"//' | sed 's/\"$//' | head -n1)"
        if [ -n "$ddl" ]; then
            ddl="$ZLIB_URL$ddl"
            if [ -z "$ext" ]; then
                ext="bin"
            fi
        fi
    fi

    if [ -z "$ddl" ]; then
        if [ "$http_code" = "503" ] || grep -qi 'Checking your browser\|c_token=\|Wait a moment, checking your browser\|Cookies are required' "$md5_page_tmp" 2>/dev/null; then
            log "ERROR" "Z-Library blocking request with browser challenge (HTTP $http_code) for md5=$md5 final_url='$final_url'"
            log_page_snippet "zlib_md5_page" "$md5_page_tmp"
        else
            log "ERROR" "Unexpected Z-Library md5 page response (HTTP $http_code) for md5=$md5 final_url='$final_url'"
            log_page_snippet "zlib_md5_page" "$md5_page_tmp"
        fi
        log "ERROR" "Failed to extract book info from URL: $final_url"
        if [ "$DEBUG_MODE" != "true" ]; then
            rm -f "$md5_page_tmp" "$md5_headers_tmp" "$md5_curl_err" >/dev/null 2>&1 || true
        fi
        return 1
    fi



    if [ "${AUTO_CONFIRM:-false}" = "true" ]; then
        confirm="n"
    else
        printf '\nDo you want to change filename? [y/N]: '
        read -r confirm
    fi
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if [ "${AUTO_CONFIRM:-false}" = "true" ]; then
            custom_filename=""
        else
            printf '\nEnter your custom filename: '
            read -r custom_filename
        fi
        if [ -n "$custom_filename" ]; then
            local title="$(sanitize_filename "$custom_filename" | tr -d ' ')"
        else
            echo "Invalid filename. Proceeding with original filename."
        fi
    else
        echo "Proceeding with original filename."
    fi

    # Probe the download URL headers (follow redirects) to capture content-type and length
    local dl_headers_tmp="$tmp_dir/zlib_dl_headers_$$.txt"
    local dl_curl_err="$tmp_dir/zlib_dl_curl_$$.log"
    "$CURL_BIN" $CURL_INSECURE -s -L -D "$dl_headers_tmp" -o /dev/null -w "%{http_code}" "$ddl" 2>"$dl_curl_err" >/dev/null 2>&1 || true
    local file_size="$(grep -i '^Content-Length:' "$dl_headers_tmp" 2>/dev/null | awk '{print $2}' | tr -d '\r' | awk '{ if ($1+0>0) printf "%.2f MB\n", $1/1048576; else print "unknown" }' )"
    log_page_snippet "zlib_dl_headers" "$dl_headers_tmp"
    local filename="$(sanitize_filename "${title}.${ext}")"
    local filename="${filename:-book.bin}"
    
    if [ ! -w "$KINDLE_DOCUMENTS" ]; then
        log "ERROR" "No write permission in $KINDLE_DOCUMENTS"
        echo "No write permission in $KINDLE_DOCUMENTS" >&2
        return 1
    fi

    if [ "$CREATE_SUBFOLDERS" = "true" ]; then
        local book_folder="$KINDLE_DOCUMENTS/$filename"
        if ! mkdir -p "$book_folder"; then
            echo "Failed to create folder '$book_folder'" >&2
            return 1
        fi
        local final_location="$book_folder/$filename"
    else
        local final_location="$KINDLE_DOCUMENTS/$filename"
    fi

    if [ -e "$final_location" ] && [ ! -w "$final_location" ]; then
        echo "No permission to overwrite $final_location" >&2
        return 1
    fi

    printf '\nDownloading:\n'
    printf "\nBook: $title\nExtension: $ext\nFile size: $file_size\nMD5: $md5\n"
    printf "\nProgress (Press Ctrl + c to stop):\n"

    log "INFO" "Starting download from ddl='$ddl' to '$final_location'"
    local dl_verbose_tmp="$tmp_dir/zlib_dl_verbose_$$.log"
    DOWNLOAD_RETRIES="${DOWNLOAD_RETRIES:-3}"
    DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-120}"
    attempt=1
    dl_http_code=""
    while [ "$attempt" -le "$DOWNLOAD_RETRIES" ]; do
        log "INFO" "Download attempt $attempt/$DOWNLOAD_RETRIES for md5=$md5"
        dl_http_code="$("$CURL_BIN" $CURL_INSECURE -L -b "$ZLIB_COOKIES_FILE" -s -S -m "$DOWNLOAD_TIMEOUT" -w "%{http_code}" -o "$final_location" "$ddl" 2>"$dl_verbose_tmp")"
        if [ "$dl_http_code" = "200" ]; then
            log "INFO" "Download successful md5=$md5 saved to $final_location size=$file_size"
            echo "\nDownload successful!"
            echo "Saved to: $final_location"
            if [ "$DEBUG_MODE" != "true" ]; then
                rm -f "$md5_page_tmp" "$md5_headers_tmp" "$md5_curl_err" "$dl_headers_tmp" "$dl_curl_err" "$dl_verbose_tmp" >/dev/null 2>&1 || true
            else
                mv -f "$md5_page_tmp" "$SCRIPT_DIR/tmp/zlib_md5_page.html" 2>/dev/null || true
                mv -f "$md5_headers_tmp" "$SCRIPT_DIR/tmp/zlib_md5_headers.txt" 2>/dev/null || true
                mv -f "$dl_headers_tmp" "$SCRIPT_DIR/tmp/dl_headers.txt" 2>/dev/null || true
                mv -f "$dl_verbose_tmp" "$SCRIPT_DIR/tmp/dl_verbose.txt" 2>/dev/null || true
            fi
            return 0
        fi
        log "WARN" "Download attempt $attempt failed md5=$md5 http_code=$dl_http_code"
        [ -f "$dl_verbose_tmp" ] && sed -n '1,240p' "$dl_verbose_tmp" | sed 's/^/    /' >> "$LOG_FILE" || true
        # Remove any partial file before retrying
        [ -f "$final_location" ] && rm -f "$final_location" || true
        if [ "$attempt" -lt "$DOWNLOAD_RETRIES" ]; then
            sleep $((attempt * 5))
            attempt=$((attempt + 1))
            continue
        else
            log "ERROR" "Download failed after $DOWNLOAD_RETRIES attempts md5=$md5 last_http_code=$dl_http_code"
            echo "Download failed." >&2
            if [ "$DEBUG_MODE" != "true" ]; then
                rm -f "$md5_page_tmp" "$md5_headers_tmp" "$md5_curl_err" "$dl_headers_tmp" "$dl_curl_err" "$dl_verbose_tmp" >/dev/null 2>&1 || true
            fi
            return 1
        fi
    done
}