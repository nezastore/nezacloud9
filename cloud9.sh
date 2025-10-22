#!/usr/bin/env bash
# =====================================================================
# Cloud9 Installer — NEZASTORE Edition (WIB + auto credential)
# Supports: Ubuntu/Debian
# Maintainer: NEZASTORE
# =====================================================================

set -o pipefail

# =========================[ THEME & UI ]==============================
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

FG_CYAN="\033[1;36m"
FG_BLUE="\033[1;34m"
FG_GREEN="\033[1;32m"
FG_YELLOW="\033[1;33m"
FG_RED="\033[1;31m"
FG_MAGENTA="\033[1;35m"
FG_WHITE="\033[1;37m"
FG_GRAY="\033[0;37m"

NEZA_WATERMARK="${DIM}— Powered by NEZASTORE —${RESET}"

step()   { echo -e "${FG_BLUE}${BOLD}➤ $1${RESET}"; }
ok()     { echo -e "${FG_GREEN}✔ $1${RESET}"; }
warn()   { echo -e "${FG_YELLOW}⚠ $1${RESET}"; }
err()    { echo -e "${FG_RED}✘ $1${RESET}"; }
info()   { echo -e "${FG_CYAN}ℹ $1${RESET}"; }

spinner_pid=""
start_spinner() {
  local msg="$1"
  printf "%b" "${FG_MAGENTA}⏳ ${msg}..."${RESET}
  ( while :; do for c in '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'; do
      printf "\r%b" "${FG_MAGENTA}${c} ${msg}...${RESET}"
      sleep 0.1
    done
  done ) &
  spinner_pid=$!
  disown
}
stop_spinner() {
  if [[ -n "$spinner_pid" ]]; then
    kill "$spinner_pid" >/dev/null 2>&1 || true
    spinner_pid=""
    printf "\r%*s\r" 80 " "
  fi
}

banner() {
  clear
  echo -e "${FG_CYAN}${BOLD}=================================================${RESET}"
  echo -e "${FG_GREEN}${BOLD}🚀 Cloud9 Installation Script — STORE Edition${RESET}"
  echo -e "${FG_CYAN}${BOLD}=================================================${RESET}"
  echo -e " ${_WATERMARK}\n"
}

# =========================[ CONFIG ]==================================
C9_IMAGE="lscr.io/linuxserver/cloud9:latest"
C9_NAME="cloud9-nezastore"
C9_PORT="8000"

# === AUTO USERNAME & PASSWORD ===
USERNAME="kontol"
PASSWORD="kontol"

C9_WORKDIR="/opt/nezastore/cloud9/workspace"
C9_CONFIG="/opt/nezastore/cloud9/config"
THEME_URL="https://raw.githubusercontent.com/priv8-app/cloud9/refs/heads/main/user.settings"
LOG_FILE="/var/log/cloud9_install.log"

# =========================[ GUARDRAILS ]==============================
need_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Please run as root (sudo)."
    exit 1
  fi
}
trap 'stop_spinner; echo; err "Unexpected error. Check log: $LOG_FILE"; exit 1' ERR

# =========================[ HELPERS ]=================================
log_run() { bash -lc "$*" 2>&1 | tee -a "$LOG_FILE"; }
detect_os() {
  . /etc/os-release
  echo "${ID}"
}
ensure_pkg() {
  local pkgs=("$@")
  apt-get update -y >>"$LOG_FILE" 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}" >>"$LOG_FILE" 2>&1
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    ok "Docker already installed."
    return
  fi
  step "Installing Docker runtime"
  start_spinner "Installing docker.io"
  ensure_pkg docker.io
  stop_spinner
  systemctl enable --now docker >>"$LOG_FILE" 2>&1 || true
  ok "Docker installed & running."
}

fetch_public_ip() {
  local ip
  ip=$(curl -fsS ifconfig.me || curl -fsS ipinfo.io/ip || echo "localhost")
  echo "$ip"
}

