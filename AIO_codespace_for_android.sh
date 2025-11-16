#!/usr/bin/env bash
set -euo pipefail

### AIO_codespace_for_android.sh
### All-in-one interactive menu for Codespaces (Android-only)
### Updated: fixed syntax errors and robust handling
### - install requirements (JDK + Flutter + Android cmdline tools)
### - build APK (Android path: build/app/outputs/flutter-apk/)
### - upload APK to GitHub Release (choose debug/release/both if present)
### - commit & push whole repo
### - cleanup
### Features: colored output, spinner, per-step logs (~/flutter_setup_logs), error handling & menu loop.

# Defaults (override via env if needed)
API_LEVEL="${API_LEVEL:-33}"
BUILD_TOOLS_VERSION="${BUILD_TOOLS_VERSION:-33.0.2}"
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
BUILD_TYPE="${BUILD_TYPE:-debug}"
CMDLINE_TOOLS_URL="${CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip}"

# Logs
LOG_DIR="${LOG_DIR:-$HOME/flutter_setup_logs}"
mkdir -p "$LOG_DIR"

# Colors
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

# Spinner functions
spinner_start() {
  local pid=$1; local msg="$2"
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  printf "%s " "$msg"
  while kill -0 "$pid" 2>/dev/null; do
    printf "\b${spin:i%${#spin}:1}"
    sleep 0.08
    i=$((i+1))
  done
  printf "\b"
}

# Run command with spinner + tee log
run_with_spinner() {
  local msg="$1"; shift
  local prefix="$1"; shift
  local safe_prefix
  safe_prefix=$(echo "$prefix" | tr ' /' '_' | tr -cd '[:alnum:]_.-')
  local logfile="$LOG_DIR/$(date +%Y%m%d_%H%M%S)_${safe_prefix}.log"
  ( "$@" ) 2>&1 | tee -a "$logfile" &
  local pid=$!
  spinner_start "$pid" "$msg"
  wait "$pid"
  local code=$?
  if [[ $code -eq 0 ]]; then
    ok "$msg Done. (log: $logfile)"
    LAST_SUCCESS_LOG="$logfile"
    return 0
  else
    err "$msg Failed (exit $code). Log: $logfile"
    LAST_ERROR_LOG="$logfile"
    return $code
  fi
}

handle_failure() {
  local errmsg="${1:-Operation failed.}"
  echo
  err "$errmsg"
  if [[ -n "${LAST_ERROR_LOG:-}" ]]; then
    echo -e "${BOLD}Error log:${CLR_YELLOW} ${LAST_ERROR_LOG}${CLR_RESET}"
    echo "Inspect: less \"${LAST_ERROR_LOG}\""
  fi
  echo
  echo "1) Selesai (keluar)"
  echo "2) Kembali ke menu utama"
  read -rp "Pilih (1/2): " hf_choice
  case "$hf_choice" in
    1) ok "Keluar. Lokasi error log: ${LAST_ERROR_LOG:-tidak tersedia}"; exit 1 ;;
    2) ok "Kembali ke menu utama. Lokasi error log: ${LAST_ERROR_LOG:-tidak tersedia}"; return 0 ;;
    *) warn "Pilihan tidak valid, kembali ke menu utama."; return 0 ;;
  esac
}

ensure_installed_basic(){
  if ! command -v curl >/dev/null 2>&1; then
    if ! run_with_spinner "apt-get update" "apt_update" sudo apt-get update -y; then
      handle_failure "apt-get update failed."
      return 1
    fi
  fi
}

# find project root by walking up for pubspec.yaml
find_project_root() {
  local dir="${1:-$(pwd)}"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/pubspec.yaml" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo ""
  return 1
}

