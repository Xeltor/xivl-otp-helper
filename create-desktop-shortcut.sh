#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
START_SCRIPT="${PROJECT_DIR}/start-ffxiv.sh"
BUNDLED_ICON_SOURCE="${PROJECT_DIR}/assets/icons/xivlauncher.svg"
USER_ICON_DIR="${HOME}/.local/share/icons/hicolor/scalable/apps"
USER_ICON_PATH="${USER_ICON_DIR}/xivl-otp-helper-xivlauncher.svg"
APPLICATIONS_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${APPLICATIONS_DIR}/final-fantasy-xiv-online.desktop"
DESKTOP_NAME="Final Fantasy XIV Online"
ICON_VALUE=""
ICON_STATUS="No suitable icon was found."
FINAL_MESSAGE=""

shopt -s nullglob

log() {
  printf '%s\n' "$*"
}

warn() {
  printf '%s\n' "$*" >&2
}

pause_before_exit() {
  if [[ -t 0 || -t 1 ]]; then
    printf '\nPress Enter to close...'
    read -r _
  fi
}

show_final_status() {
  local exit_code="$1"

  printf '\n'
  if [[ "${exit_code}" -eq 0 ]]; then
    log "Shortcut creation completed successfully."
    log "Desktop file: ${DESKTOP_FILE}"
  else
    warn "Shortcut creation failed."
    if [[ -n "${FINAL_MESSAGE}" ]]; then
      warn "${FINAL_MESSAGE}"
    fi
  fi

  log "${ICON_STATUS}"
  pause_before_exit
}

on_exit() {
  local exit_code="$1"
  show_final_status "${exit_code}"
}

die() {
  FINAL_MESSAGE="$1"
  warn "Error: ${FINAL_MESSAGE}"
  exit 1
}

trap 'on_exit $?' EXIT

desktop_escape_exec() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

looks_relevant_text() {
  local value="${1,,}"
  [[ "${value}" == *"xivlauncher"* || "${value}" == *"final fantasy xiv"* || "${value}" == *"ffxiv"* ]]
}

is_icon_file() {
  local path="$1"
  [[ -f "${path}" ]] || return 1
  case "${path##*.}" in
    png|svg|xpm|ico)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

install_bundled_icon() {
  [[ -f "${BUNDLED_ICON_SOURCE}" ]] || return 1

  mkdir -p "${USER_ICON_DIR}"
  cp -f "${BUNDLED_ICON_SOURCE}" "${USER_ICON_PATH}"
  printf '%s\n' "${USER_ICON_PATH}"
}