# =========================[ MAIN ]====================================
main() {
  banner
  need_root

  step "Detecting Linux distribution"
  if [[ ! -f /etc/os-release ]]; then
    err "Cannot detect OS. Aborting."
    exit 1
  fi
  OS=$(detect_os)
  info "Detected: ${BOLD}${OS}${RESET}"
  if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    err "Unsupported OS: $OS. Only Ubuntu/Debian supported."
    exit 1
  fi

  step "Setting timezone & locale to Asia/Jakarta (WIB)"
  timedatectl set-timezone Asia/Jakarta >>"$LOG_FILE" 2>&1
  update-locale LANG=id_ID.UTF-8 >>"$LOG_FILE" 2>&1
  ok "Timezone and locale set to WIB."

  step "System update & base tools"
  start_spinner "Installing curl, git, ca-certificates"
  ensure_pkg curl git ca-certificates lsb-release apt-transport-https
  stop_spinner
  ok "Base tools ready."

  ensure_docker

  step "Preparing workspace directories"
  start_spinner "Creating folders"
  mkdir -p "$C9_WORKDIR" "$C9_CONFIG"
  stop_spinner
  ok "Folders ready."

  PUID=${SUDO_UID:-1000}
  PGID=${SUDO_GID:-1000}

  step "Pulling Cloud9 image"
  start_spinner "docker pull $C9_IMAGE"
  docker pull "$C9_IMAGE" >>"$LOG_FILE" 2>&1
  stop_spinner
  ok "Image pulled."

  if docker ps -a --format '{{.Names}}' | grep -q "^${C9_NAME}$"; then
    warn "Old container found. Removing..."
    docker rm -f "$C9_NAME" >>"$LOG_FILE" 2>&1 || true
  fi

  step "Running Cloud9 container"
  start_spinner "Starting $C9_NAME"
  docker run -d \
    --name "$C9_NAME" \
    -e PUID="$PUID" \
    -e PGID="$PGID" \
    -e TZ="Asia/Jakarta" \
    -e USERNAME="$USERNAME" \
    -e PASSWORD="$PASSWORD" \
    -p "${C9_PORT}:8000" \
    -v "$C9_WORKDIR:/workspace" \
    -v "$C9_CONFIG:/config" \
    "$C9_IMAGE" >>"$LOG_FILE" 2>&1
  stop_spinner
  ok "Cloud9 running."

  step "Applying theme configuration"
  start_spinner "Downloading user.settings"
  TMP="/tmp/user.settings"
  curl -fsSL "$THEME_URL" -o "$TMP" >>"$LOG_FILE" 2>&1 || true
  if [[ -s "$TMP" ]]; then
    docker exec "$C9_NAME" mkdir -p /config/.c9 >>"$LOG_FILE" 2>&1
    docker cp "$TMP" "${C9_NAME}:/config/.c9/user.settings" >>"$LOG_FILE" 2>&1
    ok "Theme applied."
  else
    warn "Failed to fetch theme."
  fi
  stop_spinner

  docker restart "$C9_NAME" >>"$LOG_FILE" 2>&1
  ok "Container restarted."

  PUBLIC_IP=$(fetch_public_ip)

  echo
  echo -e "${FG_BLUE}${BOLD}===========================================${RESET}"
  echo -e "${FG_GREEN}${BOLD}🎉 Cloud9 Setup Completed Successfully 🎉${RESET}"
  echo -e "${FG_BLUE}${BOLD}===========================================${RESET}"
  echo -e "${FG_YELLOW}🌐 Access: ${FG_WHITE}${BOLD}http://${PUBLIC_IP}:${C9_PORT}${RESET}"
  echo -e "${FG_YELLOW}👤 Username: ${FG_WHITE}${BOLD}${USERNAME}${RESET}"
  echo -e "${FG_YELLOW}🔒 Password: ${FG_WHITE}${BOLD}${PASSWORD}${RESET}"
  echo -e "${FG_BLUE}${BOLD}===========================================${RESET}"
  echo -e "Log file: ${FG_GRAY}$LOG_FILE${RESET}"
  echo -e "Workspace: ${FG_GRAY}$C9_WORKDIR${RESET}"
  echo -e "Config   : ${FG_GRAY}$C9_CONFIG${RESET}"
  echo -e "\n${NEZA_WATERMARK}\n"
}

main "$@"
