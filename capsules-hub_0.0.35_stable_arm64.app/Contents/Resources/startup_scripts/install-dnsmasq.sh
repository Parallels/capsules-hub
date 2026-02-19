#!/bin/bash
# install-dnsmasq.sh
# Idempotent installer for a bundled dnsmasq on macOS
# - Installs custom dnsmasq into /usr/local/bin (if different)
# - Ensures /usr/local/etc/parallels-dnsmasq.conf has desired IP/domain
# - Ensures /etc/resolver/<domain> points to a desired nameserver (default 127.0.0.1)
# - Installs/updates a launchd daemon at /Library/LaunchDaemons/com.parallels.dnsmasq.plist
# - Restarts service only if something actually changed

set -euo pipefail

LOG_PREFIX="[install-dnsmasq]"

### -------------------------- Defaults & Paths --------------------------
if [ -n "${CAPSULE_SCRIPT_SOURCE_DIR:-}" ]; then
  if [ -d "${CAPSULE_SCRIPT_SOURCE_DIR}" ]; then
    SCRIPT_DIR="${CAPSULE_SCRIPT_SOURCE_DIR}"
  else
    echo "${LOG_PREFIX} CAPSULE_SCRIPT_SOURCE_DIR='${CAPSULE_SCRIPT_SOURCE_DIR}' is not a directory" >&2
    exit 1
  fi
else
  if ! SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"; then
    echo "${LOG_PREFIX} Failed to resolve script directory" >&2
    exit 1
  fi
fi

if [ -n "${CAPSULE_RESOURCE_ROOT:-}" ]; then
  if [ -d "${CAPSULE_RESOURCE_ROOT}/dnsmasq" ]; then
    RESOURCE_DIR="${CAPSULE_RESOURCE_ROOT}/dnsmasq"
  else
    echo "${LOG_PREFIX} CAPSULE_RESOURCE_ROOT='${CAPSULE_RESOURCE_ROOT}' does not contain dnsmasq" >&2
    exit 1
  fi
else
  if ! RESOURCE_DIR="$(cd "${SCRIPT_DIR}/../dnsmasq" 2>/dev/null && pwd)"; then
    echo "${LOG_PREFIX} Failed to locate dnsmasq resources from ${SCRIPT_DIR}" >&2
    exit 1
  fi
fi
DNSMASQ_SOURCE="${RESOURCE_DIR}/dnsmasq"

DNSMASQ_TARGET="/usr/local/bin/dnsmasq"
CONFIG_DIR="/usr/local/etc"
CONFIG_FILE="${CONFIG_DIR}/parallels-dnsmasq.conf"

DEFAULT_DOMAIN="parallels.private"
RESOLVER_DIR="/etc/resolver"
# RESOLVER_FILE is computed after args (depends on domain)
RESOLVER_NAMESERVER_DEFAULT="127.0.0.1"

LAUNCHD_PLIST="/Library/LaunchDaemons/com.parallels.dnsmasq.plist"
SERVICE_LABEL="com.parallels.dnsmasq"


### -------------------------- CLI / Usage -------------------------------
usage() {
  cat <<USAGE
Usage: $(basename "$0") [--host-ip <ip>] [--domain <dns-suffix>] [--resolver-ip <ip>] [--force-restart] [-h]

Options:
  --host-ip, --ip       IP that dnsmasq should resolve <domain> to (default: 127.0.0.1)
  --domain              DNS suffix to serve (default: ${DEFAULT_DOMAIN})
  --resolver-ip         The resolver nameserver to write into /etc/resolver/<domain> (default: 127.0.0.1)
  --force-restart       Force a service restart even if no files changed
  -h, --help            Show this help message
USAGE
}

HOST_IP="127.0.0.1"
DOMAIN="${DEFAULT_DOMAIN}"
RESOLVER_IP="${RESOLVER_NAMESERVER_DEFAULT}"
FORCE_RESTART="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --host-ip|--ip) shift; HOST_IP="${1:?missing value for --host-ip}"; shift;;
    --domain) shift; DOMAIN="${1:?missing value for --domain}"; shift;;
    --resolver-ip) shift; RESOLVER_IP="${1:?missing value for --resolver-ip}"; shift;;
    --force-restart) FORCE_RESTART="true"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Error: unknown argument '$1'" >&2; usage; exit 1;;
  esac
