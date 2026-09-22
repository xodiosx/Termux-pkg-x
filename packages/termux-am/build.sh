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
# Return a writable SDK root in $ANDROID_HOME.
# ------------------------------------------------------------------
termux_am_prepare_sdk() {
	: "${ANDROID_HOME:="$HOME/lib/android-sdk"}"
	export ANDROID_HOME

	if [ -w "$ANDROID_HOME" ]; then
		echo "INFO: $ANDROID_HOME is writable, using as-is" >&2
		return 0
	fi

	local writable="$HOME/android-sdk"
	echo "INFO: $ANDROID_HOME is NOT writable, creating user-owned copy at $writable" >&2
	rm -rf "$writable"
	mkdir -p "$writable"

	for sub in cmdline-tools licenses platform-tools; do
		if [ -e "$ANDROID_HOME/$sub" ]; then
			cp -R "$ANDROID_HOME/$sub" "$writable/" 2>/dev/null || true
		fi
	done

	chmod -R u+rwX "$writable" 2>/dev/null || true
	export ANDROID_HOME="$writable"
	echo "INFO: ANDROID_HOME is now $ANDROID_HOME" >&2
}

termux_step_make() {
	termux_am_prepare_sdk
	mkdir -p "$ANDROID_HOME/licenses"

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

	yes | "$SDK_MANAGER" --sdk_root="$ANDROID_HOME" --licenses || true

	# Fail loudly if sdkmanager can't install
	yes | "$SDK_MANAGER" --sdk_root="$ANDROID_HOME" \
		"platform-tools" \
		"build-tools;${_TERMUX_AM_BUILD_TOOLS}" \
		"platforms;${_TERMUX_AM_PLATFORM}"

	if [ ! -d "$ANDROID_HOME/platforms/${_TERMUX_AM_PLATFORM}" ]; then
		echo "ERROR: $ANDROID_HOME/platforms/${_TERMUX_AM_PLATFORM} not found after sdkmanager" >&2
		ls -la "$ANDROID_HOME" >&2 || true
		ls -la "$ANDROID_HOME/platforms" >&2 || true
		exit 1
	fi
	if [ ! -d "$ANDROID_HOME/build-tools/${_TERMUX_AM_BUILD_TOOLS}" ]; then
		echo "ERROR: $ANDROID_HOME/build-tools/${_TERMUX_AM_BUILD_TOOLS} not found after sdkmanager" >&2
		ls -la "$ANDROID_HOME/build-tools" >&2 || true
		exit 1
	fi

	termux_download \
		https://services.gradle.org/distributions/gradle-$_GRADLE_VERSION-bin.zip \
		$TERMUX_PKG_CACHEDIR/gradle-$_GRADLE_VERSION-bin.zip \
		31c55713e40233a8303827ceb42ca48a47267a0ad4bab9177123121e71524c26
	mkdir -p $TERMUX_PKG_TMPDIR/gradle
	unzip -q $TERMUX_PKG_CACHEDIR/gradle-$_GRADLE_VERSION-bin.zip -d $TERMUX_PKG_TMPDIR/gradle

	if ! grep -q '^android\.builder\.sdkDownload=' gradle.properties 2>/dev/null; then
		echo 'android.builder.sdkDownload=false' >> gradle.properties
	fi

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
