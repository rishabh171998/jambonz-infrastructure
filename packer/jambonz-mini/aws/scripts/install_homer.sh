#!/bin/bash
# Don't use set -e - we want to continue even if Homer installation fails
set +e

# Arguments passed from Packer
DISTRO=$1
INSTALL_HOMER=$2
DB_USER=$3
DB_PASS=$4

if [ "$INSTALL_HOMER" != "yes" ]; then
  echo "Skipping Homer installation per configuration."
  exit 0
fi

echo "installing homer on $DISTRO with user $DB_USER and pass $DB_PASS"

if [[ "$DISTRO" == rhel* ]] ; then
  # RHEL logic (assuming this still works for the user)
  echo installing homer on rhel
  curl -s https://packagecloud.io/install/repositories/qxip/sipcapture/script.rpm.sh | sudo bash
  sudo dnf install -y homer-app

  curl -s https://packagecloud.io/install/repositories/qxip/sipcapture/script.rpm.sh | sudo os=rpm_any dist=rpm_any bash
  sudo dnf install -y heplify-server
  sudo dnf clean packages

  sudo systemctl restart postgresql-12
  sudo systemctl status postgresql-12
else
  # --- DEBIAN INSTALLATION USING HOMER-INSTALLER ---
  echo "Installing Homer/Heplify using homer-installer script for Debian/Ubuntu"
  
  # Install prerequisites for homer-installer
  sudo apt-get update
  sudo apt-get install -y libluajit-5.1-common libluajit-5.1-dev lsb-release wget curl git
  
  # Download and run homer-installer
  echo "Downloading homer-installer script..."
  cd /tmp
  wget --tries=5 --timeout=30 --retry-connrefused \
    https://github.com/sipcapture/homer-installer/raw/master/homer_installer.sh || {
    echo "ERROR: Failed to download homer-installer script"
    echo "Homer installation will be skipped - Jambonz will work without it"
    exit 0  # Don't fail the build
  }
  
  chmod +x homer_installer.sh
  
  echo "Running homer-installer (this may take several minutes)..."
  # The homer-installer script is interactive, so we need to provide answers
  # Install expect for automated interaction, or use yes command
  sudo apt-get install -y expect || true
  
  # Try to run installer with automated responses
  # The installer typically asks: Do you want to install? (yes/no)
  # We'll use expect or yes to automate
  if command -v expect &> /dev/null; then
    # Use expect for better automation
    sudo expect <<EOF || {
      echo "WARNING: homer-installer failed with expect"
      echo "Trying with yes command..."
      yes | sudo ./homer_installer.sh || {
        echo "WARNING: homer-installer may have failed"
        echo "Homer installation will be skipped - Jambonz will work without it"
        exit 0
      }
    }
spawn sudo ./homer_installer.sh
expect {
    "*[Yy]es*" { send "yes\r"; exp_continue }
    "*[Nn]o*" { send "yes\r"; exp_continue }
    "*continue*" { send "\r"; exp_continue }
    "*proceed*" { send "yes\r"; exp_continue }
    eof
}
wait
EOF
  else
    # Fallback to yes command (less reliable but works)
    yes | sudo ./homer_installer.sh || {
      echo "WARNING: homer-installer may have failed or required interaction"
      echo "Homer installation will be skipped - Jambonz will work without it"
      exit 0  # Don't fail the build
    }
  fi

  # Clean up installer script
  rm -f /tmp/homer_installer.sh
  
  # Verify installation
  if [ -f /usr/local/bin/homer-app ] || [ -f /usr/bin/homer-app ]; then
    echo "Homer installation completed successfully"
  else
    echo "WARNING: Homer binaries not found after installation"
    echo "Homer may not be fully installed, but Jambonz will work without it"
  fi
  # --- END DEBIAN INSTALLATION ---
fi

# --- CONFIGURATION (This section remains largely the same) ---

# Configure webapp_config.json for Homer
CONFIG_FILE=""
if [ -f /usr/local/homer/etc/webapp_config.json ]; then
  CONFIG_FILE="/usr/local/homer/etc/webapp_config.json"
elif [ -f /etc/homer/webapp_config.json ]; then
  CONFIG_FILE="/etc/homer/webapp_config.json"
fi

if [ -n "$CONFIG_FILE" ]; then
  sudo sed -i -e "s/homer_user/$DB_USER/g" "$CONFIG_FILE"
  sudo sed -i -e "s/homer_password/$DB_PASS/g" "$CONFIG_FILE"
  sudo sed -i -e "s/localhost/127.0.0.1/g" "$CONFIG_FILE"
else
  echo "WARNING: webapp_config.json not found, skipping configuration"
fi

# Configure and start services if Homer was installed
if [ -f /usr/local/bin/homer-app ] || [ -f /usr/bin/homer-app ]; then
  echo "populating homer database - users etc"
  HOMER_BIN=$(which homer-app 2>/dev/null || echo "/usr/local/bin/homer-app")
  if [ -f "$HOMER_BIN" ]; then
    sudo "$HOMER_BIN" -create-table-db-config 2>/dev/null || echo "WARNING: homer-app database setup failed"
    sudo "$HOMER_BIN" -populate-table-db-config 2>/dev/null || echo "WARNING: homer-app database population failed"
  else
    echo "WARNING: homer-app binary not found, skipping database setup"
  fi

  # Configure heplify-server.toml (if it exists)
  if [ -f /etc/heplify-server.toml ]; then
    sudo sed -i -e "s/DBUser\s*=\s*\"postgres\"/DBUser          = \"$DB_USER\"/g" /etc/heplify-server.toml
    sudo sed -i -e "s/DBPass\s*=\s*\"\"/DBPass          = \"$DB_PASS\"/g" /etc/heplify-server.toml
    sudo sed -i -e "s/PromAddr\s*=\s*\".*\"/PromAddr        = \"0.0.0.0:9098\"/g" /etc/heplify-server.toml
    sudo sed -i -e "s/HEPWSAddr\s*=\s*\".*\"/HEPWSAddr    = \"0.0.0.0:3050\"/g" /etc/heplify-server.toml
    sudo sed -i -e "s/AlegIDs\s*=\s*\[\]/AlegIDs        = \[\"X-CID\"]/g" /etc/heplify-server.toml
    sudo sed -i -e "s/CustomHeader\s*=\s*\[\]/CustomHeader        = \[\"X-Application-Sid\", \"X-Originating-Carrier\", \"X-MS-Teams-Tenant-FQDN\", \"X-Authenticated-User\"]/g" /etc/heplify-server.toml
  fi

  # Enable and start services (if they exist)
  if systemctl list-unit-files | grep -q homer-app; then
    sudo systemctl enable homer-app 2>/dev/null || true
    sudo systemctl restart homer-app 2>/dev/null || echo "WARNING: Could not start homer-app service"
    sudo systemctl status homer-app --no-pager || true
  fi

  if systemctl list-unit-files | grep -q heplify-server; then
    sudo systemctl enable heplify-server 2>/dev/null || true
    sudo systemctl restart heplify-server 2>/dev/null || echo "WARNING: Could not start heplify-server service"
    sudo systemctl status heplify-server --no-pager || true
  fi
fi

# Always exit successfully - Homer is optional
exit 0
