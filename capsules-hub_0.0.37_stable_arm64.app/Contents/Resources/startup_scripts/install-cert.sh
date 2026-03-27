#!/usr/bin/env bash
set -euo pipefail

SYSTEM_KEYCHAIN="/Library/Keychains/System.keychain"
CERT_PATH=""
CERT_CN=""
NEW_FPR=""
VM_NAME=""
TARGET_USER=""
TEMP_CERT_PATH=""

# ====== UTILITY FUNCTIONS ======
log_info()  { echo -e "[\e[32mINFO\e[0m] $*"; }
log_warn()  { echo -e "[\e[33mWARN\e[0m] $*"; }
log_error() { echo -e "[\e[31mERROR\e[0m] $*" >&2; }

print_help() {
    echo "Usage: init-authentik.sh [options]"
    echo ""
    echo "Installs the Caddy Root CA from a Parallels Capsules VM."
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message and exit"
    echo "  -n, --vm-name     Name of the VM to fetch the cert from"
    echo "  -u, --user        User to run the prlctl command as"
}


# Function to validate arguments and file existence
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_help
                exit 0
                ;;
            -n|--vm-name)
                VM_NAME="$2"
                shift 2
                ;;
            -u|--user)
                TARGET_USER="$2"
                shift 2
                ;;
            *)
                log_error "Unknown parameter: $1"
                print_help
                exit 1
                ;;
        esac
    done
}

get_cert_from_vm() {
    log_info "→ VM name: $VM_NAME"
    if [[ -z "$VM_NAME" ]]; then
        log_error "Could not determine VM name."
        exit 1
    fi

    TEMP_CERT_PATH=$(mktemp)
    log_info "→ Fetching cert from VM: $VM_NAME"
    log_info "→ Current User: $(whoami)"
    log_info "→ Target User: $TARGET_USER"

    if [[ -n "$TARGET_USER" ]]; then
        temp_cert_content=$(sudo -u "$TARGET_USER" /usr/local/bin/prlctl exec "$VM_NAME" cat /var/lib/caddy/.local/share/caddy/pki/authorities/secondary/root.crt)
    else
        temp_cert_content=$(/usr/local/bin/prlctl exec "$VM_NAME" cat /var/lib/caddy/.local/share/caddy/pki/authorities/secondary/root.crt)
    fi
    echo "$temp_cert_content" >> "$TEMP_CERT_PATH"

    log_info "→ Temp cert path: $TEMP_CERT_PATH"
    log_info "→ Temp cert content:"
    log_info "$(cat "$TEMP_CERT_PATH")"
}
  


# Function to get the Common Name (CN) from the certificate
get_cert_cn() {
  CERT_CN=$(openssl x509 -in "$TEMP_CERT_PATH" -noout -subject -nameopt RFC2253 \
    | sed -n 's/^subject=CN=//p' \
    | sed 's/,.*//')

  if [[ -z "$CERT_CN" ]]; then
    log_error "Could not determine certificate CN (Common Name)."
  fi

  log_info "→ Certificate CN: $CERT_CN"
}

# Function to get the certificate's SHA-256 fingerprint
get_cert_fingerprint() {
  NEW_FPR=$(openssl x509 -in "$TEMP_CERT_PATH" -noout -sha256 -fingerprint \
    | cut -d'=' -f2 \
    | tr -d ':')

  if [[ -z "$NEW_FPR" ]]; then
    log_error "Could not compute new certificate fingerprint."
    exit 1
  fi

  log_info "→ New certificate fingerprint: $NEW_FPR"
}

# Function to install the certificate
install_cert() {
  log_info "→ Installing as trusted root…"
  
  if [[ -n "$TARGET_USER" ]]; then
      TARGET_UID=$(id -u "$TARGET_USER")
      log_info "→ Using launchctl asuser $TARGET_UID for security command"
      launchctl asuser "$TARGET_UID" sudo security add-trusted-cert \
        -d -r trustRoot \
        -k "$SYSTEM_KEYCHAIN" \
        "$TEMP_CERT_PATH"
  else
      sudo security add-trusted-cert \
        -d -r trustRoot \
        -k "$SYSTEM_KEYCHAIN" \
        "$TEMP_CERT_PATH"
  fi

  log_info "✓ Installed new Caddy CA."
  setup_firefox_trust
}

# Function to delete the certificate
# Function to delete the certificate
delete_cert() {
  log_info "→ Deleting existing certificate..."
  if [[ -n "$TARGET_USER" ]]; then
      TARGET_UID=$(id -u "$TARGET_USER")
      launchctl asuser "$TARGET_UID" sudo security delete-certificate -c "$CERT_CN" "$SYSTEM_KEYCHAIN" || true
  else
      sudo security delete-certificate -c "$CERT_CN" "$SYSTEM_KEYCHAIN" || true
  fi
}

