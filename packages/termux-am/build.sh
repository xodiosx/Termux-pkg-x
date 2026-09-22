# Contributor: @michalbednarski
TERMUX_PKG_HOMEPAGE=https://github.com/termux/TermuxAm
TERMUX_PKG_DESCRIPTION="Android Oreo-compatible am command reimplementation"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="Michal Bednarski @michalbednarski"
TERMUX_PKG_VERSION=0.8.0
TERMUX_PKG_REVISION=2
TERMUX_PKG_SRCURL=https://github.com/termux/TermuxAm/archive/refs/tags/v$TERMUX_PKG_VERSION.tar.gz
TERMUX_PKG_SHA256=7d4cfa2bfff93d5fc89fc89e537d2c072e08918276b140b7ed48ea45ebfbe8f3
TERMUX_PKG_PLATFORM_INDEPENDENT=true
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_CONFLICTS="termux-tools (<< 0.51)"
_GRADLE_VERSION=8.10.2

_TERMUX_AM_BUILD_TOOLS=30.0.3
_TERMUX_AM_PLATFORM=android-33

termux_step_post_get_source() {
	sed -i'' -E -e "s|\@TERMUX_PREFIX\@|${TERMUX_PREFIX}|g" "$TERMUX_PKG_SRCDIR/am-libexec-packaged"
	sed -i'' -E -e "s|\@TERMUX_APP_PACKAGE\@|${TERMUX_APP_PACKAGE}|g" "$TERMUX_PKG_SRCDIR/app/src/main/java/com/termux/termuxam/FakeContext.java"
}

# ------------------------------------------------------------------
# Ensure we have a *writable* AND *usable* Android SDK in $ANDROID_HOME.
#
# The official package-builder image sometimes ships an SDK owned by
# root (mode 0700) at $HOME/lib/android-sdk-<rev>. When that happens,
# sdkmanager and Gradle both fail with:
#   "Failed to read or create install properties file"
#
# Rather than trying to copy that root-owned SDK (which can be mode
# 0700 and unreadable by us), we build a fresh, user-owned SDK at
# $HOME/android-sdk. We only reuse the license hashes, if readable,
# to avoid re-accepting them.
# ------------------------------------------------------------------
termux_am_prepare_sdk() {
	: "${ANDROID_HOME:="$HOME/lib/android-sdk"}"
	local writable="$HOME/android-sdk"

	# 1. Prefer the system SDK if it is writable AND has sdkmanager.
	if [ -w "$ANDROID_HOME" ]; then
		if [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ] || \
			[ -x "$ANDROID_HOME/cmdline-tools/bin/sdkmanager" ] || \
			[ -x "$ANDROID_HOME/tools/bin/sdkmanager" ]; then
			echo "INFO: Using system SDK at $ANDROID_HOME (writable, has sdkmanager)" >&2
			export ANDROID_HOME
			return 0
		fi
	fi

	echo "INFO: System SDK at $ANDROID_HOME is not usable, setting up user-owned SDK at $writable" >&2

	# 2. Build / reuse a user-owned SDK.
	if [ ! -x "$writable/cmdline-tools/latest/bin/sdkmanager" ]; then
		rm -rf "$writable"
		mkdir -p "$writable/licenses"

		# Copy license hashes if the source directory is readable.
		if [ -d "$ANDROID_HOME/licenses" ] && [ -r "$ANDROID_HOME/licenses" ]; then
			cp -R "$ANDROID_HOME/licenses/." "$writable/licenses/" 2>/dev/null || true
		fi

		local sdk_zip="$TERMUX_PKG_TMPDIR/commandlinetools-linux-${TERMUX_SDK_REVISION}_latest.zip"
		local sdk_url="https://dl.google.com/android/repository/commandlinetools-linux-${TERMUX_SDK_REVISION}_latest.zip"

		if [ ! -f "$sdk_zip" ]; then
			echo "INFO: Downloading $sdk_url" >&2
			curl -fsSL -o "$sdk_zip" "$sdk_url" || {
				echo "ERROR: failed to download $sdk_url" >&2
				exit 1
			}
		fi

		# Unzip into a temp dir. Layout inside the zip is cmdline-tools/.
		# We need it at cmdline-tools/latest/ for sdkmanager to run.
		local tmpdir="$writable/.tmp-cmdline-tools"
		rm -rf "$tmpdir"
		mkdir -p "$tmpdir"
		unzip -q "$sdk_zip" -d "$tmpdir"

		# Clean target directory.
		rm -rf "$writable/cmdline-tools"
		mkdir -p "$writable/cmdline-tools"

		if [ -d "$tmpdir/cmdline-tools" ]; then
			mv "$tmpdir/cmdline-tools" "$writable/cmdline-tools/latest"
		else
			# Fallback if the zip layout changes: move everything.
			mv "$tmpdir" "$writable/cmdline-tools/latest"
		fi
		rm -rf "$tmpdir"

		chmod -R u+rwX "$writable" 2>/dev/null || true
	fi

	export ANDROID_HOME="$writable"

	if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
		echo "ERROR: sdkmanager still not found after setup in $ANDROID_HOME" >&2
		find "$ANDROID_HOME" -maxdepth 5 -type f -name sdkmanager >&2 || true
		exit 1
	fi

	echo "INFO: Using user-owned SDK at $ANDROID_HOME" >&2
}

