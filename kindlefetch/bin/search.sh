#!/bin/sh

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

    i=$((end))
    while [ "$i" -ge "$start" ]; do
        book_info="$(echo "$books" | awk -v i=$i 'BEGIN{RS="\\{"; FS="\\}"} NR==i+2{print $1}')"

        title="$(get_json_value "$book_info" "title")"
        author="$(get_json_value "$book_info" "author")"
        format="$(get_json_value "$book_info" "format")"
        description="$(get_json_value "$book_info" "description")"

        if [ "$COMPACT_OUTPUT" != true ]; then
            printf "%2d. %s\n" "$((i+1))" "$title"
            [ -n "$description" ] && [ "$description" != "null" ] && echo "    $description"
            echo ""
        else
            printf "%2d. %s by %s in %s format\n" \
                "$((i+1))" "$title" "$author" "$format"
            echo ""
        fi

        i=$((i - 1))
    done

    local items_on_page=$(( end - start + 1 ))

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
    if [ -f "$SCRIPT_DIR"/tmp/current_filter_params ]; then
        filters=$(cat "$SCRIPT_DIR/tmp/current_filter_params")
    fi
    
    local encoded_query=$(echo "$query" | sed 's/ /+/g')
    local search_url="$ANNAS_URL/search?page=${page}&q=${encoded_query}${filters}"
    local html_content
    html_content="$(curl -s -A "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36" "$search_url")"
    
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
    
    local books="$(echo "$html_content" | awk -v base_url="$ANNAS_URL" '
        BEGIN {
            RS = "href=\"/md5/"
            print "["
            count = 0
        }
        NR > 1 {
            title = ""; author = ""; md5 = ""; format = ""; description = ""; tags = ""

            # md5 is at the very start of each record (before the closing quote)
            if (match($0, /^[a-f0-9]{32}/)) {
                md5 = substr($0, RSTART, RLENGTH)
            }
            if (md5 == "") next

            # Title: text immediately after the anchor-opener md5"[^>]*>
            # Title links have the book name here; thumbnail links only have whitespace then <img>
            s = $0
            if (match(s, /^[a-f0-9]{32}"[^>]*>/)) {
                s = substr(s, RSTART + RLENGTH)
                if (match(s, /[^<]+/)) {
                    title = substr(s, RSTART, RLENGTH)
                    gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", title)
                }
            }
            if (title == "") next

            # author: text that follows the icon-[mdi--user-edit] span
            s = $0
            if (match(s, /icon-\[mdi--user-edit\]/)) {
                s = substr(s, RSTART + RLENGTH)
                # skip to end of the span tag (self-closing /> or separate </span>)
                if (match(s, /\/>|<\/span>/)) {
                    s = substr(s, RSTART + RLENGTH)
                    if (match(s, /[^<]+/)) {
                        author = substr(s, RSTART, RLENGTH)
                        gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", author)
                    }
                }
            }

            # tags/sources: full text of the font-semibold div (contains format, sources like lgli/zlib, language, etc.)
            s = $0
            if (match(s, /font-semibold[^>]*>/)) {
                s = substr(s, RSTART + RLENGTH)
                # collect everything up to the closing </div>
                if (match(s, /<\/div>/)) {
                    div_content = substr(s, 1, RSTART - 1)
                    # strip inner HTML tags
                    gsub(/<[^>]*>/, " ", div_content)
                    # remove "Save" button text and beyond
                    if (match(div_content, /Save/)) {
                        div_content = substr(div_content, 1, RSTART - 1)
                    }
                    gsub(/[ \t\r\n]+/, " ", div_content)
                    gsub(/^[ ]+|[ ]+$/, "", div_content)
                    tags = div_content
                    # first · separated field is the file format
                    n = split(tags, parts, " · ")
                    if (n >= 1) {
                        format = parts[1]
                        gsub(/^[ ]+|[ ]+$/, "", format)
                    }
                }
            }

            # description: div[@class="relative"] > div[class contains "line-clamp"]
            s = $0
            if (match(s, /class="relative"/)) {
                s = substr(s, RSTART + RLENGTH)
                if (match(s, /line-clamp[^>]*>/)) {
                    s = substr(s, RSTART + RLENGTH)
                    if (match(s, /<\/div>/)) {
                        desc_content = substr(s, 1, RSTART - 1)
                        gsub(/<[^>]*>/, " ", desc_content)
                        gsub(/&[#a-zA-Z0-9]+;/, "", desc_content)
                        gsub(/[ \t\r\n]+/, " ", desc_content)
                        gsub(/^[ ]+|[ ]+$/, "", desc_content)
                        description = desc_content
                    }
                }
            }
            # fall back to tags when no description text found
            if (description == "") description = tags

            # escape double quotes for JSON
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
    
    echo "$books" > "$TMP_DIR"/search_results.json

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
                if echo "$page_number" | grep -qE '^[0-9]+$'; then
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
                if echo "$choice" | grep -qE '^[0-9]+$'; then
                    local start=$(( (current_page - 1) * RESULTS_PER_PAGE ))
                    local end=$(( start + RESULTS_PER_PAGE - 1 ))
                    [ "$end" -ge "$count" ] && end=$((count - 1))
                    local items_on_page=$(( end - start + 1 ))

                    if [ "$choice" -ge "$((start+1))" ] && [ "$choice" -le "$((end+1))" ]; then
                        absolute_index=$(( choice - 1 ))

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
                                        if ! lgli_download "$choice"; then
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
                                            if ! zlib_download "$choice"; then
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
                                                    read -s -r zlib_password
                                                    echo

                                                    if zlib_login "$zlib_email" "$zlib_password"; then
                                                        ZLIB_AUTH=true
                                                        save_config

                                                        printf "\n\nProceeding with zlib..."
                                                        if ! zlib_download "$choice"; then
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
                        echo "Invalid selection (must be between $((start+1)) and $((end+1)))"
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