done

RESOLVER_FILE="${RESOLVER_DIR}/${DOMAIN}"

### -------------------------- Helpers -----------------------------------
log() { echo "${LOG_PREFIX} $*"; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This script must run as root (sudo)."; exit 1
  fi
}

# Write content atomically if different; sets a flag if changed
# args: <target> <mode> <content-var-name> <changed-flag-name>
write_if_changed() {
  local target="$1" mode="$2" content_var="$3" changed_flag_name="$4"
  local tmp
  tmp="$(mktemp)"

  # Indirect expansion: 'content_var' holds the name of the variable with the content
  # shellcheck disable=SC2086
  local content="${!content_var}"

  # Write temp and compare
  printf '%s' "$content" > "$tmp"
  if [ ! -f "$target" ] || ! cmp -s "$tmp" "$target"; then
    install -m "$mode" "$tmp" "$target"
    # Mark the caller's flag as true
    # shellcheck disable=SC2086
    eval "$changed_flag_name=true"
  fi

  # Explicit cleanup (avoid RETURN trap + set -u issues)
  rm -f "${tmp:-}"
}


ensure_dir() {
  local d="$1" mode="${2:-755}"
  install -d -m "$mode" "$d"
}

set_owner_perms_if_needed() {
  # Ensure root:wheel and given mode if not already
  local path="$1" mode="$2"
  local changed=false

  # owner/group
  local owner group
  owner="$(stat -f %Su "$path" 2>/dev/null || echo "")"
  group="$(stat -f %Sg "$path" 2>/dev/null || echo "")"
  if [ "$owner" != "root" ] || [ "$group" != "wheel" ]; then
    chown root:wheel "$path"
    changed=true
  fi

  # mode
  local curmode
  curmode="$(stat -f %Lp "$path" 2>/dev/null || echo "")"
  if [ "$curmode" != "$mode" ]; then
    chmod "$mode" "$path"
    changed=true
  fi

  $changed && return 0 || return 1
}

service_is_loaded() {
  # returns 0 if listed; non-zero otherwise
  launchctl list "$SERVICE_LABEL" >/dev/null 2>&1
}

restart_service() {
  # Try bootout/bootstrap; fallback to unload/load for older behavior
  if service_is_loaded; then
    launchctl bootout system "$LAUNCHD_PLIST" >/dev/null 2>&1 || launchctl unload "$LAUNCHD_PLIST" >/dev/null 2>&1 || true
  fi
  launchctl bootstrap system "$LAUNCHD_PLIST" >/dev/null 2>&1 || launchctl load "$LAUNCHD_PLIST"
}

### -------------------------- Stages ------------------------------------
STAGE_BIN_CHANGED=false
STAGE_CFG_CHANGED=false
STAGE_RESOLVER_CHANGED=false
STAGE_PLIST_CHANGED=false
SERVICE_RESTARTED=false

stage_binary() {
  log "Stage: make pid file dir"
  mkdir -p "/opt/homebrew/var/run/dnsmasq"
  
  log "Stage: dnsmasq binary"
  if [ ! -f "$DNSMASQ_SOURCE" ]; then
    log "  ERROR: dnsmasq binary not found at ${DNSMASQ_SOURCE}"
    exit 1
  fi

  ensure_dir "/usr/local/bin" 755


  if [ ! -f "$DNSMASQ_TARGET" ] || ! cmp -s "$DNSMASQ_SOURCE" "$DNSMASQ_TARGET"; then
    log "  Installing/Updating ${DNSMASQ_TARGET}"
    install -m 755 "$DNSMASQ_SOURCE" "$DNSMASQ_TARGET"
    STAGE_BIN_CHANGED=true
  else
    log "  OK (no change)"
  fi
}

