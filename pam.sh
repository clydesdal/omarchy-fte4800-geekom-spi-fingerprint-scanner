#!/bin/bash
# Enable fingerprint auth for sudo, polkit and the Omarchy lock screen.
#
# The PAM functions below are copied from Omarchy's
# /usr/bin/omarchy-setup-security-fingerprint (MIT, github.com/basecamp/omarchy)
# with max-tries=10 timeout=30 added. That script can't be used directly
# because its omarchy-hw-fingerprint check only scans USB, and the FTE4800 is
# on SPI. Run this only after enrolling a finger.
set -e
setup_pam_config() {
  # A clamshell gate runs before pam_fprintd in every stack: when the lid is
  # shut the reader is unreachable, so it skips fingerprint (success=1) and PAM
  # drops straight to the password prompt instead of blocking on the reader
  # until it times out. Lid open → fingerprint, then password as the fallback.
  #
  # pam_exec needs a literal absolute path (no env expansion). Point at the
  # fixed /usr/bin path the omarchy package always provides, so the gate keeps
  # working across package installs and dev-link — the latter overlays
  # $OMARCHY_PATH trees but leaves /usr/bin untouched.
  local fprintd_gate="auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed"

  # Configure sudo
  if ! grep -q pam_fprintd.so /etc/pam.d/sudo; then
    echo "Configuring sudo for fingerprint authentication..."
    sudo sed -i '1i auth      sufficient pam_fprintd.so max-tries=10 timeout=30' /etc/pam.d/sudo
  fi
  if ! grep -q 'omarchy-hw-laptop-closed' /etc/pam.d/sudo; then
    echo "Adding clamshell gate to sudo..."
    # Insert immediately before pam_fprintd so success=1 skips exactly it.
    sudo sed -i "/pam_fprintd\.so/i $fprintd_gate" /etc/pam.d/sudo
  fi

  # Configure polkit
  if [[ -f /etc/pam.d/polkit-1 ]]; then
    if ! grep -q 'pam_fprintd.so' /etc/pam.d/polkit-1; then
      echo "Configuring polkit for fingerprint authentication..."
      sudo sed -i '1i auth      sufficient pam_fprintd.so max-tries=10 timeout=30' /etc/pam.d/polkit-1
    fi
    if ! grep -q 'omarchy-hw-laptop-closed' /etc/pam.d/polkit-1; then
      echo "Adding clamshell gate to polkit..."
      sudo sed -i "/pam_fprintd\.so/i $fprintd_gate" /etc/pam.d/polkit-1
    fi
  else
    echo "Creating polkit configuration with fingerprint authentication..."
    # omarchy:heredoc-expands paths=none -- $fprintd_gate is the literal PAM
    # line defined above, shared with the two sed insertions so the gate cannot
    # drift between files. The only path in it is the fixed /usr/bin one.
    sudo tee /etc/pam.d/polkit-1 >/dev/null <<EOF
$fprintd_gate
auth      sufficient pam_fprintd.so max-tries=10 timeout=30
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
EOF
  fi
}
setup_lock_fingerprint_pam() {
  echo "Configuring lock screen for fingerprint authentication..."
  sudo tee /etc/pam.d/omarchy-lock-fingerprint >/dev/null <<'EOF'
#%PAM-1.0
auth       required                    pam_fprintd.so max-tries=10 timeout=30
account    include                     system-local-login
EOF
}

# Small FTE4800 sensor: one touch matches ~40% of the time, so allow retries.
ok=0; for i in 1 2 3 4 5; do echo "verify attempt $i/5"; fprintd-verify && { ok=1; break; }; done
[ $ok = 1 ] || { echo "No match in 5 tries; re-enroll before enabling PAM."; exit 1; }
setup_pam_config
setup_lock_fingerprint_pam
echo "Fingerprint enabled for sudo, polkit and lock screen (Super+Ctrl+L)."
