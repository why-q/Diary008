#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

CALLER_DIR="$(pwd -P)"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)"

# Tool installations commonly live beside a checkout. For linked worktrees,
# also inspect beside the shared repository without depending on its location.
TOOL_ROOTS=("$PROJECT_ROOT/../tools")
COMMON_GIT_DIR="$(git -C "$PROJECT_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [[ -n "$COMMON_GIT_DIR" && -d "$COMMON_GIT_DIR" ]]; then
  COMMON_REPO_ROOT="$(CDPATH= cd -- "$COMMON_GIT_DIR/.." 2>/dev/null && pwd -P || true)"
  if [[ -n "$COMMON_REPO_ROOT" ]]; then
    TOOL_ROOTS+=("$COMMON_REPO_ROOT/../tools")
  fi
fi

resolve_command() {
  local requested="$1"
  local result
  if [[ "$requested" == */* ]]; then
    result="$requested"
    [[ "$result" == /* ]] || result="$CALLER_DIR/$result"
  else
    result="$(command -v "$requested" 2>/dev/null || true)"
    [[ -n "$result" ]] || return 1
    [[ "$result" == /* ]] || result="$CALLER_DIR/$result"
  fi
  [[ -x "$result" ]] || return 1
  printf '%s\n' "$result"
}

# FLUTTER_BIN wins over FLUTTER_ROOT; otherwise use PATH and common locations.
FLUTTER_CMD=""
if [[ -n "${FLUTTER_BIN:-}" ]]; then
  FLUTTER_CMD="$(resolve_command "$FLUTTER_BIN" || true)"
  [[ -n "$FLUTTER_CMD" ]] || fail "FLUTTER_BIN is not executable: $FLUTTER_BIN"
elif [[ -n "${FLUTTER_ROOT:-}" ]]; then
  FLUTTER_CMD="$(resolve_command "$FLUTTER_ROOT/bin/flutter" || true)"
  [[ -n "$FLUTTER_CMD" ]] || fail "FLUTTER_ROOT has no executable bin/flutter: $FLUTTER_ROOT"
else
  FLUTTER_CMD="$(resolve_command flutter || true)"
  if [[ -z "$FLUTTER_CMD" ]]; then
    for tool_root in "${TOOL_ROOTS[@]}" "${HOME:-}/development" "${HOME:-}/flutter"; do
      candidate="$tool_root/flutter/bin/flutter"
      if [[ -x "$candidate" ]]; then
        FLUTTER_CMD="$candidate"
        break
      fi
    done
  fi
  [[ -n "$FLUTTER_CMD" ]] || fail "Flutter not found; set FLUTTER_BIN or FLUTTER_ROOT, or add flutter to PATH"
fi

java_home_from_binary() {
  local binary="$1"
  local link
  local hops=0
  [[ "$binary" == /* ]] || binary="$CALLER_DIR/$binary"
  while [[ -L "$binary" && "$hops" -lt 40 ]]; do
    command -v readlink >/dev/null 2>&1 || break
    link="$(readlink "$binary" 2>/dev/null || true)"
    [[ -n "$link" ]] || break
    if [[ "$link" == /* ]]; then
      binary="$link"
    else
      binary="$(dirname -- "$binary")/$link"
    fi
    hops=$((hops + 1))
  done
  CDPATH= cd -- "$(dirname -- "$binary")/.." 2>/dev/null && pwd -P
}

is_jdk17() {
  local home="$1"
  local version_output major
  [[ -x "$home/bin/java" && -x "$home/bin/javac" ]] || return 1
  version_output="$("$home/bin/java" -version 2>&1)" || return 1
  if [[ "$version_output" =~ version[[:space:]]+\"?([0-9]+) ]]; then
    major="${BASH_REMATCH[1]}"
  elif [[ "$version_output" =~ openjdk[[:space:]]+([0-9]+) ]]; then
    major="${BASH_REMATCH[1]}"
  else
    return 1
  fi
  [[ "$major" == 17 ]]
}

if [[ -n "${JAVA_HOME:-}" ]]; then
  [[ -d "$JAVA_HOME" ]] || fail "JAVA_HOME is not a directory: $JAVA_HOME"
  JAVA_HOME="$(CDPATH= cd -- "$JAVA_HOME" && pwd -P)"
  is_jdk17 "$JAVA_HOME" || fail "JAVA_HOME must point to a JDK 17 installation: $JAVA_HOME"
else
  JAVA_CANDIDATES=()
  PATH_JAVA="$(command -v java 2>/dev/null || true)"
  if [[ -n "$PATH_JAVA" ]]; then
    PATH_JAVA_HOME="$(java_home_from_binary "$PATH_JAVA" || true)"
    [[ -z "$PATH_JAVA_HOME" ]] || JAVA_CANDIDATES+=("$PATH_JAVA_HOME")
  fi
  for tool_root in "${TOOL_ROOTS[@]}"; do
    JAVA_CANDIDATES+=("$tool_root/java" "$tool_root/jdk-17")
  done
  JAVA_CANDIDATES+=("${HOME:-}/.sdkman/candidates/java/current" "${HOME:-}/.jdks"/* /usr/lib/jvm/java-17* /usr/lib/jvm/* /opt/java/openjdk)
  if [[ -n "${ANDROID_STUDIO_HOME:-}" ]]; then
    JAVA_CANDIDATES+=("$ANDROID_STUDIO_HOME/jbr" "$ANDROID_STUDIO_HOME/jre")
  fi
  JAVA_CANDIDATES+=("/Applications/Android Studio.app/Contents/jbr/Contents/Home")
  JAVA_HOME=""
  for candidate in "${JAVA_CANDIDATES[@]}"; do
    if [[ -d "$candidate" ]] && is_jdk17 "$candidate"; then
      JAVA_HOME="$(CDPATH= cd -- "$candidate" && pwd -P)"
      break
    fi
  done
  [[ -n "$JAVA_HOME" ]] || fail "JDK 17 not found; set JAVA_HOME to a JDK 17 installation"
fi
export JAVA_HOME

is_android_sdk() {
  local sdk="$1"
  [[ -d "$sdk" ]] && { [[ -d "$sdk/platforms" ]] || [[ -d "$sdk/platform-tools" ]] || [[ -d "$sdk/cmdline-tools" ]] || [[ -d "$sdk/build-tools" ]]; }
}

if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
  ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT%/}"
elif [[ -n "${ANDROID_HOME:-}" ]]; then
  ANDROID_SDK_ROOT="${ANDROID_HOME%/}"
else
  ANDROID_SDK_CANDIDATES=()
  PATH_ADB="$(command -v adb 2>/dev/null || true)"
  if [[ -n "$PATH_ADB" ]]; then
    if command -v readlink >/dev/null 2>&1; then
      RESOLVED_ADB="$(readlink -f "$PATH_ADB" 2>/dev/null || true)"
      [[ -z "$RESOLVED_ADB" ]] || PATH_ADB="$RESOLVED_ADB"
    fi
    ADB_DIR="$(dirname -- "$PATH_ADB")"
    if [[ "$(basename -- "$ADB_DIR")" == platform-tools ]]; then
      ANDROID_SDK_CANDIDATES+=("$(dirname -- "$ADB_DIR")")
    fi
  fi
  for tool_root in "${TOOL_ROOTS[@]}"; do
    ANDROID_SDK_CANDIDATES+=("$tool_root/android-sdk")
  done
  ANDROID_SDK_CANDIDATES+=("${HOME:-}/Android/Sdk" "${HOME:-}/Android/sdk" "${HOME:-}/Library/Android/sdk" /opt/android-sdk /usr/lib/android-sdk)
  if [[ -n "${ANDROID_STUDIO_HOME:-}" ]]; then
    ANDROID_SDK_CANDIDATES+=("$ANDROID_STUDIO_HOME/sdk")
  fi
  ANDROID_SDK_ROOT=""
  for candidate in "${ANDROID_SDK_CANDIDATES[@]}"; do
    if is_android_sdk "$candidate"; then
      ANDROID_SDK_ROOT="$(CDPATH= cd -- "$candidate" && pwd -P)"
      break
    fi
  done
  [[ -n "$ANDROID_SDK_ROOT" ]] || fail "Android SDK not found; set ANDROID_SDK_ROOT or ANDROID_HOME"
fi
is_android_sdk "$ANDROID_SDK_ROOT" || fail "Android SDK directory is invalid: $ANDROID_SDK_ROOT"
ANDROID_SDK_ROOT="$(CDPATH= cd -- "$ANDROID_SDK_ROOT" && pwd -P)"
export ANDROID_SDK_ROOT
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$(dirname -- "$FLUTTER_CMD"):$JAVA_HOME/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

cd "$PROJECT_ROOT"
printf 'Project: %s\n' "$PROJECT_ROOT"
printf 'Flutter: %s\n' "$FLUTTER_CMD"
printf 'JDK: %s\n' "$JAVA_HOME"
printf 'Android SDK: %s\n' "$ANDROID_SDK_ROOT"
printf '\nPreparing Flutter dependencies...\n'
"$FLUTTER_CMD" pub get
printf '\nBuilding arm64-only Debug APK...\n'
# Split the single selected ABI so Flutter plugins cannot package extra JNI architectures.
"$FLUTTER_CMD" build apk --debug --target-platform android-arm64 --split-per-abi

APK_PATH="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk"
[[ -s "$APK_PATH" ]] || fail "Build completed without a non-empty APK at $APK_PATH"
ABI_LIST="$("$JAVA_HOME/bin/jar" tf "$APK_PATH" | awk -F/ '$1 == "lib" && NF >= 3 && $3 != "" { print $2 }' | LC_ALL=C sort -u)"
[[ "$ABI_LIST" == arm64-v8a ]] || fail "APK must contain only arm64-v8a native libraries; found: ${ABI_LIST:-none}"

if command -v sha256sum >/dev/null 2>&1; then
  SHA256="$(sha256sum "$APK_PATH" | awk 'NR == 1 { print $1 }')"
elif command -v shasum >/dev/null 2>&1; then
  SHA256="$(shasum -a 256 "$APK_PATH" | awk 'NR == 1 { print $1 }')"
else
  fail "Neither sha256sum nor shasum is available"
fi
SIZE_BYTES="$(wc -c < "$APK_PATH" | tr -d '[:space:]')"
printf '\nVerified APK contains only ABI: %s\n' "$ABI_LIST"
printf 'APK: %s\nSize: %s bytes\nSHA-256: %s\n' "$APK_PATH" "$SIZE_BYTES" "$SHA256"
