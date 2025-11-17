#!/usr/bin/env bash
set -euo pipefail

### AIO_codespace_for_android.sh
### All-in-one script for Codespaces / WSL / Linux (Android Build + Web/Device Preview + Release Upload)
### Updated: Interactive commit message added.

API_LEVEL="${API_LEVEL:-33}"
BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION:-33.0.2}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
BUILD_TYPE="${BUILD_TYPE:-debug}"
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip}"
WEB_PORT="${WEB_PORT:-8080}"

LOG_DIR="${LOG_DIR:-$HOME/flutter_setup_logs}"
mkdir -p "$LOG_DIR"

PREVIEW_PID=""
PREVIEW_TYPE=""
PREVIEW_LOG=""

CLR_RESET="\e[0m"
CLR_RED="\e[31m"
CLR_GREEN="\e[32m"
CLR_YELLOW="\e[33m"
CLR_BLUE="\e[34m"
CLR_CYAN="\e[36m"
BOLD="\e[1m"

info(){ echo -e "${BOLD}${CLR_BLUE}[INFO]${CLR_RESET} $*"; }
ok(){ echo -e "${BOLD}${CLR_GREEN}[OK]${CLR_RESET} $*"; }
warn(){ echo -e "${BOLD}${CLR_YELLOW}[WARN]${CLR_RESET} $*"; }
err(){ echo -e "${BOLD}${CLR_RED}[ERR]${CLR_RESET} $*"; }

spinner_start() {
  local pid=$1 msg="$2" spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  printf "%s " "$msg"
  while kill -0 "$pid" 2>/dev/null; do
    printf "\b${spin:i%${#spin}:1}"
    sleep 0.08; ((i++))
  done
  printf "\b"
}

run_with_spinner() {
  local msg="$1"; shift
  local prefix="$1"; shift
  local safe="${prefix// /_}"
  local logfile="$LOG_DIR/$(date +%Y%m%d_%H%M%S)_${safe}.log"

  ( "$@" ) 2>&1 | tee -a "$logfile" &
  local pid=$!
  spinner_start "$pid" "$msg"
  wait "$pid" || { err "$msg Failed. Log: $logfile"; LAST_ERROR_LOG="$logfile"; return 1; }

  ok "$msg Done. Log: $logfile"
  LAST_SUCCESS_LOG="$logfile"
}

handle_failure() {
  echo; err "$1"
  echo; echo "1) Exit"; echo "2) Menu Utama"
  read -rp "Pilih: " c
  [[ "$c" == "1" ]] && exit 1
}

ensure_installed_basic(){ command -v curl >/dev/null || sudo apt-get update -y; }

find_project_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/pubspec.yaml" ]] && echo "$dir" && return
    dir="$(dirname "$dir")"
  done
  echo ""
}

