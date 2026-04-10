# Kindle deployment notes

Follow these concise steps to prepare and run the updated KindleFetch scripts on your Kindle device.

- Prepare package locally:
  - Run `sh package_for_kindle.sh` from repository root. This creates `kindlefetch_kindle_package.tar.gz`.

- Copy to Kindle:
  - Mount Kindle via USB and copy/extract the tarball into the device root or a preferred folder.

- On-device recommended env (adapt paths as needed):
  - `export AUTO_CONFIRM=true`  # makes downloads non-interactive
  - `export DEBUG_MODE=true`    # preserves debug artifacts for diagnostics
  - `export KINDLE_DOCUMENTS=/mnt/us/documents`  # typical path, adjust if different
  - `export DOWNLOAD_RETRIES=3`
  - `export DOWNLOAD_TIMEOUT=180`

- Run tests and reproduce:
  - `sh kindlefetch/bin/search.sh` to run search UI
  - Or run `sh kindlefetch/bin/downloads/zlib_download.sh <index>` to test the specific entry from `tmp/search_results.json`

- Collect logs:
  - Consolidated: `/tmp/kindlefetch/kindlefetch.log`
  - If `DEBUG_MODE=true`, per-request artifacts will be saved under `kindlefetch/bin/tmp/` on the device.

- Next steps if downloads still fail:
  - Attach the produced `/tmp/kindlefetch/kindlefetch.log` and any preserved files from `kindlefetch/bin/tmp/` and share for further diagnosis.
