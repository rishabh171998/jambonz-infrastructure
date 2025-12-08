#!/bin/bash

if [ "$1" == "yes" ]; then

DB_USER=$2
DB_PASS=$3

# Set non-interactive mode to prevent prompts during installation
export DEBIAN_FRONTEND=noninteractive

# Configure debconf to prevent automatic PostgreSQL cluster upgrades
echo "postgresql-common postgresql-common/promote_old_cluster boolean false" | sudo debconf-set-selections
echo "postgresql-common postgresql-common/remove_old_cluster boolean true" | sudo debconf-set-selections
echo "postgresql-common postgresql-common/upgrade_cluster boolean false" | sudo debconf-set-selections

wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O- | sudo apt-key add -
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/postgresql.list'
sudo apt-get update

# Prevent the postgresql meta package from being installed/upgraded before installation
sudo apt-mark hold postgresql || true

# Install postgresql-12 specifically, avoiding the meta package that would trigger upgrades
# Use --no-install-recommends to avoid pulling in the meta package
sudo apt-get install -y --no-install-recommends postgresql-12 postgresql-client-12

# Ensure the meta package stays on hold
sudo apt-mark hold postgresql || true

sudo systemctl daemon-reload
sudo systemctl enable postgresql@12-main || sudo systemctl enable postgresql
sudo systemctl restart postgresql@12-main || sudo systemctl restart postgresql

sudo -u postgres psql -c "CREATE DATABASE homer_config;"
sudo -u postgres psql -c "CREATE DATABASE homer_data;"
sudo -u postgres psql -c "CREATE ROLE ${DB_USER} WITH SUPERUSER LOGIN PASSWORD '$DB_PASS';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE homer_config to ${DB_USER};"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE homer_data to ${DB_USER};"

fi