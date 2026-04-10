#!/bin/sh

shorten_text() {
    printf "%s" "$1" | tr '\n' ' ' | awk -v max_len="$2" '
        {
            gsub(/[[:space:]]+/, " ")
            gsub(/^ | $/, "")
            if (length($0) <= max_len) {
                print $0
            } else if (max_len > 3) {
                print substr($0, 1, max_len - 3) "..."
            } else {
                print substr($0, 1, max_len)
            }
        }'
}

extract_year() {
    printf "%s\n" "$1" | awk '
        match($0, /[12][0-9][0-9][0-9]/) {
            print substr($0, RSTART, RLENGTH)
            exit
        }'
}

is_positive_integer() {
    case "$1" in
        ''|*[!0-9]*)
            return 1
            ;;
        0*)
            [ "$1" = "0" ] && return 0
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

normalize_input() {
    printf "%s" "$1" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

display_books() {
    clear
    echo -e "
  _____                     _     
 / ____|                   | |    
| (___   ___  __ _ _ __ ___| |__  
 \___ \ / _ \/ _\` | '__/ __| '_ \\ 
 ____) |  __/ (_| | | | (__| | | |
|_____/ \___|\__,_|_|  \___|_| |_|
"
    echo "--------------------------------"
    echo ""

    local books="$1"
    local page="$2"
    local has_prev="$3"
    local has_next="$4"
    local last_page="$5"

    local count
    count="$(echo "$books" | grep -o '"title":' | wc -l)"

    local start=$(( (page - 1) * RESULTS_PER_PAGE ))
    local end=$(( start + RESULTS_PER_PAGE - 1 ))
    [ "$end" -ge "$count" ] && end=$((count - 1))
    local items_on_page=$(( end - start + 1 ))

    local display_index=1
    while [ "$display_index" -le "$items_on_page" ]; do
        local absolute_index=$(( start + display_index - 1 ))
        book_info="$(echo "$books" | awk -v i=$absolute_index 'BEGIN{RS="\\{"; FS="\\}"} NR==i+2{print $1}')"

        title="$(get_json_value "$book_info" "title")"
        author="$(get_json_value "$book_info" "author")"
        format="$(get_json_value "$book_info" "format")"
        description="$(get_json_value "$book_info" "description")"
        tags="$(get_json_value "$book_info" "tags")"
        year="$(extract_year "$tags")"

        [ -z "$title" ] && title="Unknown title"
        [ -z "$author" ] && author="Unknown author"
        [ -z "$format" ] && format="Unknown format"

        local short_title
        local short_author
        local short_metadata
        local short_description
        short_title="$(shorten_text "$title" 58)"
        short_author="$(shorten_text "$author" 52)"
        if [ -n "$tags" ] && [ "$tags" != "null" ]; then
            short_metadata="$(shorten_text "$tags" 72)"
        elif [ -n "$year" ]; then
            short_metadata="$(shorten_text "Year: $year | Format: $format" 72)"
        else
            short_metadata="$(shorten_text "Format: $format" 72)"
        fi
        short_description="$(shorten_text "$description" 52)"

        printf "%2d. %s\n" "$display_index" "$short_title"
        printf "    Author: %s\n" "$short_author"
        printf "    Meta: %s\n" "$short_metadata"
        if [ -n "$description" ] && [ "$description" != "null" ]; then
            printf "    Desc: %s\n" "$short_description"
        fi
        echo "--------------------------------"

        display_index=$((display_index + 1))
    done

    echo "--------------------------------"
    echo ""
    echo "Page $page of $last_page"
    echo ""

    [ "$has_prev" = true ] && echo -n "p: Previous page | "
    echo -n "t[1-$last_page]: Select page | "
    [ "$has_next" = true ] && echo -n "n: Next page | "
    echo "1-$items_on_page: Select book | q: Quit"
    echo ""
}

search_books() {
    local query="$1"
    local page="${2:-1}"
    local tmp_dir="$SCRIPT_DIR/tmp"
    mkdir -p "$tmp_dir"
    local raw_html_tmp="$tmp_dir/annas_search_last_$$.html"
    local curl_stderr_tmp="$tmp_dir/search_curl_error_$$.log"
    local parsed_results_tmp="$tmp_dir/search_results_$$.json"
    
    if [ -z "$query" ]; then
        echo -n "Enter search query: "
        read -r query
        [ -z "$query" ] && {
            echo "Search query cannot be empty"
            return 1
        }
    fi
    
    echo "Searching for '$query' (page $page)..."

    local filters=""
    local active_annas_url=""
    if [ -f "$SCRIPT_DIR"/tmp/current_filter_params ]; then
        filters=$(cat "$SCRIPT_DIR/tmp/current_filter_params")
    fi

    active_annas_url=$(normalize_url "$ANNAS_URL")
    if ! is_http_url "$active_annas_url"; then
        active_annas_url=""
    fi
    if [ -z "$active_annas_url" ]; then
        active_annas_url=$(find_working_url $ANNAS_MIRROR_URLS)
        if [ -n "$active_annas_url" ]; then
            ANNAS_URL="$active_annas_url"
            save_config
        else
            echo "No working Anna's Archive mirror is configured."
            echo "Open Settings -> Change URLs, or run the Kindle test to inspect mirrors."
            echo "Press any key to continue..."
            read -n 1 -s
            return 1
        fi
    fi
    
    local encoded_query=$(echo "$query" | sed 's/ /+/g')
    local search_url="$active_annas_url/search?page=${page}&q=${encoded_query}${filters}"
    log "INFO" "search_books start query='$query' page=$page url='$search_url'"
    local html_content
    html_content="$("$CURL_BIN" $CURL_INSECURE -s -A "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36" "$search_url" 2>"$curl_stderr_tmp")"
    local curl_status=$?
    printf "%s" "$html_content" > "$raw_html_tmp"

    if [ "$curl_status" -ne 0 ] || [ -z "$html_content" ]; then
        echo "Search fetch failed for $search_url"
        log "ERROR" "search_books curl failed (status=$curl_status) for url='$search_url'"
        if [ -s "$curl_stderr_tmp" ]; then
            log "ERROR" "search curl stderr:"
            sed -n '1,60p' "$curl_stderr_tmp" | sed 's/^/    /' >> "$LOG_FILE" || true
        else
            log "ERROR" "curl exited with status $curl_status and returned no data."
        fi
        log_page_snippet "search_page" "$raw_html_tmp"
        echo "Debug: search log saved to $LOG_FILE"
        if [ "$DEBUG_MODE" != "true" ]; then
            rm -f "$raw_html_tmp" "$curl_stderr_tmp" "$parsed_results_tmp" >/dev/null 2>&1 || true
        fi
        echo "Press any key to continue..."
        read -n 1 -s
        return 1
    fi
    
    local last_page="$(echo "$html_content" | grep -o 'page=[0-9]\+"' | sort -t= -k2 -nr | head -1 | cut -d= -f2 | tr -d '"')"
    [ -z "$last_page" ] && last_page=1
    
    local has_prev=false
    [ "$page" -gt 1 ] && has_prev=true
    
    local has_next=false
    [ "$page" -lt "$last_page" ] && has_next=true

    echo "$query" > "$TMP_DIR"/last_search_query
    echo "$page" > "$TMP_DIR"/last_search_page
    echo "$last_page" > "$TMP_DIR"/last_search_last_page
    echo "$has_next" > "$TMP_DIR"/last_search_has_next
    echo "$has_prev" > "$TMP_DIR"/last_search_has_prev
    
    local books="$(echo "$html_content" | awk -v base_url="$active_annas_url" '
        function trim(value) {
            gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", value)
            return value
        }

        BEGIN {
            RS = "href=\"/md5/"
            print "["
            count = 0
        }
        NR > 1 {
            title = ""; author = ""; md5 = ""; format = ""; description = ""; tags = ""
            record = $0

            # Use fixed-width slicing instead of counted regexes for better awk portability.
            md5 = substr(record, 1, 32)
            if (length(md5) != 32) next
            if (md5 !~ /^[0-9a-f]+$/) next

            anchor_end = index(record, ">")
            if (anchor_end == 0) next
            s = substr(record, anchor_end + 1)
            title_end = index(s, "<")
            if (title_end <= 1) next
            title = trim(substr(s, 1, title_end - 1))
            if (title == "") next

            s = record
            author_pos = index(s, "icon-[mdi--user-edit]")
            if (author_pos > 0) {
                s = substr(s, author_pos + length("icon-[mdi--user-edit]"))
                span_end = index(s, "</span>")
                if (span_end > 0) {
                    s = substr(s, span_end + length("</span>"))
                    author_end = index(s, "<")
                    if (author_end > 1) {
                        author = trim(substr(s, 1, author_end - 1))
                    }
                }
            }

            s = record
            tags_pos = index(s, "text-gray-800 dark:text-slate-400 font-semibold")
            if (tags_pos == 0) {
                tags_pos = index(s, "dark:text-slate-400 font-semibold text-sm")
            }
            if (tags_pos > 0) {
                s = substr(s, tags_pos)
                div_open_end = index(s, ">")
                if (div_open_end > 0) {
                    s = substr(s, div_open_end + 1)
                    div_close = index(s, "</div>")
                    if (div_close > 0) {
                        div_content = substr(s, 1, div_close - 1)
                        gsub(/<[^>]*>/, " ", div_content)
                        if (match(div_content, /Save/)) {
                            div_content = substr(div_content, 1, RSTART - 1)
                        }
                        gsub(/[ \t\r\n]+/, " ", div_content)
                        tags = trim(div_content)
                        n = split(tags, parts, " · ")
                        if (n >= 2) {
                            format = trim(parts[2])
                        } else if (n >= 1) {
                            format = trim(parts[1])
                        }
                    }
                }
            }

            s = record
            relative_pos = index(s, "class=\"relative\"")
            if (relative_pos > 0) {
                s = substr(s, relative_pos)
                line_clamp_pos = index(s, "line-clamp")
                if (line_clamp_pos > 0) {
                    s = substr(s, line_clamp_pos)
                    desc_open_end = index(s, ">")
                    if (desc_open_end > 0) {
                        s = substr(s, desc_open_end + 1)
                        desc_close = index(s, "</div>")
                        if (desc_close > 0) {
                            desc_content = substr(s, 1, desc_close - 1)
                            gsub(/<[^>]*>/, " ", desc_content)
                            gsub(/&[#a-zA-Z0-9]+;/, "", desc_content)
                            gsub(/[ \t\r\n]+/, " ", desc_content)
                            description = trim(desc_content)
                        }
                    }
                }
            }
            if (description == "") description = tags

            gsub(/"/, "\\\"", title)
            gsub(/"/, "\\\"", author)
            gsub(/"/, "\\\"", description)
            gsub(/"/, "\\\"", tags)

            if (count > 0) printf ",\n"
            printf "  {\"author\": \"%s\", \"format\": \"%s\", \"md5\": \"%s\", \"title\": \"%s\", \"url\": \"%s/md5/%s\", \"description\": \"%s\", \"tags\": \"%s\"}", author, format, md5, title, base_url, md5, description, tags
            count++
        }
        END {
            print "\n]"
        }'
    )"
    
    echo "$books" > "$parsed_results_tmp"

    if ! echo "$books" | grep -q '"title":'; then
        echo "Search page downloaded, but no book entries were parsed."
        if grep -qi 'cloudflare\|captcha\|checking your browser' "$raw_html_tmp" 2>/dev/null; then
            echo "The response looked like a challenge page rather than search results."
        fi
        log "WARN" "search parsed 0 entries for query='$query' page=$page"
        log_page_snippet "search_page" "$raw_html_tmp"
        if [ "$DEBUG_MODE" = "true" ]; then
            mv -f "$raw_html_tmp" "$SCRIPT_DIR/tmp/annas_search_last.html" 2>/dev/null || true
            mv -f "$curl_stderr_tmp" "$SCRIPT_DIR/tmp/search_curl_error.log" 2>/dev/null || true
            mv -f "$parsed_results_tmp" "$SCRIPT_DIR/tmp/search_results.json" 2>/dev/null || true
        else
            rm -f "$raw_html_tmp" "$curl_stderr_tmp" "$parsed_results_tmp" >/dev/null 2>&1 || true
        fi
        echo "Press any key to continue..."
        read -n 1 -s
        return 1
    fi

    echo "$books" > "$TMP_DIR"/search_results.json
    # write parsed results to temporary debug file if requested
    if [ "$DEBUG_MODE" = "true" ]; then
        mv -f "$parsed_results_tmp" "$SCRIPT_DIR/tmp/search_results.json" 2>/dev/null || true
    else
        rm -f "$parsed_results_tmp" >/dev/null 2>&1 || true
    fi

    local parsed_count
    parsed_count=$(echo "$books" | grep -o '"title":' | wc -l | tr -d '[:space:]')
    log "INFO" "search_books complete query='$query' page=$page parsed_count=$parsed_count"

    # clean up temporary files unless DEBUG_MODE
    if [ "$DEBUG_MODE" != "true" ]; then
        rm -f "$raw_html_tmp" "$curl_stderr_tmp" >/dev/null 2>&1 || true
    fi

    while true; do
        local query="$(cat "$TMP_DIR"/last_search_query 2>/dev/null)"
        local current_page="$(cat "$TMP_DIR"/last_search_page 2>/dev/null || echo 1)"
        local last_page="$(cat "$TMP_DIR"/last_search_last_page 2>/dev/null || echo 1)"
        local has_next="$(cat "$TMP_DIR"/last_search_has_next 2>/dev/null || echo "false")"
        local has_prev="$(cat "$TMP_DIR"/last_search_has_prev 2>/dev/null || echo "false")"
        local books="$(cat "$TMP_DIR"/search_results.json 2>/dev/null)"
        local count="$(echo "$books" | grep -o '"title":' | wc -l)"

        display_books "$books" "$current_page" "$has_prev" "$has_next" "$last_page"
        
        echo -n "Enter choice: "
        read -r choice
        choice="$(normalize_input "$choice")"
        
        case "$choice" in
            [qQ])
                return 0
                ;;
            [pP])
                if [ "$has_prev" = true ]; then
                    new_page=$((current_page - 1))
                    echo "$new_page" > "$TMP_DIR"/last_search_page
                    has_prev="$([ "$new_page" -gt 1 ] && echo "true" || echo "false")"
                    has_next="$([ "$new_page" -lt "$last_page" ] && echo "true" || echo "false")"
                    echo "$has_prev" > "$TMP_DIR"/last_search_has_prev
                    echo "$has_next" > "$TMP_DIR"/last_search_has_next
                    continue
                else
                    echo "Already on first page"
                    sleep 2
                fi
                ;;
            [nN])
                if [ "$has_next" = true ]; then
                    new_page=$((current_page + 1))
                    echo "$new_page" > "$TMP_DIR"/last_search_page
                    has_prev="$([ "$new_page" -gt 1 ] && echo "true" || echo "false")"
                    has_next="$([ "$new_page" -lt "$last_page" ] && echo "true" || echo "false")"
                    echo "$has_prev" > "$TMP_DIR"/last_search_has_prev
                    echo "$has_next" > "$TMP_DIR"/last_search_has_next
                    continue
                else
                    echo "Already on last page"
                    sleep 2
                fi
                ;;
            t[0-9]*)
                page_number="${choice#t}"
                if is_positive_integer "$page_number"; then
                    if [ "$page_number" -ge 1 ] && [ "$page_number" -le "$last_page" ]; then
                        if [ "$page_number" -ne "$current_page" ]; then
                            echo "$page_number" > "$TMP_DIR"/last_search_page
                            has_prev="$([ "$page_number" -gt 1 ] && echo "true" || echo "false")"
                            has_next="$([ "$page_number" -lt "$last_page" ] && echo "true" || echo "false")"
                            echo "$has_prev" > "$TMP_DIR"/last_search_has_prev
                            echo "$has_next" > "$TMP_DIR"/last_search_has_next
                            continue
                        else
                            echo "You are already on page $current_page"
                            sleep 2
                        fi
                    else
                        echo "Page number out of range (1-$last_page)"
                        sleep 2
                    fi
                else
                    echo "Invalid input"
                    sleep 2
                fi
                ;;
            *)  
                if is_positive_integer "$choice"; then
                    local start=$(( (current_page - 1) * RESULTS_PER_PAGE ))
                    local end=$(( start + RESULTS_PER_PAGE - 1 ))
                    [ "$end" -ge "$count" ] && end=$((count - 1))
                    local items_on_page=$(( end - start + 1 ))

                    if [ "$choice" -ge 1 ] && [ "$choice" -le "$items_on_page" ]; then
                        absolute_index=$(( start + choice - 1 ))

                        book_info="$(awk -v i=$absolute_index \
                            'BEGIN{RS="\\{"; FS="\\}"} NR==i+2{print $1}' \
                            "$TMP_DIR"/search_results.json)"

                        local lgli_available=false
                        local zlib_available=false

                        if echo "$book_info" | grep -q "lgli"; then
                            lgli_available=true
                        fi
                        if echo "$book_info" | grep -q "zlib"; then
                            zlib_available=true
                        fi

                        while true; do
                            if [ "$lgli_available" = false ] && [ "$zlib_available" = false ]; then
                                echo "There are no available sources for this book right now."
                            fi

                            if [ "$lgli_available" = true ]; then
                                echo "1. lgli"
                            fi
                            if [ "$zlib_available" = true ]; then
                                if [ "$ZLIB_AUTH" = true ]; then
                                    echo "2. zlib"
                                else
                                    echo "2. zlib (Authentication required)"
                                fi
                            fi
                            echo "3. Cancel download"

                            echo -n "Choose source to proceed with: "
                            read -r source_choice

                            case "$source_choice" in
                                1)
                                    if [ "$lgli_available" = true ]; then
                                        echo "Proceeding with lgli..."
                                        if ! lgli_download "$absolute_index"; then
                                            echo "Download from lgli failed."
                                            sleep 2
                                        else
                                            break
                                        fi
                                    else
                                        echo "Invalid choice."
                                    fi
                                    ;;
                                2)
                                    if [ "$zlib_available" = true ]; then
                                        if [ "$ZLIB_AUTH" = true ]; then
                                            echo "Proceeding with zlib..."
                                            if ! zlib_download "$absolute_index"; then
                                                echo "Download from zlib failed."
                                                sleep 2
                                            else
                                                break
                                            fi
                                        else
                                            echo
                                            echo -n "Do you want to sign into your zlib account? [Y/n]: "
                                            read -r zlib_login_choice
                                            echo

                                            if [ "$zlib_login_choice" = "n" ] || [ "$zlib_login_choice" = "N" ]; then
                                                ZLIB_AUTH=false
                                                save_config
                                            else
                                                while true; do
                                                    echo -n "Zlib email: "
                                                    read -r zlib_email
                                                    echo -n "Zlib password: "
                                                    read -r zlib_password

                                                    if zlib_login "$zlib_email" "$zlib_password"; then
                                                        ZLIB_AUTH=true
                                                        save_config

                                                        printf "\n\nProceeding with zlib..."
                                                        if ! zlib_download "$absolute_index"; then
                                                            echo "Download from zlib failed."
                                                            sleep 2
                                                        else
                                                            break 2
                                                        fi
                                                    else
                                                        echo -n "Zlib login failed. Do you want to try again? [Y/n]: "
                                                        read -r zlib_login_retry_choice
                                                        echo
                                                        
                                                        if [ "$zlib_login_retry_choice" = "n" ] || [ "$zlib_login_retry_choice" = "N" ]; then
                                                            ZLIB_AUTH=false
                                                            save_config
                                                            break
                                                        fi
                                                    fi
                                                done
                                            fi
                                        fi
                                    else
                                        echo "Invalid choice."
                                    fi
                                    ;;
                                3)
                                    break
                                    ;;
                                *)
                                    echo "Invalid choice."
                                    ;;
                            esac
                        done

                        printf "\nPress any key to continue..."
                        read -n 1 -s
                    else
                        echo "Invalid selection (must be between 1 and $items_on_page)"
                        sleep 2
                    fi
                else
                    echo "Invalid input"
                    sleep 2
                fi
                ;;
        esac
    done
}