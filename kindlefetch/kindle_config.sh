#!/bin/sh
# KindleFetch device defaults (sourced by scripts when present)
# Place this file at `kindlefetch/kindle_config.sh` to set device-friendly defaults.
# These values are only applied when the environment or other configs don't override them.

# Non-interactive by default on Kindle
: ${AUTO_CONFIRM:=true}

# Debug mode: set to true to keep per-request debug artifacts on-device
: ${DEBUG_MODE:=false}

# Default Kindle documents path (adjust if your device differs)
: ${KINDLE_DOCUMENTS:=/mnt/us/documents}

# Download retry behavior
: ${DOWNLOAD_RETRIES:=3}
: ${DOWNLOAD_TIMEOUT:=180}

# Temporary directory and log file defaults
: ${TMP_DIR:=/tmp}
: ${LOG_FILE:=${TMP_DIR}/kindlefetch/kindlefetch.log}

# If you include a static curl binary named `curl` in the `kindlefetch/` folder,
# the scripts will prefer it. Put your custom curl at `kindlefetch/curl` and
# ensure it's executable (`chmod +x kindlefetch/curl`) after copying to device.
# You may override the path by setting `CURL_BIN` here or via environment.
: ${CURL_BIN:="$SCRIPT_DIR/curl"}

export AUTO_CONFIRM DEBUG_MODE KINDLE_DOCUMENTS DOWNLOAD_RETRIES DOWNLOAD_TIMEOUT TMP_DIR LOG_FILE CURL_BIN