setup_firefox_trust() {
  log_info "→ Setting up Firefox trust..."

  # Determine actual user and home directory
  local real_user="${TARGET_USER:-${SUDO_USER:-$USER}}"
  local real_home
  # Use eval to expand tilde for the real user
  real_home=$(eval echo "~$real_user")
  
  log_info "  User: $real_user"
  log_info "  Home: $real_home"

  # Check if Firefox is installed
  local firefox_installed=false
  if [[ -d "/Applications/Firefox.app" ]]; then
    firefox_installed=true
  elif [[ -d "$real_home/Applications/Firefox.app" ]]; then
    firefox_installed=true
  fi

  if [[ "$firefox_installed" == "false" ]]; then
    log_info "Firefox.app not found. Skipping Firefox trust setup."
    return 0
  fi

  FF_BASE="$real_home/Library/Application Support/Firefox"
  PROFILES_INI="$FF_BASE/profiles.ini"

  if [[ ! -f "$PROFILES_INI" ]]; then
    log_warn "Firefox profiles.ini not found at: $PROFILES_INI"
    return 0
  fi

  # Find the default profile path from profiles.ini
  # Handles Path before or after Default=1 within the section
  PROFILE_PATH=$(awk -F= '
    /^\[Profile/ {current_path=""; is_default=0}
    /^Path=/ {current_path=$2; if (is_default) {print current_path; exit}}
    /^Default=1/ {is_default=1; if (current_path != "") {print current_path; exit}}
  ' "$PROFILES_INI")

  if [[ -z "$PROFILE_PATH" ]]; then
    log_warn "Could not determine default Firefox profile from profiles.ini"
    return 0
  fi

  PROFILE_DIR="$FF_BASE/$PROFILE_PATH"
  USER_JS="$PROFILE_DIR/user.js"

  log_info "→ Default Firefox profile: $PROFILE_DIR"

  if [[ ! -d "$PROFILE_DIR" ]]; then
      log_warn "Profile directory does not exist: $PROFILE_DIR"
      return 0
  fi

  # Append or create user.js with the enterprise roots pref
  if grep -q 'security.enterprise_roots.enabled' "$USER_JS" 2>/dev/null; then
    # Replace existing line
    sed -i '' 's/user_pref("security.enterprise_roots.enabled".*/user_pref("security.enterprise_roots.enabled", true);/' "$USER_JS"
    log_info "✓ Updated existing preference in $USER_JS"
  else
    # Append new line
    echo 'user_pref("security.enterprise_roots.enabled", true);' >> "$USER_JS"
    log_info "✓ Added preference to $USER_JS"
  fi
  
  # Fix ownership if we created the file or if it was owned by root for some reason
  chown "$real_user" "$USER_JS"
  
  log_info "✓ Firefox will start trusting the macOS system keychain on next launch."
}

# Main function to orchestrate the flow
main() {
  # Check root first, passing all args


  log_info "→ Parsing args..."
  parse_args "$@"

  log_info "→ Getting cert from VM..."
  get_cert_from_vm

#   # Get Cert Details
  get_cert_cn
  get_cert_fingerprint

#   # Try to find an existing certificate in the System keychain with the same CN
  local existing_info
  existing_info=$(sudo security find-certificate -c "$CERT_CN" -Z "$SYSTEM_KEYCHAIN" 2>/dev/null || true)

  if [[ -z "$existing_info" ]]; then
    log_info "→ No existing certificate with CN '$CERT_CN' found in System keychain."
    install_cert
    exit 0
  fi

  # Extract the first SHA-256 hash from the existing cert info
  local existing_fpr
  existing_fpr=$(echo "$existing_info" | awk '/SHA-256 hash:/ {print $3; exit}')

  if [[ -z "$existing_fpr" ]]; then
    log_info "→ Existing certificate found but fingerprint not readable. Replacing it."
    delete_cert
    install_cert
    log_info "✓ Replaced existing Caddy CA (fingerprint missing)."
    exit 0
  fi

  log_info "→ Existing certificate fingerprint: $existing_fpr"

  if [[ "$existing_fpr" == "$NEW_FPR" ]]; then
    log_info "✓ Existing Caddy CA already matches this fingerprint. Nothing to do."
    exit 0
  else
    log_info "→ Fingerprints differ. Replacing existing certificate…"
    delete_cert
    install_cert
    log_info "✓ Replaced Caddy CA with new fingerprint."
    exit 0
  fi
}

main "$@"
