#!/bin/bash

###############################################################################
# SSH Hardening Launcher (Debian / Ubuntu)
# Author: spookey007
#
# Usage:
#   sudo SSH_USER=myadmin SSH_PASS=StrongPass123 \
#        SSH_PORT=49221 PORTS="5060,5061,10000-20000" \
#        SSH_PUB_KEY="ssh-rsa AAAAB3NzaC1yc2E..." ./ssh_harden.sh
#
# Detects Debian vs Ubuntu, creates/updates SSH user, hardens SSH,
# optionally configures UFW and Fail2Ban. Continues if already installed.
###############################################################################

set -euo pipefail

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

banner() {
  echo -e "${MAGENTA}${BOLD}"
  echo "  ██   ██  █████  ██████  ██ ██████  ██ "
  echo "  ██   ██ ██   ██ ██   ██ ██ ██   ██ ██ "
  echo "  ███████ ███████ ██████  ██ ██████  ██ "
  echo "  ██   ██ ██   ██ ██   ██ ██ ██   ██ ██ "
  echo "  ██   ██ ██   ██ ██████  ██ ██████  ██ "
  echo "          HABIBI-SSH HARDENING"
  echo -e "${RESET}"
}

info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
success() { echo -e "${GREEN}[ OK ]${RESET} $*"; }
err()     { echo -e "${RED}[ERR]${RESET} $*" >&2; }

progress_bar() {
  local msg="${1:-Working}"
  local width=30
  echo -ne "${BLUE}${msg} ["
  for ((i=0; i<width; i++)); do
    echo -ne "#"
    sleep 0.03
  done
  echo -e "]${RESET}"
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-Y}"
  local hint
  [[ "$default" == "Y" ]] && hint="Y/n" || hint="y/N"
  local answer
  while true; do
    read -rp "$(echo -e "${BOLD}${prompt}${RESET} [${hint}]: ")" answer
    if [[ -z "$answer" ]]; then
      [[ "$default" == "Y" ]] && return 0 || return 1
    fi
    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Answer y or n." ;;
    esac
  done
}

if [[ "$EUID" -ne 0 ]]; then
  err "Run with sudo."
  exit 1
fi

