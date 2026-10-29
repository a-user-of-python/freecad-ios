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
