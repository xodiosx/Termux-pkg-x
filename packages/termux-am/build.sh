TERMUX_PKG_HOMEPAGE=https://www.ppsspp.org/
TERMUX_PKG_DESCRIPTION="PlayStation Portable emulator"
TERMUX_PKG_LICENSE="GPL-2.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION="1.20.4"
TERMUX_PKG_GIT_BRANCH="v${TERMUX_PKG_VERSION}"
TERMUX_PKG_SRCURL="git+https://github.com/hrydgard/ppsspp"
TERMUX_PKG_DEPENDS="sdl2, sdl2-ttf, fontconfig, libcurl, glew, libpng, rapidjson, miniupnpc, zstd, zlib, libzip, libsnappy, libcpufeatures, spirv-tools"
TERMUX_PKG_BUILD_DEPENDS="extra-cmake-modules, libglvnd-dev, vulkan-headers, spirv-headers, mesa-dev"
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
-DCMAKE_SYSTEM_NAME=Linux
-DBUILD_TESTING=OFF
-DUSING_EGL=ON
-DUSING_FBDEV=OFF
-DUSING_GLES2=ON
-DUSING_X11_VULKAN=ON
-DUSE_WAYLAND_WSI=OFF
-DUSE_VULKAN_DISPLAY_KHR=OFF
-DUSING_QT_UI=OFF
-DMOBILE_DEVICE=OFF
-DHEADLESS=OFF
-DATLAS_TOOL=ON
-DUNITTEST=OFF
-DUSE_LIBNX=OFF
-DUSE_FFMPEG=ON
-DUSE_DISCORD=OFF
-DUSE_MINIUPNPC=ON
-DUSE_SYSTEM_SNAPPY=ON
-DUSE_SYSTEM_FFMPEG=OFF
-DUSE_SYSTEM_FREETYPE=ON
-DUSE_SYSTEM_LIBCHDR=OFF
-DUSE_SYSTEM_LIBZIP=ON
-DUSE_SYSTEM_LIBSDL2=ON
-DUSE_SYSTEM_LIBPNG=ON
-DUSE_SYSTEM_RAPIDJSON=ON
-DUSE_SYSTEM_ZSTD=ON
-DUSE_SYSTEM_MINIUPNPC=ON
-DUSE_ASAN=OFF
-DUSE_UBSAN=OFF
-DUSE_CCACHE=OFF
-DUSE_NO_MMAP=OFF
"

termux_step_post_extract_package() {
	# Replace Android ashmem/dlopen(libandroid.so) with POSIX shm emulation
	# immediately after the source code is cloned.
	cp -a "$TERMUX_PKG_BUILDER_DIR/Common-MemArenaAndroid.cpp" \
		"$TERMUX_PKG_SRCDIR/Common/MemArenaAndroid.cpp"

	# Replace placeholder with the real Termux prefix
	sed -i "s|@TERMUX_PREFIX@|${TERMUX_PREFIX}|g" \
		"$TERMUX_PKG_SRCDIR/Common/MemArenaAndroid.cpp"
}

termux_step_pre_configure() {
	cd "$TERMUX_PKG_SRCDIR"
	# Replace Android ashmem/dlopen(libandroid.so) with POSIX shm emulation.
	cp -a "$TERMUX_PKG_BUILDER_DIR/MemArenaAndroid.cpp" \
		"$TERMUX_PKG_SRCDIR/Common/MemArenaAndroid.cpp"
	# Replace placeholder with the real Termux prefix.
	sed -i "s|@TERMUX_PREFIX@|${TERMUX_PREFIX}|g" \
		"$TERMUX_PKG_SRCDIR/Common/MemArenaAndroid.cpp"
	# Disable Android-specific test calls
	sed -i 's/Arm64EmitterTest();/\/\/ Arm64EmitterTest();/' UI/NativeApp.cpp
	sed -i 's/ArmEmitterTest();/\/\/ ArmEmitterTest();/' UI/NativeApp.cpp
	# code for building .

	find \
		"$TERMUX_PKG_SRCDIR"/Common/GPU \
		"$TERMUX_PKG_SRCDIR"/Common/Log.h \
		"$TERMUX_PKG_SRCDIR"/Common/MsgHandler.h \
		"$TERMUX_PKG_SRCDIR"/ext/naett \
		"$TERMUX_PKG_SRCDIR"/ppsspp_config.h \
		-type f -print0 | xargs -0 sed -i \
		-e 's/\([^A-Za-z0-9_]__ANDROID\)\(__[^A-Za-z0-9_]\)/\1__DISABLING_THIS_BECAUSE_IT_IS_FOR_BUILDING_AN_APK\2/g' \
		-e 's/\([^A-Za-z0-9_]__ANDROID\)__$/\1_DISABLING_THIS_BECAUSE_IT_IS_FOR_BUILDING_AN_APK__/g'
}


termux_step_post_make_install() {
	# Create a convenience symlink: ppsspp -> PPSSPPSDL
	cd $TERMUX_PREFIX/bin
	ln -sf PPSSPPSDL "$TERMUX_PREFIX/bin/ppsspp"
}