[[ -f /etc/os-release ]] || { err "/etc/os-release not found."; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release

DISTRO_ID=${ID:-unknown}
DISTRO_LIKE=${ID_LIKE:-}
if [[ "$DISTRO_ID" == debian || "$DISTRO_ID" == ubuntu ]]; then
  DISTRO_FAMILY="debian"
elif [[ "$DISTRO_LIKE" == *debian* ]]; then
  DISTRO_FAMILY="debian"
else
  clear 2>/dev/null || true
  echo
  echo -e "${YELLOW}Detected OS: ${BOLD}${DISTRO_ID}${RESET}${YELLOW}.${RESET}"
  echo -e "${GREEN}Support for this OS is coming soon 😊${RESET}"
  echo
  exit 0
fi

# -----------------------------------------------------------------------------
# Ensure git is installed (runs separately, before any other steps)
# -----------------------------------------------------------------------------
if ! command -v git &>/dev/null; then
  info "Git not found. Installing git..."
  apt-get update -y -qq 2>/dev/null || true
  apt-get install -y git >/dev/null 2>&1 || { err "Failed to install git."; exit 1; }
  success "Git installed."
else
  success "Git already installed."
fi

SSH_USER=${SSH_USER:-"adminuser"}
SSH_PASS=${SSH_PASS:-"ChangeMe123!"}
SSH_PORT=${SSH_PORT:-$((RANDOM % 55535 + 10000))}
EXTRA_PORTS=${PORTS:-""}
SSH_PUB_KEY=${SSH_PUB_KEY:-""}

clear 2>/dev/null || true
banner

echo -e "${BOLD}Detected:${RESET} ${GREEN}${DISTRO_ID}${RESET} (${DISTRO_FAMILY})"
echo -e "${BOLD}User:${RESET} ${SSH_USER}  ${BOLD}Port:${RESET} ${SSH_PORT}  ${BOLD}Extra ports:${RESET} ${EXTRA_PORTS:-<none>}"
echo -e "${BOLD}SSH key:${RESET} $( [[ -n "$SSH_PUB_KEY" ]] && echo 'yes' || echo 'no' )"
echo

if ! prompt_yes_no "Continue?" "Y"; then
  warn "Aborted."
  exit 0
fi

INSTALL_UFW=false
INSTALL_F2B=false
prompt_yes_no "Configure UFW firewall?" "Y" && INSTALL_UFW=true
prompt_yes_no "Install and configure Fail2Ban?" "Y" && INSTALL_F2B=true
echo

progress_bar "Starting"

info "Updating package index..."
apt-get update -y >/dev/null 2>&1 || warn "apt update had issues, continuing."

info "Checking user ${SSH_USER}..."
if id "$SSH_USER" &>/dev/null; then
  warn "User ${SSH_USER} already exists; skipping user creation and password change. Doing hardening only."
  usermod -aG sudo "$SSH_USER" 2>/dev/null || true
else
  adduser --gecos "" --disabled-password "$SSH_USER"
  echo "${SSH_USER}:${SSH_PASS}" | chpasswd
  usermod -aG sudo "$SSH_USER" 2>/dev/null || true
fi

SSH_DIR="/home/${SSH_USER}/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown "${SSH_USER}:${SSH_USER}" "$SSH_DIR"

if [[ -n "$SSH_PUB_KEY" ]]; then
  echo "$SSH_PUB_KEY" > "${SSH_DIR}/authorized_keys"
  chmod 600 "${SSH_DIR}/authorized_keys"
  chown "${SSH_USER}:${SSH_USER}" "${SSH_DIR}/authorized_keys"
  success "SSH key installed."
else
  warn "No SSH_PUB_KEY; password login only."
fi

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="${SSHD_CONFIG}.bak.$(date +%F-%H%M%S)"
info "Backing up sshd_config to ${BACKUP}"
cp "$SSHD_CONFIG" "$BACKUP" 2>/dev/null || warn "Backup failed."

update_sshd() {
  local key="$1" val="$2"
  if grep -qiE "^${key}[[:space:]]" "$SSHD_CONFIG"; then
    sed -i "s|^${key}.*|${key} ${val}|I" "$SSHD_CONFIG"
  else
    echo "${key} ${val}" >> "$SSHD_CONFIG"
  fi
}

info "Hardening sshd_config..."
update_sshd "Port" "$SSH_PORT"
update_sshd "PermitRootLogin" "no"
PA_VALUE="no"
if [[ -z "$SSH_PUB_KEY" ]]; then
  warn "No SSH_PUB_KEY configured; disabling SSH password authentication can lock you out."
  if prompt_yes_no "Disable SSH password authentication anyway?" "N"; then
    PA_VALUE="no"
  else
    PA_VALUE="yes"
  fi
fi
update_sshd "PasswordAuthentication" "$PA_VALUE"
update_sshd "PubkeyAuthentication" "yes"
update_sshd "ChallengeResponseAuthentication" "no"
update_sshd "UsePAM" "yes"

if command -v sshd &>/dev/null; then
  sshd -t || { err "sshd -t failed."; exit 1; }
fi

if systemctl restart ssh 2>/dev/null; then
  success "SSH restarted (ssh)."
elif systemctl restart sshd 2>/dev/null; then
  success "SSH restarted (sshd)."
else
  err "Could not restart SSH."
fi

if [[ "$INSTALL_UFW" == true ]]; then
  if dpkg -s ufw &>/dev/null; then
    success "UFW already installed."
  else
    apt-get install -y ufw >/dev/null 2>&1 || warn "UFW install failed."
  fi
  if command -v ufw &>/dev/null; then
    ufw default deny incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true
    ufw allow "${SSH_PORT}/tcp" 2>/dev/null || true
    IFS=',' read -ra PA <<< "$EXTRA_PORTS"
    for p in "${PA[@]}"; do
      [[ -z "$p" ]] && continue
      ufw allow $p 2>/dev/null || true
    done
    ufw --force enable 2>/dev/null || true
    success "UFW configured."
  fi
else
  warn "UFW skipped."
fi

if [[ "$INSTALL_F2B" == true ]]; then
  if dpkg -s fail2ban &>/dev/null; then
    success "Fail2Ban already installed."
  else
    apt-get install -y fail2ban >/dev/null 2>&1 || warn "Fail2Ban install failed."
  fi
  if systemctl list-unit-files 2>/dev/null | grep -q fail2ban; then
    systemctl enable fail2ban 2>/dev/null || true
    systemctl start fail2ban 2>/dev/null || true
    mkdir -p /etc/fail2ban/jail.d
    JAIL="/etc/fail2ban/jail.d/ssh-hardening.conf"
    cat > "$JAIL" <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
maxretry = 5
bantime = 3600
EOF
    systemctl restart fail2ban 2>/dev/null || true
    success "Fail2Ban configured."
  fi
else
  warn "Fail2Ban skipped."
fi

if [[ "$DISTRO_ID" == debian && -x "./debian/ssh_harden_extra.sh" ]]; then
  info "Running Debian extra script..."
  ./debian/ssh_harden_extra.sh || warn "Debian extra script failed."
fi
if [[ "$DISTRO_ID" == ubuntu && -x "./ubuntu/ssh_harden_extra.sh" ]]; then
  info "Running Ubuntu extra script..."
  ./ubuntu/ssh_harden_extra.sh || warn "Ubuntu extra script failed."
fi

echo
echo -e "${GREEN}${BOLD}========= SSH HARDENING DONE =========${RESET}"
echo -e "  ${BOLD}User:${RESET} ${SSH_USER}   ${BOLD}Port:${RESET} ${SSH_PORT}"
echo -e "  ${BOLD}UFW:${RESET} $([[ "$INSTALL_UFW" == true ]] && echo 'on' || echo 'skipped')   ${BOLD}Fail2Ban:${RESET} $([[ "$INSTALL_F2B" == true ]] && echo 'on' || echo 'skipped')"
echo -e "  ${CYAN}ssh -p ${SSH_PORT} ${SSH_USER}@<server>${RESET}"
echo
