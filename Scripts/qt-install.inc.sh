# Shared Qt dual-kit install (FEBio recipe, front 05 P1/P4).
# Sourced by the stage scripts; expects ROOT and WORK to be set.
# On return: QT_VERSION, QT_IOS, QT_DESKTOP are set and verified.
QT_ROOT="$WORK/Qt"
mkdir -p "$WORK" "$QT_ROOT"
echo "== installing Qt (aqtinstall)"
python3 -m pip install --quiet --break-system-packages aqtinstall
QT_VERSION=""
for v in 6.9.3 6.8.3; do
	echo "-- trying Qt $v"
	if python3 -m aqt install-qt mac desktop "$v" clang_64 -O "$QT_ROOT" --modules qtshadertools \
	   && python3 -m aqt install-qt mac ios "$v" ios -O "$QT_ROOT" --modules qtshadertools; then
		QT_VERSION="$v"
		break
	fi
	echo "-- Qt $v install failed, trying next candidate"
done
if [ -z "$QT_VERSION" ]; then
	echo "ERROR: could not install any candidate Qt version" >&2
	exit 1
fi
QT_IOS="$QT_ROOT/$QT_VERSION/ios"
# Discover the desktop (host) kit directory instead of assuming its
# name: Qt renamed the macOS desktop kit dir from clang_64 to macos
# in newer releases (FEBio runs 40763496098 / 40765786297 lessons).
echo "== Qt kit layout under $QT_ROOT/$QT_VERSION:"
ls "$QT_ROOT/$QT_VERSION"
find "$QT_ROOT/$QT_VERSION" -maxdepth 4 -name "Qt6Config.cmake" | sed 's/^/   /' || true
QT_DESKTOP=""
for cfg in "$QT_ROOT/$QT_VERSION"/*/lib/cmake/Qt6/Qt6Config.cmake; do
	case "$cfg" in
		"$QT_IOS"/*) ;;
		*) QT_DESKTOP="$(dirname "$(dirname "$(dirname "$(dirname "$cfg")")")")" ;;
	esac
done
echo "== Qt $QT_VERSION ready (host: $QT_DESKTOP, ios: $QT_IOS)"
test -n "$QT_DESKTOP"
test -f "$QT_IOS/lib/cmake/Qt6/qt.toolchain.cmake"
test -f "$QT_DESKTOP/lib/cmake/Qt6/Qt6Config.cmake"
command -v ninja >/dev/null || brew install ninja

# --- iPhoneOS SDK discovery (runner-pool heterogeneity fix) -------
# On some macos-26 runners the xcode-select default Xcode lacks the
# (downloadable) iOS platform: `xcrun --sdk iphoneos --show-sdk-path`
# fails outright ("SDK iphoneos cannot be located") and CMake's own
# sysroot resolution silently leaves the name "iphoneos", which
# CMake 4.x then fatals on ("iphoneos is not an iOS SDK"). Strategy:
# trust xcrun only if it returns a real directory; otherwise scan
# every installed Xcode for an iPhoneOS SDK, export DEVELOPER_DIR
# for that Xcode (so all later xcrun calls agree), and use the SDK
# path directly as CMAKE_OSX_SYSROOT.
IOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
if [ ! -d "$IOS_SDK_PATH" ]; then
	IOS_SDK_PATH=""
	# xcrun respects DEVELOPER_DIR: retry per installed Xcode, then
	# fall back to a filesystem glob for the SDK directory itself.
	for devdir in $(ls -d /Applications/Xcode*.app/Contents/Developer 2>/dev/null | sort -Vr); do
		candidate="$(DEVELOPER_DIR="$devdir" xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
		if [ -d "$candidate" ]; then
			IOS_SDK_PATH="$candidate"
			DEVELOPER_DIR="$devdir"
			break
		fi
		for sdk in $(ls -d "$devdir"/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk 2>/dev/null | sort -Vr); do
			if [ -d "$sdk" ]; then
				IOS_SDK_PATH="$sdk"
				DEVELOPER_DIR="$devdir"
				break 2
			fi
		done
	done
fi
if [ -d "$IOS_SDK_PATH" ]; then
	echo "== iPhoneOS SDK: $IOS_SDK_PATH (DEVELOPER_DIR=${DEVELOPER_DIR:-default})"
else
	# Observed on a real runner (run 40924270694): with an explicitly
	# empty CMAKE_OSX_SYSROOT, CMake's own fallback resolution still
	# configured every library correctly. Warn loudly, do not die.
	echo "WARNING: no iPhoneOS SDK located via xcrun or filesystem scan;" >&2
	echo "         continuing with an empty CMAKE_OSX_SYSROOT (CMake fallback)." >&2
	IOS_SDK_PATH=""
fi
export DEVELOPER_DIR IOS_SDK_PATH
