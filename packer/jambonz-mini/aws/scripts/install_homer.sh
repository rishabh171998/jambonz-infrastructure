#!/bin/bash
set -e

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
  # --- FIXED DEBIAN INSTALLATION (Bypassing broken package repository) ---
  echo "Installing Homer/Heplify via direct download for Debian/Ubuntu"
  sudo apt-get update
  sudo apt-get install -y curl wget gnupg2 libpq5 libjson-glib-dev

  # Direct Download Homer App v1.4.45 (Stable)
  echo "Downloading Homer App..."
  wget --tries=5 --timeout=30 --retry-connrefused --continue \
    https://github.com/sipcapture/homer-app/releases/download/v1.4.45/homer-app_1.4.45_amd64.deb || {
    echo "ERROR: Failed to download homer-app. Trying alternative version..."
    # Try latest version if specific version fails
    wget --tries=3 --timeout=30 --retry-connrefused \
      https://github.com/sipcapture/homer-app/releases/latest/download/homer-app_amd64.deb || {
      echo "ERROR: Failed to download homer-app from all sources"
      exit 8
    }
  }

  # Direct Download Heplify Server v1.3.5 (Stable)
  echo "Downloading Heplify Server..."
  wget --tries=5 --timeout=30 --retry-connrefused --continue \
    https://github.com/sipcapture/heplify-server/releases/download/v1.3.5/heplify-server_1.3.5_amd64.deb || {
    echo "ERROR: Failed to download heplify-server. Trying alternative version..."
    # Try latest version if specific version fails
    wget --tries=3 --timeout=30 --retry-connrefused \
      https://github.com/sipcapture/heplify-server/releases/latest/download/heplify-server_amd64.deb || {
      echo "ERROR: Failed to download heplify-server from all sources"
      exit 8
    }
  }

  echo "Installing packages..."
  # Install whatever .deb files we downloaded (handle both versioned and latest)
  sudo dpkg -i *.deb 2>/dev/null || {
    # If that fails, try installing individually
    for deb in *.deb; do
      if [ -f "$deb" ]; then
        echo "Installing $deb..."
        sudo dpkg -i "$deb" || true
      fi
    done
  }

  # Fix any missing dependencies (needed after using dpkg directly)
  sudo apt-get install -f -y

  # Clean up downloaded files
  rm -f *.deb

  # Copy webapp config file (if it exists)
  if [ -f /usr/local/homer/etc/webapp_config.json.example ]; then
    sudo cp /usr/local/homer/etc/webapp_config.json.example /usr/local/homer/etc/webapp_config.json
  elif [ -f /etc/homer/webapp_config.json.example ]; then
    sudo mkdir -p /etc/homer
    sudo cp /etc/homer/webapp_config.json.example /etc/homer/webapp_config.json
  else
    echo "WARNING: webapp_config.json.example not found, may need manual configuration"
  fi
  # --- END FIXED DEBIAN INSTALLATION ---
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

echo "populating homer database - users etc"
sudo /usr/local/bin/homer-app -create-table-db-config 
sudo /usr/local/bin/homer-app -populate-table-db-config

# Configure heplify-server.toml
sudo sed -i -e "s/DBUser\s*=\s*\"postgres\"/DBUser          = \"$DB_USER\"/g" /etc/heplify-server.toml
sudo sed -i -e "s/DBPass\s*=\s*\"\"/DBPass          = \"$DB_PASS\"/g" /etc/heplify-server.toml
sudo sed -i -e "s/PromAddr\s*=\s*\".*\"/PromAddr        = \"0.0.0.0:9098\"/g" /etc/heplify-server.toml
sudo sed -i -e "s/HEPWSAddr\s*=\s*\".*\"/HEPWSAddr    = \"0.0.0.0:3050\"/g" /etc/heplify-server.toml
sudo sed -i -e "s/AlegIDs\s*=\s*\[\]/AlegIDs        = \[\"X-CID\"]/g" /etc/heplify-server.toml
sudo sed -i -e "s/CustomHeader\s*=\s*\[\]/CustomHeader        = \[\"X-Application-Sid\", \"X-Originating-Carrier\", \"X-MS-Teams-Tenant-FQDN\", \"X-Authenticated-User\"]/g" /etc/heplify-server.toml

# Enable and start services
sudo systemctl enable homer-app
sudo systemctl restart homer-app
sudo systemctl status homer-app

sudo systemctl enable heplify-server
sudo systemctl restart heplify-server
sudo systemctl status heplify-server