stage_config() {
  log "Stage: dnsmasq config @ ${CONFIG_FILE}"
  ensure_dir "$CONFIG_DIR" 755

  # If an existing config is present, try to preserve unrelated lines but ensure our required lines are correct.
  local desired="listen-address=127.0.0.1
bind-interfaces
domain-needed
bogus-priv
address=/${DOMAIN}/${HOST_IP}
"

  # Simple replace strategy: if file exists, rewrite only if content differs from our desired set.
  # If you need to preserve custom additions, you can enhance this with a merge step.
  write_if_changed "$CONFIG_FILE" 644 desired STAGE_CFG_CHANGED

  if [ "$STAGE_CFG_CHANGED" = true ]; then
    log "  Wrote updated config (domain=${DOMAIN}, host-ip=${HOST_IP})"
  else
    # If not changed, still report effective IP by parsing
    local current_ip
    current_ip="$(grep -E "^address=/${DOMAIN}/" "$CONFIG_FILE" 2>/dev/null | sed -E "s#^address=/${DOMAIN}/##" || true)"
    log "  OK (no change) (effective IP: ${current_ip:-unknown})"
  fi
}

stage_resolver() {
  log "Stage: resolver @ ${RESOLVER_FILE}"
  ensure_dir "$RESOLVER_DIR" 755
  local desired="nameserver ${RESOLVER_IP}
"
  write_if_changed "$RESOLVER_FILE" 644 desired STAGE_RESOLVER_CHANGED
  if [ "$STAGE_RESOLVER_CHANGED" = true ]; then
    log "  Wrote resolver (nameserver ${RESOLVER_IP})"
  else
    log "  OK (no change)"
  fi
}

stage_plist() {
  log "Stage: launchd plist @ ${LAUNCHD_PLIST}"
  local plist_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>Label</key>
  <string>${SERVICE_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${DNSMASQ_TARGET}</string>
    <string>--keep-in-foreground</string>
    <string>--conf-file=${CONFIG_FILE}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/${SERVICE_LABEL}.out.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/${SERVICE_LABEL}.err.log</string>
</dict>
</plist>
"
  write_if_changed "$LAUNCHD_PLIST" 644 plist_content STAGE_PLIST_CHANGED

  # Ensure correct ownership/permissions for system daemons
  if set_owner_perms_if_needed "$LAUNCHD_PLIST" 644; then
    STAGE_PLIST_CHANGED=true
  fi

  if command -v plutil >/dev/null 2>&1; then
    if ! plutil -lint "$LAUNCHD_PLIST" >/dev/null 2>&1; then
      log "  ERROR: Plist failed validation (plutil)."
      exit 1
    fi
  fi

  if [ "$STAGE_PLIST_CHANGED" = true ]; then
    log "  Plist installed/updated"
  else
    log "  OK (no change)"
  fi
}

stage_service() {
  log "Stage: service state"

  local need_restart="$FORCE_RESTART"
  if [ "$STAGE_BIN_CHANGED" = true ] || [ "$STAGE_CFG_CHANGED" = true ] || [ "$STAGE_PLIST_CHANGED" = true ]; then
    need_restart="true"
  fi

  if [ "$need_restart" = "true" ]; then
    log "  Restarting ${SERVICE_LABEL}"
    restart_service
    SERVICE_RESTARTED=true
  else
    # Ensure it is loaded at least once
    if ! service_is_loaded; then
      log "  Service not loaded; loading now"
      restart_service
      SERVICE_RESTARTED=true
    else
      log "  OK (no restart needed)"
    fi
  fi
}

### -------------------------- Main --------------------------------------
main() {
  require_root
  log "Using domain=${DOMAIN}, host-ip=${HOST_IP}, resolver-ip=${RESOLVER_IP}"

  stage_binary
  stage_config
  stage_resolver
  stage_plist
  stage_service

  log "Summary:"
  log "  Binary changed:   ${STAGE_BIN_CHANGED}"
  log "  Config changed:   ${STAGE_CFG_CHANGED}"
  log "  Resolver changed: ${STAGE_RESOLVER_CHANGED}"
  log "  Plist changed:    ${STAGE_PLIST_CHANGED}"
  log "  Service restarted:${SERVICE_RESTARTED}"
  log "Done."
}

main "$@"
