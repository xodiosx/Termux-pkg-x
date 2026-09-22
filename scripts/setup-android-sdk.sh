#!/bin/bash
set -eo pipefail

: "${TERMUX_PKG_TMPDIR:="/tmp"}"
: "${ANDROID_HOME:="$HOME/lib/android-sdk"}"
: "${NDK:="$HOME/lib/android-ndk"}"
: "${TERMUX_ANDROID_BUILD_TOOLS_VERSION:="35.0.0"}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/properties.sh"
. "$SCRIPT_DIR/build/termux_download.sh"

# ------------------------------------------------------------------
# 0. Make sure required host tools exist
# ------------------------------------------------------------------
need_pkg() {
    command -v "$1" >/dev/null 2>&1 && return 0
    if   command -v apt-get >/dev/null 2>&1; then apt-get update -y && apt-get install -y "$1"
    elif command -v pkg     >/dev/null 2>&1; then pkg install -y "$1"
    else echo "Missing required tool: $1" >&2; return 1
    fi
}
for p in unzip curl wget; do need_pkg "$p"; done
if ! command -v java >/dev/null 2>&1; then
    need_pkg openjdk-17-jre-headless || true
fi

ANDROID_SDK_FILE=commandlinetools-linux-${TERMUX_SDK_REVISION}_latest.zip
ANDROID_SDK_SHA256=0bebf59339eaa534f4217f8aa0972d14dc49e7207be225511073c661ae01da0a

if   [ "$TERMUX_NDK_VERSION" = "29" ]; then
    ANDROID_NDK_FILE=android-ndk-r${TERMUX_NDK_VERSION}-linux.zip
    ANDROID_NDK_SHA256=4abbbcdc842f3d4879206e9695d52709603e52dd68d3c1fff04b3b5e7a308ecf
elif [ "$TERMUX_NDK_VERSION" = "23c" ]; then
    ANDROID_NDK_FILE=android-ndk-r${TERMUX_NDK_VERSION}-linux.zip
    ANDROID_NDK_SHA256=6ce94604b77d28113ecd588d425363624a5228d9662450c48d2e4053f8039242
else
    echo "ERROR: unknown NDK version $TERMUX_NDK_VERSION" >&2
    exit 1
fi

# ------------------------------------------------------------------
# 1. Android SDK
# ------------------------------------------------------------------
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ] && \
   [ ! -x "$ANDROID_HOME/cmdline-tools/bin/sdkmanager" ]; then

    echo "Downloading Android SDK..."
    rm -rf "$ANDROID_HOME"
    mkdir -p "$ANDROID_HOME"

    termux_download "https://dl.google.com/android/repository/${ANDROID_SDK_FILE}" \
        "$TERMUX_PKG_TMPDIR/$ANDROID_SDK_FILE" \
        "$ANDROID_SDK_SHA256"

    unzip -q "$TERMUX_PKG_TMPDIR/$ANDROID_SDK_FILE" -d "$ANDROID_HOME"

    # cmdline-tools/ → cmdline-tools/latest/
    if [ -d "$ANDROID_HOME/cmdline-tools" ] && \
       [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
        mv "$ANDROID_HOME/cmdline-tools" "$ANDROID_HOME/cmdline-tools.tmp"
        mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
        mv "$ANDROID_HOME/cmdline-tools.tmp"/* "$ANDROID_HOME/cmdline-tools/latest/"
        rmdir "$ANDROID_HOME/cmdline-tools.tmp"
    fi
fi

mkdir -p "$ANDROID_HOME/licenses"

# ------------------------------------------------------------------
# 2. Android NDK
# ------------------------------------------------------------------
if [ ! -d "$NDK" ]; then
    echo "Downloading Android NDK..."
    mkdir -p "$(dirname "$NDK")"

    termux_download "https://dl.google.com/android/repository/${ANDROID_NDK_FILE}" \
        "$TERMUX_PKG_TMPDIR/$ANDROID_NDK_FILE" \
        "$ANDROID_NDK_SHA256"

    rm -rf "$NDK" "$(dirname "$NDK")/android-ndk-r$TERMUX_NDK_VERSION"
    unzip -q "$TERMUX_PKG_TMPDIR/$ANDROID_NDK_FILE" -d "$(dirname "$NDK")"

    if [ ! -d "$NDK" ] && [ -d "$(dirname "$NDK")/android-ndk-r$TERMUX_NDK_VERSION" ]; then
        mv "$(dirname "$NDK")/android-ndk-r$TERMUX_NDK_VERSION" "$NDK"
    fi

    rm -rf "$NDK/sources/cxx-stl/system"
fi

# ------------------------------------------------------------------
# 3. Locate sdkmanager
# ------------------------------------------------------------------
if   [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    SDK_MANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
elif [ -x "$ANDROID_HOME/cmdline-tools/bin/sdkmanager" ]; then
    SDK_MANAGER="$ANDROID_HOME/cmdline-tools/bin/sdkmanager"
else
    echo "ERROR: no usable sdkmanager found in $ANDROID_HOME" >&2
    find "$ANDROID_HOME" -type f -name sdkmanager >&2 || true
    exit 1
fi

echo "INFO: Using sdkmanager ... $SDK_MANAGER"
echo "INFO: Using NDK ... $NDK"

# ------------------------------------------------------------------
# 4. Install required SDK packages
# ------------------------------------------------------------------
yes | "$SDK_MANAGER" --sdk_root="$ANDROID_HOME" --licenses || true

yes | "$SDK_MANAGER" --sdk_root="$ANDROID_HOME" \
    "platform-tools" \
    "build-tools;${TERMUX_ANDROID_BUILD_TOOLS_VERSION}" \
    "build-tools;30.0.3" \
    "platforms;android-35" \
    "platforms;android-33" \
    "platforms;android-28" \
    "platforms;android-24" || true

# ------------------------------------------------------------------
# 5. Fix ownership so the build user owns the whole SDK tree.
# ------------------------------------------------------------------
# This runs as the user who invoked the script. On the official
# Dockerfile that user is "builder", so this is a no-op. If anyone
# runs the script as root (e.g. in a custom image), this ensures the
# SDK does not end up root-owned and unusable by the build user.
if [ "$(id -u)" -eq 0 ] && id builder >/dev/null 2>&1; then
    chown -R builder:builder "$ANDROID_HOME" "$(dirname "$NDK")" 2>/dev/null || true
fi

echo "INFO: setup-android-sdk.sh finished"
echo "INFO: ANDROID_HOME = $ANDROID_HOME"
echo "INFO: NDK          = $NDK"
echo "INFO: sdkmanager   = $SDK_MANAGER"