termux_step_make() {
	termux_am_prepare_sdk
	mkdir -p "$ANDROID_HOME/licenses"

	local SDK_MANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
	if [ ! -x "$SDK_MANAGER" ]; then
		# Fallback for older commandlinetools layouts.
		for cand in \
			"$ANDROID_HOME/cmdline-tools/bin/sdkmanager" \
			"$ANDROID_HOME/tools/bin/sdkmanager"; do
			if [ -x "$cand" ]; then
				SDK_MANAGER="$cand"
				break
			fi
		done
	fi
	if [ ! -x "$SDK_MANAGER" ]; then
		echo "ERROR: no usable sdkmanager found in $ANDROID_HOME" >&2
		find "$ANDROID_HOME" -type f -name sdkmanager >&2 || true
		exit 1
	fi
	echo "INFO: Using sdkmanager: $SDK_MANAGER"

	# Accept licenses (guard against `yes` SIGPIPE under `set -e`).
	yes | "$SDK_MANAGER" --sdk_root="$ANDROID_HOME" --licenses || true

	# Install the exact components Gradle will ask for.
	# Do NOT swallow errors here — fail fast with a clear message.
	yes | "$SDK_MANAGER" --sdk_root="$ANDROID_HOME" \
		"platform-tools" \
		"build-tools;${_TERMUX_AM_BUILD_TOOLS}" \
		"platforms;${_TERMUX_AM_PLATFORM}"

	if [ ! -d "$ANDROID_HOME/platforms/${_TERMUX_AM_PLATFORM}" ]; then
		echo "ERROR: $ANDROID_HOME/platforms/${_TERMUX_AM_PLATFORM} not found" >&2
		ls -la "$ANDROID_HOME" >&2 || true
		ls -la "$ANDROID_HOME/platforms" >&2 || true
		exit 1
	fi
	if [ ! -d "$ANDROID_HOME/build-tools/${_TERMUX_AM_BUILD_TOOLS}" ]; then
		echo "ERROR: $ANDROID_HOME/build-tools/${_TERMUX_AM_BUILD_TOOLS} not found" >&2
		ls -la "$ANDROID_HOME/build-tools" >&2 || true
		exit 1
	fi

	# ------------------------------------------------------------------
	# Download and use a new enough gradle version.
	# ------------------------------------------------------------------
	termux_download \
		https://services.gradle.org/distributions/gradle-$_GRADLE_VERSION-bin.zip \
		$TERMUX_PKG_CACHEDIR/gradle-$_GRADLE_VERSION-bin.zip \
		31c55713e40233a8303827ceb42ca48a47267a0ad4bab9177123121e71524c26
	mkdir -p $TERMUX_PKG_TMPDIR/gradle
	unzip -q $TERMUX_PKG_CACHEDIR/gradle-$_GRADLE_VERSION-bin.zip -d $TERMUX_PKG_TMPDIR/gradle

	# Stop Gradle from trying to auto-install SDK components.
	if ! grep -q '^android\.builder\.sdkDownload=' gradle.properties 2>/dev/null; then
		echo 'android.builder.sdkDownload=false' >> gradle.properties
	fi

	# Avoid spawning the gradle daemon due to org.gradle.jvmargs
	# being set (https://github.com/gradle/gradle/issues/1434):
	sed -i'' -E '/^org\.gradle\.jvmargs=.*/d' gradle.properties

	export GRADLE_OPTS="-Dorg.gradle.daemon=false -Xmx1536m -Dorg.gradle.java.home=/usr/lib/jvm/java-1.17.0-openjdk-amd64"

	$TERMUX_PKG_TMPDIR/gradle/gradle-$_GRADLE_VERSION/bin/gradle \
		:app:assembleRelease
}

termux_step_make_install() {
	cp $TERMUX_PKG_SRCDIR/am-libexec-packaged $TERMUX_PREFIX/bin/am
	mkdir -p $TERMUX_PREFIX/libexec/termux-am
	cp $TERMUX_PKG_SRCDIR/app/build/outputs/apk/release/app-release-unsigned.apk \
		$TERMUX_PREFIX/libexec/termux-am/am.apk
}