# returns apk path or empty (prefer debug -> release -> newest)
find_latest_apk() {
  local project_root
  project_root="$(find_project_root "$(pwd)")"
  local apk_dir
  if [[ -n "$project_root" ]]; then
    apk_dir="$project_root/build/app/outputs/flutter-apk"
  else
    apk_dir="./build/app/outputs/flutter-apk"
  fi

  if [[ -f "$apk_dir/app-debug.apk" ]]; then
    echo "$apk_dir/app-debug.apk"
    return 0
  fi
  if [[ -f "$apk_dir/app-release.apk" ]]; then
    echo "$apk_dir/app-release.apk"
    return 0
  fi
  if compgen -G "$apk_dir"/*.apk >/dev/null 2>&1; then
    ls -t "$apk_dir"/*.apk | head -n1
  else
    echo ""
  fi
}

# NEW: list available debug/release apks (absolute paths)
list_debug_release_apks() {
  local project_root
  project_root="$(find_project_root "$(pwd)")"
  local apk_dir
  if [[ -n "$project_root" ]]; then
    apk_dir="$project_root/build/app/outputs/flutter-apk"
  else
    apk_dir="./build/app/outputs/flutter-apk"
  fi
  local debug="${apk_dir}/app-debug.apk"
  local release="${apk_dir}/app-release.apk"
  local dbg_out=""
  local rel_out=""
  if [[ -f "$debug" ]]; then dbg_out="$debug"; fi
  if [[ -f "$release" ]]; then rel_out="$release"; fi
  printf "%s|%s|%s" "$dbg_out" "$rel_out" "$apk_dir"
}

install_requirements() {
  info "Installing system packages and JDK..."
  if ! run_with_spinner "Installing apt packages (JDK etc)..." "apt_install" sudo apt-get install -y --no-install-recommends curl git unzip xz-utils zip zipalign openjdk-17-jdk-headless pkg-config; then
    handle_failure "Apt package installation failed."
    return 1
  fi

  if ! command -v java >/dev/null 2>&1; then
    handle_failure "Java not found after apt install."
    return 1
  fi

  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
  export JAVA_HOME
  grep -qxF "export JAVA_HOME=$JAVA_HOME" ~/.bashrc || echo "export JAVA_HOME=$JAVA_HOME" >> ~/.bashrc
  grep -qxF 'export PATH="$JAVA_HOME/bin:$PATH"' ~/.bashrc || echo 'export PATH="$JAVA_HOME/bin:$PATH"' >> ~/.bashrc
  export PATH="$JAVA_HOME/bin:$PATH"
  ok "JDK installed and JAVA_HOME set to $JAVA_HOME"

  info "Installing/Updating Flutter SDK..."
  if [[ ! -d "$HOME/flutter" ]]; then
    if ! run_with_spinner "Cloning Flutter SDK..." "git_clone_flutter" git clone https://github.com/flutter/flutter.git -b "$FLUTTER_CHANNEL" --depth 1 "$HOME/flutter"; then
      handle_failure "Failed to clone Flutter."
      return 1
    fi
  else
    run_with_spinner "Updating Flutter repo..." "git_update_flutter" bash -lc "cd '$HOME/flutter' && git fetch --all --prune --tags" || warn "Flutter update failed (non-fatal)."
  fi
  export PATH="$HOME/flutter/bin:$PATH"
  grep -qxF 'export PATH="$HOME/flutter/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
  ok "Flutter ready."

  info "Installing Android command-line tools..."
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  TMPZIP="/tmp/commandlinetools.zip"
  if ! run_with_spinner "Downloading command-line tools..." "download_cmdline_tools" curl -fSL -o "$TMPZIP" "$CMDLINE_TOOLS_URL"; then
    handle_failure "Download command-line tools failed. Upload zip to $TMPZIP and try again."
    return 1
  fi
  if ! run_with_spinner "Extracting command-line tools..." "extract_cmdline_tools" unzip -oq "$TMPZIP" -d "$ANDROID_SDK_ROOT/cmdline-tools"; then
    handle_failure "Extracting command-line tools failed."
    return 1
  fi

  if [[ -d "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" ]]; then
    rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest" 2>/dev/null || true
    mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  else
    mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
    shopt -s dotglob
    mv "$ANDROID_SDK_ROOT/cmdline-tools/"* "$ANDROID_SDK_ROOT/cmdline-tools/latest/" 2>/dev/null || true
    shopt -u dotglob
  fi

  grep -qxF "export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT" ~/.bashrc || echo "export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT" >> ~/.bashrc
  grep -qxF 'export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"' ~/.bashrc \
    || echo 'export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"' >> ~/.bashrc

  export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
  export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

  if ! command -v sdkmanager >/dev/null 2>&1; then
    handle_failure "sdkmanager not found after extraction. Check $ANDROID_SDK_ROOT/cmdline-tools/latest/bin"
    return 1
  fi

  if ! run_with_spinner "Accepting Android SDK licenses..." "accept_licenses" bash -c "yes | sdkmanager --sdk_root='$ANDROID_SDK_ROOT' --licenses >/dev/null 2>&1"; then
    handle_failure "Failed accepting SDK licenses."
    return 1
  fi

  if ! run_with_spinner "Installing platform-tools, platform android-$API_LEVEL, build-tools $BUILD_TOOLS_VERSION..." "sdk_install" sdkmanager --sdk_root="$ANDROID_SDK_ROOT" "platform-tools" "platforms;android-$API_LEVEL" "build-tools;$BUILD_TOOLS_VERSION"; then
    handle_failure "sdkmanager failed to install required packages."
    return 1
  fi

  ok "Android SDK components installed."
  return 0
}

build_apk() {
  # ensure project root found
  local project_root
  project_root="$(find_project_root "$(pwd)")"
  if [[ -z "$project_root" ]]; then
    handle_failure "pubspec.yaml not found. Run build from inside a Flutter project (or place script in project)."
    return 1
  fi
  # work in project root for predictable outputs
  pushd "$project_root" >/dev/null

  if ! run_with_spinner "flutter pub get" "flutter_pub_get" flutter pub get; then
    popd >/dev/null
    handle_failure "flutter pub get failed."
    return 1
  fi

  local build_log="$LOG_DIR/flutter_build_$(date +%Y%m%d_%H%M%S).log"
  ( flutter build apk --$BUILD_TYPE -v 2>&1 | tee -a "$build_log" ) &
  local bpid=$!
  spinner_start "$bpid" "Building APK..."
  wait "$bpid" || { LAST_ERROR_LOG="$build_log"; popd >/dev/null; handle_failure "flutter build failed. See log."; return 1; }
  ok "flutter build finished. Log: $build_log"

  local apk
  apk=$(find_latest_apk)
  if [[ -z "$apk" ]]; then
    warn "Tidak ada APK ditemukan di $project_root/build/app/outputs/flutter-apk/. Pastikan build sukses."
    popd >/dev/null
    return 1
  fi
  ok "APK ditemukan: $apk"
  popd >/dev/null

  post_build_menu "$apk"
  return 0
}

# Post-build submenu
post_build_menu() {
  local apk="$1"
  while true; do
    echo
    echo -e "${BOLD}${CLR_CYAN}Build Sukses! Pilih aksi selanjutnya:${CLR_RESET}"
    echo "1) Selesai (kembali ke menu utama)"
    echo "2) Upload ke GitHub Release"
    echo "3) Push (commit & push) seluruh repo ke GitHub"
    echo "4) Bersihkan Flutter (flutter clean + remove build/)"
    echo "5) Show APK path"
    read -rp "Pilih (1/2/3/4/5): " choice
    case "$choice" in
      1) ok "Kembali ke menu utama."; break ;;
      2) upload_to_release "$apk" || { handle_failure "Upload to release failed."; return 1; } ;;
      3) push_repo_all || { handle_failure "Push repo failed."; return 1; } ;;
      4) bersihkan_flutter || { handle_failure "Cleanup failed."; return 1; } ;;
      5) echo "APK path: $apk" ;;
      *) warn "Pilihan tidak valid." ;;
    esac
  done
}

# select which apks to upload: debug, release, both, or none
select_apks_for_upload() {
  # returns newline-separated list of files to upload (or nothing)
  IFS='|' read -r debug_path release_path apk_dir <<< "$(list_debug_release_apks)"
  debug_path="${debug_path:-}"
  release_path="${release_path:-}"

  if [[ -n "$debug_path" && -n "$release_path" ]]; then
    echo
    echo -e "${BOLD}${CLR_CYAN}Ditemukan kedua APK:${CLR_RESET}"
    echo "1) Upload hanya debug: $debug_path"
    echo "2) Upload hanya release: $release_path"
    echo "3) Upload keduanya"
    echo "4) Batal (kembali ke menu utama)"
    read -rp "Pilih (1/2/3/4): " choice
    case "$choice" in
      1) printf "%s\n" "$debug_path"; return 0 ;;
      2) printf "%s\n" "$release_path"; return 0 ;;
      3) printf "%s\n%s\n" "$debug_path" "$release_path"; return 0 ;;
      4) return 1 ;;
      *) warn "Pilihan tidak valid. Batal."; return 1 ;;
    esac
  elif [[ -n "$debug_path" ]]; then
    printf "%s\n" "$debug_path"
    return 0
  elif [[ -n "$release_path" ]]; then
    printf "%s\n" "$release_path"
    return 0
  else
    # none found
    return 1
  fi
}

upload_to_release() {
  local apk_arg="${1:-}"
  local files_to_upload=()

  # If caller provided an apk path, use it (if exists)
  if [[ -n "$apk_arg" && -f "$apk_arg" ]]; then
    files_to_upload+=("$apk_arg")
  else
    # try to select from project build folder
    if files_list="$(select_apks_for_upload)"; then
      # read lines safely and append
      while IFS= read -r line; do
        if [[ -n "$line" ]]; then
          files_to_upload+=("$line")
        fi
      done <<< "$files_list"
    else
      # nothing found -> offer build or return
      warn "Tidak ada APK yang valid ditemukan di build/app/outputs/flutter-apk/."
      echo "1) Build sekarang"
      echo "2) Kembali ke menu utama"
      read -rp "Pilih (1/2): " choice
      case "$choice" in
        1)
          build_apk || return 1
          # after build, re-select
          if files_list="$(select_apks_for_upload)"; then
            while IFS= read -r line; do
              if [[ -n "$line" ]]; then
                files_to_upload+=("$line")
              fi
            done <<< "$files_list"
          fi
          ;;
        2) ok "Kembali ke menu utama."; return 0 ;;
        *) warn "Pilihan tidak valid. Kembali ke menu utama."; return 0 ;;
      esac
    fi
  fi

  if [[ ${#files_to_upload[@]} -eq 0 ]]; then
    warn "Tidak ada file untuk di-upload. Kembali ke menu utama."
    return 0
  fi

  # Ensure gh exists & auth
  if ! command -v gh >/dev/null 2>&1; then
    warn "GitHub CLI (gh) tidak ditemukan."
    read -rp "Install GitHub CLI now? (y/N): " yn
    if [[ "${yn,,}" =~ ^(y|yes)$ ]]; then
      if ! run_with_spinner "Installing gh..." "install_gh" sudo apt-get install -y gh; then handle_failure "Failed installing gh."; return 1; fi
    else
      handle_failure "gh required to upload release."
      return 1
    fi
  fi

  if ! gh auth status >/dev/null 2>&1; then
    warn "You are not authenticated with gh."
    echo "Run: gh auth login (choose GitHub.com, HTTPS, and follow prompts)."
    read -rp "Run 'gh auth login' now? (y/N): " yn
    if [[ "${yn,,}" =~ ^(y|yes)$ ]]; then
      gh auth login || { handle_failure "gh auth login failed."; return 1; }
    else
      handle_failure "Cannot upload without gh auth."
      return 1
    fi
  fi

  # Create release and attach files. If >1 file, pass them all to gh release create.
  TAG="auto-apk-$(date +%Y%m%d%H%M%S)"
  RELEASE_TITLE="APK $TAG"
  info "Creating release $TAG and uploading ${#files_to_upload[@]} file(s)..."
  # Build args array for gh
  gh_args=( "release" "create" "$TAG" "--title" "$RELEASE_TITLE" "--notes" "Automated APK upload" )
  for f in "${files_to_upload[@]}"; do
    gh_args+=( "$f" )
  done

  if ! run_with_spinner "Creating GitHub release $TAG and uploading APK(s)..." "gh_release_upload" gh "${gh_args[@]}"; then
    handle_failure "gh release create/upload failed."
    return 1
  fi

  ok "Upload complete. Release tag: $TAG (files: ${files_to_upload[*]})"
  return 0
}

# New: commit & push whole repo
push_repo_all() {
  # find project root
  local project_root
  project_root="$(find_project_root "$(pwd)")"
  if [[ -z "$project_root" ]]; then
    handle_failure "Not inside a git/flutter project. Cannot push repo."
    return 1
  fi
  pushd "$project_root" >/dev/null

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    popd >/dev/null
    handle_failure "Not inside a git repository."
    return 1
  fi

  warn "This will 'git add -A' and commit all changes, then push current branch to origin."
  warn "If you have large binaries, consider using Git LFS."
  read -rp "Proceed to commit & push all changes? (y/N): " yn
  if [[ ! "${yn,,}" =~ ^(y|yes)$ ]]; then
    popd >/dev/null
    warn "Push cancelled by user."
    return 1
  fi

  if ! run_with_spinner "Adding all changes (git add -A)..." "git_add_all" git add -A; then
    popd >/dev/null
    handle_failure "git add failed."
    return 1
  fi

  local commit_msg
  read -rp "Commit message (default: 'chore: commit from codespace script'): " commit_msg
  commit_msg="${commit_msg:-chore: commit from codespace script}"

  # commit (if nothing to commit, git commit returns non-zero)
  if ! run_with_spinner "Committing changes..." "git_commit_all" git commit -m "$commit_msg"; then
    warn "git commit returned non-zero (maybe nothing to commit). Continuing to push."
  fi

  local head_branch
  head_branch=$(git rev-parse --abbrev-ref HEAD)
  if ! run_with_spinner "Pushing to origin/$head_branch..." "git_push_all" git push origin "$head_branch"; then
    popd >/dev/null
    handle_failure "git push failed."
    return 1
  fi

  ok "Repository pushed to origin/$head_branch"
  popd >/dev/null
  return 0
}

bersihkan_flutter() {
  local project_root
  project_root="$(find_project_root "$(pwd)")"
  if [[ -n "$project_root" ]]; then
    pushd "$project_root" >/dev/null
  fi

  warn "Running flutter clean and removing build/ directory..."
  if command -v flutter >/dev/null 2>&1; then
    run_with_spinner "flutter clean" "flutter_clean" flutter clean || { handle_failure "flutter clean failed."; [[ -n "$project_root" ]] && popd >/dev/null; return 1; }
  fi
  if [[ -n "$project_root" ]]; then
    run_with_spinner "Removing build/ directory" "rm_build" rm -rf build || { handle_failure "Removing build dir failed."; popd >/dev/null; return 1; }
    popd >/dev/null
  else
    run_with_spinner "Removing build/ directory in cwd" "rm_build" rm -rf build || { handle_failure "Removing build dir failed."; return 1; }
  fi
  ok "Cleanup finished."
  return 0
}

# MAIN MENU
main_menu() {
  while true; do
    echo
    echo -e "${BOLD}${CLR_CYAN}=== GitHub Codespace Flutter Android All-in-One Menu ===${CLR_RESET}"
    echo "API_LEVEL=$API_LEVEL  BUILD_TOOLS=$BUILD_TOOLS_VERSION  BUILD_TYPE=$BUILD_TYPE"
    echo "1) Siapkan requirement saja (JDK, Flutter, Android SDK tools)"
    echo "2) Build APK saja (jalankan dari root project Flutter)"
    echo "3) Keduanya (setup + build)"
    echo "4) Upload APK ke GitHub Release (cek APK; tawarkan build jika belum ada). If both debug & release exist -> choose debug/release/both."
    echo "5) Commit & Push whole repo to GitHub (git add -A; commit; push)"
    echo "6) Bersihkan Flutter (flutter clean + remove build/)"
    echo "7) Exit"
    read -rp "Pilih (1-7): " opt
    case "$opt" in
      1) install_requirements || true ;;
      2) build_apk || true ;;
      3) install_requirements || true; build_apk || true ;;
      4) upload_to_release "$(find_latest_apk)" || true ;;
      5) push_repo_all || true ;;
      6) bersihkan_flutter || true ;;
      7) ok "Keluar. Sampai jumpa!"; break ;;
      *) warn "Pilihan tidak valid. Pilih 1-7." ;;
    esac
  done
}

# Run
ensure_installed_basic
main_menu

exit 0