parse_desktop_value() {
  local key="$1"
  local file="$2"
  awk -F= -v wanted="${key}" '
    $0 ~ /^[[:space:]]*[#;]/ { next }
    $1 == wanted {
      sub(/^[^=]*=/, "", $0)
      print $0
      exit
    }
  ' "${file}"
}

desktop_file_looks_relevant() {
  local file="$1"
  local base name exec_line icon_line

  base="$(basename "${file}")"
  if looks_relevant_text "${base}"; then
    return 0
  fi

  name="$(parse_desktop_value "Name" "${file}" || true)"
  exec_line="$(parse_desktop_value "Exec" "${file}" || true)"
  icon_line="$(parse_desktop_value "Icon" "${file}" || true)"

  looks_relevant_text "${name}" || looks_relevant_text "${exec_line}" || looks_relevant_text "${icon_line}"
}

icon_name_from_path() {
  local path="$1"
  local name
  name="$(basename "${path}")"
  printf '%s' "${name%.*}"
}

find_local_icon_file() {
  local dir
  local -a search_dirs=(
    "${HOME}/.local/share/icons"
    "${HOME}/.icons"
    "/usr/share/icons"
    "${HOME}/.local/share/Steam"
    "${HOME}/.steam/steam"
    "${HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"
  )

  for dir in "${search_dirs[@]}"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r path; do
      printf '%s\n' "${path}"
      return 0
    done < <(
      find "${dir}" -type f \( \
        -iname '*xivlauncher*.png' -o -iname '*xivlauncher*.svg' -o -iname '*xivlauncher*.xpm' -o \
        -iname '*ffxiv*.png' -o -iname '*ffxiv*.svg' -o -iname '*ffxiv*.xpm' -o \
        -iname '*final*fantasy*xiv*.png' -o -iname '*final*fantasy*xiv*.svg' -o -iname '*final*fantasy*xiv*.xpm' \
      \) 2>/dev/null | sort
    )
  done

  return 1
}

find_icon_from_relevant_desktop_file() {
  local dir file icon_value
  local -a desktop_dirs=(
    "${HOME}/.local/share/applications"
    "/usr/share/applications"
    "${HOME}/.local/share/Steam"
    "${HOME}/.steam/steam"
    "${HOME}/.var/app/com.valvesoftware.Steam/.local/share/Steam"
  )

  for dir in "${desktop_dirs[@]}"; do
    [[ -d "${dir}" ]] || continue
    while IFS= read -r file; do
      if ! desktop_file_looks_relevant "${file}"; then
        continue
      fi

      icon_value="$(parse_desktop_value "Icon" "${file}" || true)"
      [[ -n "${icon_value}" ]] || continue

      if [[ "${icon_value}" = /* ]] && is_icon_file "${icon_value}"; then
        printf '%s\n' "${icon_value}"
        return 0
      fi

      if [[ "${icon_value}" != */* ]]; then
        printf '%s\n' "${icon_value}"
        return 0
      fi
    done < <(find "${dir}" -type f -name '*.desktop' 2>/dev/null | sort)
  done

  return 1
}

choose_icon() {
  local icon

  if icon="$(install_bundled_icon)"; then
    printf '%s\n' "${icon}"
    return 0
  fi

  if is_icon_file "${BUNDLED_ICON_SOURCE}"; then
    printf '%s\n' "${BUNDLED_ICON_SOURCE}"
    return 0
  fi

  if icon="$(find_local_icon_file)"; then
    printf '%s\n' "${icon}"
    return 0
  fi

  if icon="$(find_icon_from_relevant_desktop_file)"; then
    printf '%s\n' "${icon}"
    return 0
  fi

  return 1
}

if [[ ! -f "${START_SCRIPT}" ]]; then
  die "Could not find launcher script at ${START_SCRIPT}."
fi

mkdir -p "${APPLICATIONS_DIR}"
chmod +x "${START_SCRIPT}" 2>/dev/null || true

if ICON_VALUE="$(choose_icon)"; then
  if [[ "${ICON_VALUE}" == "${USER_ICON_PATH}" ]]; then
    ICON_STATUS="Icon used: ${ICON_VALUE} (installed from bundled project icon)"
    log "Using installed bundled icon: ${ICON_VALUE}"
  elif [[ "${ICON_VALUE}" == "${BUNDLED_ICON_SOURCE}" ]]; then
    ICON_STATUS="Icon used: ${ICON_VALUE} (bundled project icon)"
    log "Using bundled project icon: ${ICON_VALUE}"
  elif [[ "${ICON_VALUE}" = /* ]]; then
    ICON_STATUS="Icon used: ${ICON_VALUE}"
    log "Using fallback local icon: ${ICON_VALUE}"
  else
    ICON_STATUS="Icon used: ${ICON_VALUE} (icon name from an existing desktop entry)"
    log "Using fallback icon name from existing desktop entry: ${ICON_VALUE}"
  fi
else
  ICON_STATUS="No suitable icon was found. The shortcut was created without an icon."
  log "No bundled or local FFXIV/XIVLauncher icon was found; creating shortcut without an icon."
fi

EXEC_VALUE="$(desktop_escape_exec "${START_SCRIPT}")"

{
  printf '[Desktop Entry]\n'
  printf 'Version=1.0\n'
  printf 'Type=Application\n'
  printf 'Name=%s\n' "${DESKTOP_NAME}"
  printf 'Exec=%s\n' "${EXEC_VALUE}"
  printf 'Terminal=false\n'
  printf 'Categories=Game;\n'
  printf 'StartupNotify=true\n'
  if [[ -n "${ICON_VALUE}" ]]; then
    printf 'Icon=%s\n' "${ICON_VALUE}"
  fi
} > "${DESKTOP_FILE}"

chmod 755 "${DESKTOP_FILE}"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${APPLICATIONS_DIR}" >/dev/null 2>&1 || true
fi

FINAL_MESSAGE="Created desktop shortcut at ${DESKTOP_FILE}"
log "${FINAL_MESSAGE}"
