#!/bin/sh

# KindleFetch
# Made by justrals
# https://github.com/justrals/KindleFetch

# Variables
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CURL_BIN=${CURL_BIN:-curl}
if [ -x "$SCRIPT_DIR/curl" ]; then
    CURL_BIN="$SCRIPT_DIR/curl"
fi
CONFIG_FILE="$SCRIPT_DIR/kindlefetch_config"
LINK_CONFIG_FILE="$SCRIPT_DIR/link_config"
VERSION_FILE="$SCRIPT_DIR/.version"
ZLIB_COOKIES_FILE="$SCRIPT_DIR/zlib_cookies.txt"
TMP_DIR="/tmp"
BASE_DIR="/mnt/us"

UPDATE_AVAILABLE=false
CREATE_SUBFOLDERS=false
COMPACT_OUTPUT=false
RESULTS_PER_PAGE=10

# Default Z-Library mirror candidates (space-separated, tried in order)
ZLIB_MIRROR_URLS="https://z-library.gs https://1lib.sk https://z-lib.fm https://z-lib.gd https://z-lib.gl https://zliba.ru https://z-lib.sk"

# Check if running on a Kindle
if ! { [ -f "/etc/prettyversion.txt" ] || [ -d "/mnt/us" ] || pgrep "lipc-daemon" >/dev/null; }; then
    echo -n "This script must run on a Kindle device. Do you want to run it anyway? [y/N]: "
    read -r kindle_override_choice
    if [ "$kindle_override_choice" = "y" ] || [ "$kindle_override_choice" = "Y" ]; then
        :
    else
        exit 1
    fi
fi

# Script imports
. "$SCRIPT_DIR/downloads/zlib_download.sh"
. "$SCRIPT_DIR/downloads/lgli_download.sh"
. "$SCRIPT_DIR/filters.sh"
. "$SCRIPT_DIR/search.sh"
. "$SCRIPT_DIR/misc.sh"
. "$SCRIPT_DIR/local_books.sh"
. "$SCRIPT_DIR/update.sh"
. "$SCRIPT_DIR/setup.sh"
. "$SCRIPT_DIR/settings.sh"

check_for_updates
load_config
refresh_curl_security_settings

normalized_url=$(normalize_url "$ANNAS_URL")
[ -n "$normalized_url" ] && ANNAS_URL="$normalized_url"
normalized_url=$(normalize_url "$LGLI_URL")
[ -n "$normalized_url" ] && LGLI_URL="$normalized_url"
normalized_url=$(normalize_url "$ZLIB_URL")
[ -n "$normalized_url" ] && ZLIB_URL="$normalized_url"

if [ -z "$ANNAS_URL" ]; then
    probed_url=$(find_working_url $ANNAS_MIRROR_URLS)
    [ -n "$probed_url" ] && ANNAS_URL="$probed_url"
fi
if [ -z "$LGLI_URL" ]; then
    probed_url=$(find_working_url $LGLI_MIRROR_URLS)
    [ -n "$probed_url" ] && LGLI_URL="$probed_url"
fi
if [ -z "$ZLIB_URL" ]; then
    # Try to find a working mirror; prefer the configured ZLIB_URL if present.
    probed_url=$(find_working_zlib_url "$ZLIB_URL" $ZLIB_MIRROR_URLS)
    [ -n "$probed_url" ] && ZLIB_URL="$probed_url"
fi

save_config

main_menu() {
    if [ "${ENFORCE_DNS}" = true ];
    	then change_dns
    fi
    
    while true; do
        clear
        echo -e "
 _  ___           _ _      ______   _       _     
| |/ (_)         | | |    |  ____| | |     | |    
| ' / _ _ __   __| | | ___| |__ ___| |_ ___| |__  
|  < | | '_ \ / _\` | |/ _ \  __/ _ \ __/ __| '_ \\ 
| . \| | | | | (_| | |  __/ | |  __/ || (__| | | |
|_|\_\_|_| |_|\__,_|_|\___|_|  \___|\__\___|_| |_|
                                                
$(load_version) | https://github.com/justrals/KindleFetch
"
        if $UPDATE_AVAILABLE; then
            echo "Update available! Select option 6 to install."
            echo ""
        fi
        echo "1. Search and download books"
        echo "2. Filter search results"
        echo "3. List my books"
        echo "4. Settings"
        echo "q. Exit"
        if $UPDATE_AVAILABLE; then
            echo ""
            echo "6. Install update"
        fi
        echo ""
        echo -n "Choose option: "
        read -r choice
        
        case "$choice" in
            1)
                search_books
                ;;
            2)
                filters_menu
                ;;
            3)
                list_local_books
                ;;
            4)
                settings_menu
                ;;
            [qQ])
                cleanup
                exit 0
                ;;
            6)  
                if $UPDATE_AVAILABLE; then
                    update
                fi
                ;;
            *)
                echo "Invalid option"
                sleep 2
                ;;
        esac
    done
}

trap cleanup EXIT
main_menu