find_latest_apk() {
  local root="$(find_project_root)" d="$root/build/app/outputs/flutter-apk"
  [[ -f "$d/app-debug.apk" ]] && echo "$d/app-debug.apk" && return
  [[ -f "$d/app-release.apk" ]] && echo "$d/app-release.apk" && return
  compgen -G "$d/*.apk" >/dev/null && ls -t "$d"/*.apk | head -n1 || echo ""
}

install_requirements() {
  info "Installing basics..."
  sudo apt-get install -y curl git unzip xz-utils zip zipalign openjdk-17-jdk-headless pkg-config

  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
  export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"

  [[ -d "$HOME/flutter" ]] || git clone https://github.com/flutter/flutter.git -b "$FLUTTER_CHANNEL" --depth 1 "$HOME/flutter"

  export PATH="$HOME/flutter/bin:$PATH"
  flutter config --enable-web || true
  flutter doctor -v || true

  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  TMP="/tmp/cmd.zip"
  curl -fSL -o "$TMP" "$CMDLINE_TOOLS_URL"
  unzip -oq "$TMP" -d "$ANDROID_SDK_ROOT/cmdline-tools"

  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest" 2>/dev/null || true
  export ANDROID_SDK_ROOT PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

  yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses || true
  sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "platform-tools" "platforms;android-$API_LEVEL" "build-tools;$BUILD_TOOLS_VERSION"

  ok "Requirements installed."
}

start_web_preview_bg() {
  [[ -n "$PREVIEW_PID" ]] && warn "Preview already running." && return
  local root="$(find_project_root)"; [[ -z "$root" ]] && handle_failure "Not project." && return
  pushd "$root" >/dev/null

  local log="$LOG_DIR/$(date +%Y%m%d_%H%M%S)_web.log"
  flutter pub get | tee -a "$log"
  ( flutter run -d web-server --web-hostname=0.0.0.0 --web-port=$WEB_PORT | tee -a "$log" ) &

  PREVIEW_PID=$!
  PREVIEW_TYPE="web"
  PREVIEW_LOG="$log"
  ok "Web Preview Running."
  popd >/dev/null
}

start_device_preview_bg() {
  [[ -n "$PREVIEW_PID" ]] && warn "Preview already running." && return
  local root="$(find_project_root)"; [[ -z "$root" ]] && handle_failure "Not project." && return
  pushd "$root" >/dev/null

  flutter devices
  read -rp "Device-id: " d
  [[ -z "$d" ]] && warn "Cancelled." && popd >/dev/null && return

  local log="$LOG_DIR/$(date +%Y%m%d_%H%M%S)_dev_${d}.log"
  flutter pub get | tee -a "$log"
  ( flutter run -d "$d" | tee -a "$log" ) &
  PREVIEW_PID=$!
  PREVIEW_TYPE="device"
  PREVIEW_LOG="$log"
  ok "Device Preview Running."
  popd >/dev/null
}

show_preview_log() {
  [[ -f "$PREVIEW_LOG" ]] && less "$PREVIEW_LOG" || warn "No preview log."
}

preview_menu() {
  while true; do
    echo; echo -e "${BOLD}${CLR_CYAN}=== Preview Aplikasi ===${CLR_RESET}"
    echo "1) Start Web Preview"
    echo "2) Start Device Preview"
    echo "3) Show Preview Log"
    echo "4) Kembali"
    echo "5) Exit"
    read -rp "Pilih: " p
    case "$p" in
      1) start_web_preview_bg ;;
      2) start_device_preview_bg ;;
      3) show_preview_log ;;
      4) break ;;
      5) exit 0 ;;
      *) warn "Invalid." ;;
    esac
  done
}

build_apk() {
  local root="$(find_project_root)"
  [[ -z "$root" ]] && handle_failure "Bukan project." && return
  pushd "$root" >/dev/null

  flutter pub get
  flutter build apk --$BUILD_TYPE -v
  ok "Build Selesai."
  popd >/dev/null
}

upload_to_release() {
  local apk="$(find_latest_apk)"
  [[ -z "$apk" ]] && warn "APK tidak ada." && return

  command -v gh >/dev/null || sudo apt-get install -y gh
  gh auth status >/dev/null 2>&1 || gh auth login

  local tag="auto-$(date +%Y%m%d%H%M%S)"
  gh release create "$tag" "$apk" --notes "Auto upload"
  ok "Uploaded ke Release."
}

push_repo_all() {
  echo
  read -rp "Masukkan commit message: " COMMSG
  COMMSG="${COMMSG:-chore: update via AIO script}"

  git add -A
  git commit -m "$COMMSG" || true
  git push || true

  ok "Repo pushed dengan message: \"$COMMSG\""
}

bersihkan_flutter() {
  local root="$(find_project_root)"
  pushd "$root" >/dev/null
  flutter clean || true
  rm -rf build || true
  popd >/dev/null
  ok "Cleanup done."
}

main_menu() {
  while true; do
    echo
    echo -e "${BOLD}${CLR_CYAN}====== AIO Flutter Android Menu ======${CLR_RESET}"
    echo "1) Siapkan Requirement"
    echo "2) Build APK"
    echo "3) Setup + Build"
    echo "4) Upload APK ke Release"
    echo "5) Commit & Push Repo"
    echo "6) Bersihkan Flutter"
    echo "7) Preview Aplikasi (Web/Device)"
    echo "8) Exit"
    read -rp "Pilih: " x
    case "$x" in
      1) install_requirements ;;
      2) build_apk ;;
      3) install_requirements; build_apk ;;
      4) upload_to_release ;;
      5) push_repo_all ;;
      6) bersihkan_flutter ;;
      7) preview_menu ;;
      8) exit 0 ;;
      *) warn "Invalid." ;;
    esac
  done
}

ensure_installed_basic
main_menu
