#!/bin/sh
# Create a tarball package suitable for copying to a Kindle device.
set -e

PKG="kindlefetch_kindle_package.tar.gz"
BUILD_DIR="kindle_package_build"

echo "Preparing package..."
rm -rf "$BUILD_DIR" "$PKG"
mkdir -p "$BUILD_DIR"

echo "Copying kindlefetch/ to build dir..."
cp -r kindlefetch "$BUILD_DIR/" || {
    echo "Failed to copy kindlefetch/ — ensure you run this from repository root." >&2
    exit 1
}

# Remove runtime tmp artifacts if present
rm -rf "$BUILD_DIR/kindlefetch/tmp" "$BUILD_DIR/kindlefetch/bin/tmp" 2>/dev/null || true

cat > "$BUILD_DIR/INSTALL_ON_KINDLE.txt" <<'EOF'
Deployment notes — KindleFetch (Kindle)

1) Copy files to Kindle
   - Mount your Kindle via USB and copy the contents of the generated tarball into the root of the device, or copy the tarball and extract it on-device.

2) Recommended environment variables (run before invoking scripts):
   export AUTO_CONFIRM=true        # non-interactive
   export DEBUG_MODE=true          # keep debug artifacts for diagnosis
   export KINDLE_DOCUMENTS=/mnt/us/documents  # adjust if different on your model
   export DOWNLOAD_RETRIES=3       # retry downloads (default 3)
   export DOWNLOAD_TIMEOUT=180     # per-download timeout in seconds

3) Run a non-interactive test
   sh kindlefetch/bin/search.sh
   # or run a specific downloader
   sh kindlefetch/bin/downloads/zlib_download.sh 2

4) Retrieve logs
   - Consolidated log: /tmp/kindlefetch/kindlefetch.log
   - If DEBUG_MODE=true, per-request artifacts will be in kindlefetch/bin/tmp/ on-device.

EOF

echo "Creating tarball $PKG..."
tar -czf "$PKG" -C "$BUILD_DIR" kindlefetch INSTALL_ON_KINDLE.txt
rm -rf "$BUILD_DIR"
echo "Package created: $PKG"

exit 0
