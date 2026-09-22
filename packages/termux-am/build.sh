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

# Components Gradle will ask for when building TermuxAm.
# Adjust these if you bump compileSdk / buildToolsVersion in the project.
_TERMUX_AM_BUILD_TOOLS=30.0.3
_TERMUX_AM_PLATFORM=android-33

termux_step_post_get_source() {
	sed -i'' -E -e "s|\@TERMUX_PREFIX\@|${TERMUX_PREFIX}|g" "$TERMUX_PKG_SRCDIR/am-libexec-packaged"
	sed -i'' -E -e "s|\@TERMUX_APP_PACKAGE\@|${TERMUX_APP_PACKAGE}|g" "$TERMUX_PKG_SRCDIR/app/src/main/java/com/termux/termuxam/FakeContext.java"
}

# ------------------------------------------------------------------
# Helper: make a directory writable by the current user.
# The Termux build SDK is often root-owned, which is what causes
# "Failed to read or create install properties file".
# ------------------------------------------------------------------
termux_am_ensure_writable() {
	local dir="$1"
	[ -z "$dir" ] || [ ! -e "$dir" ] && return 0
	[ -w "$dir" ] && return 0

	echo "INFO: Fixing permissions on $dir ..." >&2
	local uid gid
	uid="$(id -u)"
	gid="$(id -g)"

	if command -v sudo >/dev/null 2>&1; then
		sudo chown -R "$uid:$gid" "$dir" 2>/dev/null || \
		sudo chmod -R u+rwX "$dir"       2>/dev/null || \
		chmod    -R u+rwX "$dir"         2>/dev/null || true
	else
		chmod -R u+rwX "$dir" 2>/dev/null || true
	fi

	# Remove stale .installer dirs that can block sdkmanager.
	find "$dir" -maxdepth 3 -type d -name ".installer" \
		-exec rm -rf {} + 2>/dev/null || true
}

termux_step_make() {
	# ------------------------------------------------------------------
	# 1. Make sure ANDROID_HOME is set and writable.
	# ------------------------------------------------------------------
	: "${ANDROID_HOME:="/home/builder/lib/android-sdk"}"
	export ANDROID_HOME

	mkdir -p "$ANDROID_HOME"
	termux_am_ensure_writable "$ANDROID_HOME"
	mkdir -p "$ANDROID_HOME/licenses"
	termux_am_ensure_writable "$ANDROID_HOME/licenses"

	# ------------------------------------------------------------------
	# 2. Locate sdkmanager inside the SDK.
	# ------------------------------------------------------------------
	local SDK_MANAGER=""
	if   [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
		SDK_MANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
	elif [ -x "$ANDROID_HOME/cmdline-tools/bin/sdkmanager" ]; then
		SDK_MANAGER="$ANDROID_HOME/cmdline-tools/bin/sdkmanager"
	else
		echo "ERROR: no usable sdkmanager found in $ANDROID_HOME" >&2
		find "$ANDROID_HOME" -type f -name sdkmanager >&2 || true
		exit 1
	fi
	echo "INFO: Using sdkmanager: $SDK_MANAGER"

	# ------------------------------------------------------------------
	# 3. Install the exact SDK components Gradle needs.
	# ------------------------------------------------------------------
	# Accept licenses. `yes |` closes the pipe early, so guard with `|| true`.
	yes | "$SDK_MANAGER" --sdk_root="$ANDROID_HOME" --licenses || true

	yes | "$SDK_MANAGER" --sdk_root="$ANDROID_HOME" \
		"platform-tools" \
		"build-tools;${_TERMUX_AM_BUILD_TOOLS}" \
		"platforms;${_TERMUX_AM_PLATFORM}" || true

	# Fix ownership again: sdkmanager may have created root-owned files.
	termux_am_ensure_writable "$ANDROID_HOME"

	# ------------------------------------------------------------------
	# 4. Download and use a new enough gradle version.
	# ------------------------------------------------------------------
	# (avoids the process hanging after running with older gradle)
	termux_download \
		https://services.gradle.org/distributions/gradle-$_GRADLE_VERSION-bin.zip \
		$TERMUX_PKG_CACHEDIR/gradle-$_GRADLE_VERSION-bin.zip \
		31c55713e40233a8303827ceb42ca48a47267a0ad4bab9177123121e71524c26
	mkdir -p $TERMUX_PKG_TMPDIR/gradle
	unzip -q $TERMUX_PKG_CACHEDIR/gradle-$_GRADLE_VERSION-bin.zip -d $TERMUX_PKG_TMPDIR/gradle

	# ------------------------------------------------------------------
	# 5. Disable Gradle's SDK auto-install.
	# ------------------------------------------------------------------
	# This is what triggers "Failed to read or create install properties
	# file" when the SDK dir is root-owned. We've already installed the
	# required components above, so Gradle doesn't need to touch the SDK.
	if ! grep -q '^android\.builder\.sdkDownload=' gradle.properties 2>/dev/null; then
		echo 'android.builder.sdkDownload=false' >> gradle.properties
	fi

	# Avoid spawning the gradle daemon due to org.gradle.jvmargs
	# being set (https://github.com/gradle/gradle/issues/1434):
	sed -i'' -E '/^org\.gradle\.jvmargs=.*/d' gradle.properties

	# ------------------------------------------------------------------
	# 6. Build.
	# ------------------------------------------------------------------
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
