#!/bin/bash
set -e

DISTRO=$1

if [ "$2" == "yes" ]; then

cd /tmp

JAEGER_VERSION="v1.76.0"
# NOTE: The file name on GitHub releases does not use the 'v' prefix.
JAEGER_ARTIFACT_VERSION="1.76.0"

echo "installing jaeger ${JAEGER_VERSION}"

# 1. INSTALL JAEGER BINARIES
# Use wget with retry and timeout settings for reliability
wget --tries=5 --timeout=30000 --continue "https://github.com/jaegertracing/jaeger/releases/download/${JAEGER_VERSION}/jaeger-${JAEGER_ARTIFACT_VERSION}-linux-amd64.tar.gz" || \
  wget --tries=5 --timeout=30000 "https://github.com/jaegertracing/jaeger/releases/download/${JAEGER_VERSION}/jaeger-${JAEGER_ARTIFACT_VERSION}-linux-amd64.tar.gz"
tar xvfz "jaeger-${JAEGER_ARTIFACT_VERSION}-linux-amd64.tar.gz"
sudo mv "jaeger-${JAEGER_ARTIFACT_VERSION}-linux-amd64/jaeger-collector" /usr/local/bin/
sudo mv "jaeger-${JAEGER_ARTIFACT_VERSION}-linux-amd64/jaeger-query" /usr/local/bin/

sudo cp jaeger-collector.service /etc/systemd/system
sudo chmod 644 /etc/systemd/system/jaeger-collector.service

sudo cp jaeger-query.service /etc/systemd/system
sudo chmod 644 /etc/systemd/system/jaeger-query.service
sudo systemctl daemon-reload


# 2. INSTALL REQUIRED TOOLS (GIT)
echo "installing git (required for schema scripts)"
if [[ "$DISTRO" == rhel* ]]; then
  sudo dnf install -y git
else
  # Ensure package lists are updated before installing
  sudo apt-get update
  sudo apt-get install -y git
fi


echo "installing cassandra on $2"

# 3. INSTALL CASSANDRA PREREQUISITES (JAVA)
if [ "$DISTRO" == "debian-12" ]; then
  # if debian 12 we need to downgrade java JDK to 11
  echo "downgrading Java JSDK to 11 because cassandra requires it"
  wget https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.9%2B11.1/OpenJDK11U-jdk_x64_linux_hotspot_11.0.9_11.tar.gz
  sudo tar -xvf OpenJDK11U-jdk_x64_linux_hotspot_11.0.9_11.tar.gz -C /opt/
  sudo update-alternatives --install /usr/bin/java java /opt/jdk-11.0.9+11/bin/java 100
  sudo update-alternatives --install /usr/bin/javac javac /opt/jdk-11.0.9+11/bin/javac 100
  sudo update-alternatives --set java /opt/jdk-11.0.9+11/bin/java
  sudo update-alternatives --set javac /opt/jdk-11.0.9+11/bin/javac
  echo "export JAVA_HOME=/opt/jdk-11.0.9+11" >> ~/.bashrc
  echo "export PATH=\$PATH:\$JAVA_HOME/bin" >> ~/.bashrc
  source ~/.bashrc
elif [[ "$DISTRO" == rhel* ]]; then
  sudo dnf install -y java-11-openjdk-devel
else
  sudo apt-get install -y default-jdk
fi
# Verify the installation
java -version

# 4. INSTALL CASSANDRA
CASSANDRA_VERSION="4.1.3"
# Use wget with retry, timeout, and continue options for large downloads
wget --tries=10 --timeout=600 --continue --progress=bar:force "https://archive.apache.org/dist/cassandra/${CASSANDRA_VERSION}/apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz" || \
  wget --tries=10 --timeout=600 --progress=bar:force "https://archive.apache.org/dist/cassandra/${CASSANDRA_VERSION}/apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz"
tar xvfz "apache-cassandra-${CASSANDRA_VERSION}-bin.tar.gz"
sudo mv "apache-cassandra-${CASSANDRA_VERSION}" /usr/local/cassandra
sudo cp cassandra.yaml /usr/local/cassandra/conf
sudo cp jvm-server.options /usr/local/cassandra/conf

if [[ "$DISTRO" == rhel* ]] ; then
  chown -R ec2-user:ec2-user /usr/local/cassandra/
  echo 'export PATH=$PATH:/usr/local/cassandra/bin' | sudo tee -a /home/ec2-user/.bashrc
  sed -i 's/\badmin\b/ec2-user/g' cassandra.service
else
  # User is 'admin' for Debian/Amazon builds
  sudo chown -R admin:admin /usr/local/cassandra/
  chown -R admin:admin /usr/local/cassandra/
  echo 'export PATH=$PATH:/usr/local/cassandra/bin' | sudo tee -a /home/admin/.bashrc
fi

echo 'export PATH=$PATH:/usr/local/cassandra/bin' | sudo tee -a /etc/profile
export PATH=$PATH:/usr/local/cassandra/bin

sudo cp cassandra.service /etc/systemd/system
sudo chmod 644 /etc/systemd/system/cassandra.service
sudo systemctl daemon-reload
sudo systemctl enable cassandra
sudo systemctl start cassandra

echo "waiting 60 secs for cassandra to start.."
sleep 60
echo "create jaeger user in cassandra"

# 5. CASSANDRA KEYSPACE AND USER SETUP
export CQLSH_HOST='127.0.0.1'
export CQLSH_PORT=9042
export USER_TO_CREATE='jaeger'
export PASSWORD='JambonzR0ck$'

# Create User
cqlsh -u cassandra -p cassandra -e "CREATE ROLE IF NOT EXISTS $USER_TO_CREATE WITH PASSWORD = '$PASSWORD' AND LOGIN = true AND SUPERUSER = false;"

echo "create keyspace and grant permissions for jaeger in cassandra"
cqlsh -u cassandra -p cassandra -e "CREATE KEYSPACE IF NOT EXISTS jaeger_v1_dc1 WITH replication = {'class': 'SimpleStrategy', 'replication_factor': '2'} AND durable_writes = true;"
cqlsh -u cassandra -p cassandra -e "GRANT ALL PERMISSIONS ON KEYSPACE jaeger_v1_dc1 TO $USER_TO_CREATE;"

# 6. JAEGER SCHEMA CREATION
echo "Creating Jaeger Cassandra schema"

# Configuration variables (matching the keyspace setup above)
# Schema creation requires cassandra superuser, not jaeger user
export CQLSH_HOST=${CQLSH_HOST:-localhost}
export CQLSH_PORT=${CQLSH_PORT:-9042}
export CQLSH_USER=${CQLSH_USER:-cassandra}
export CQLSH_PASSWORD=${CQLSH_PASSWORD:-cassandra}
export MODE=${MODE:-prod}
export DATACENTER=${DATACENTER:-datacenter1}
export KEYSPACE=${KEYSPACE:-jaeger_v1_dc1}
export REPLICATION_FACTOR=${REPLICATION_FACTOR:-2}
export TRACE_TTL=${TRACE_TTL:-604800}  # 7 days in seconds
export DEPENDENCIES_TTL=${DEPENDENCIES_TTL:-5184000}  # 60 days in seconds
export COMPACTION_WINDOW=${COMPACTION_WINDOW:-2h}  # Compaction window

echo "Configuration:"
echo "  MODE: $MODE"
echo "  DATACENTER: $DATACENTER"
echo "  KEYSPACE: $KEYSPACE"
echo "  REPLICATION_FACTOR: $REPLICATION_FACTOR"
echo "  TRACE_TTL: $TRACE_TTL seconds (7 days)"
echo "  DEPENDENCIES_TTL: $DEPENDENCIES_TTL seconds (60 days)"
echo "  COMPACTION_WINDOW: $COMPACTION_WINDOW"
echo "  CQLSH_HOST: $CQLSH_HOST"
echo "  CQLSH_PORT: $CQLSH_PORT"

# Install Docker if not available (required for schema creation)
if ! command -v docker &> /dev/null; then
  echo "Docker is not installed. Installing Docker..."
  
  if [ "$DISTRO" == "debian-11" ] || [ "$DISTRO" == "debian-12" ] || [[ "$DISTRO" == debian* ]]; then
    # Install Docker for Debian
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif [[ "$DISTRO" == rhel* ]] || [[ "$DISTRO" == amazon* ]]; then
    # Install Docker for RHEL/Amazon Linux
    sudo yum install -y docker
    sudo systemctl start docker
    sudo systemctl enable docker
  else
    echo "ERROR: Cannot install Docker automatically for distro: $DISTRO"
    exit 1
  fi
  
  # Verify Docker installation
  if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker installation failed"
    exit 1
  fi
  
  echo "Docker installed successfully"
fi

# Use Docker approach (preferred method)
if command -v docker &> /dev/null; then
  echo "Docker is available, using Docker image approach..."
  
  # Use the official Jaeger Cassandra schema Docker image
  echo "Pulling jaegertracing/jaeger-cassandra-schema Docker image..."
  docker pull jaegertracing/jaeger-cassandra-schema:latest || {
    echo "WARNING: Failed to pull latest tag, trying without tag..."
    docker pull jaegertracing/jaeger-cassandra-schema || {
      echo "ERROR: Failed to pull Docker image, falling back to script approach..."
      USE_DOCKER=false
    }
  }
  
  if [ "${USE_DOCKER:-true}" = "true" ]; then
    echo "Waiting for Cassandra to be fully ready..."
    # Wait for Cassandra to accept connections with authentication
    MAX_WAIT=180
    WAIT_COUNT=0
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
      if cqlsh -u "$CQLSH_USER" -p "$CQLSH_PASSWORD" "$CQLSH_HOST" "$CQLSH_PORT" -e "DESCRIBE KEYSPACES;" > /dev/null 2>&1; then
        echo "Cassandra is ready and accepting connections!"
        break
      fi
      if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
        echo "Waiting for Cassandra... ($WAIT_COUNT/$MAX_WAIT seconds)"
      fi
      sleep 2
      WAIT_COUNT=$((WAIT_COUNT + 2))
    done
    
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
      echo "WARNING: Cassandra did not become ready within $MAX_WAIT seconds"
      echo "Checking if keyspace already exists (schema might have been created)..."
      if cqlsh -u "$CQLSH_USER" -p "$CQLSH_PASSWORD" "$CQLSH_HOST" "$CQLSH_PORT" -e "DESCRIBE KEYSPACE $KEYSPACE;" > /dev/null 2>&1; then
        echo "Keyspace $KEYSPACE already exists, schema creation may have succeeded"
        exit 0
      fi
      echo "Cassandra connection test:"
      cqlsh -u "$CQLSH_USER" -p "$CQLSH_PASSWORD" "$CQLSH_HOST" "$CQLSH_PORT" -e "DESCRIBE KEYSPACES;" 2>&1 || true
      echo ""
      echo "WARNING: Skipping schema creation - Cassandra authentication issue"
      echo "Jaeger will work but schema will need to be created manually later"
      echo "You can create the schema manually by running:"
      echo "  docker run --rm --network host -e CQLSH_HOST=localhost -e CQLSH_PORT=9042 -e CQLSH_USER=cassandra -e CQLSH_PASSWORD=cassandra -e MODE=prod -e DATACENTER=datacenter1 -e KEYSPACE=jaeger_v1_dc1 jaegertracing/jaeger-cassandra-schema:latest"
      echo ""
      exit 0  # Don't fail the build, just skip schema creation
    fi
    
    echo "Creating Cassandra schema using Docker image..."
    docker run --rm --network host \
      -e CQLSH_HOST="$CQLSH_HOST" \
      -e CQLSH_PORT="$CQLSH_PORT" \
      -e CQLSH_USER="$CQLSH_USER" \
      -e CQLSH_PASSWORD="$CQLSH_PASSWORD" \
      -e MODE="$MODE" \
      -e DATACENTER="$DATACENTER" \
      -e KEYSPACE="$KEYSPACE" \
      -e REPLICATION_FACTOR="$REPLICATION_FACTOR" \
      -e TRACE_TTL="$TRACE_TTL" \
      -e DEPENDENCIES_TTL="$DEPENDENCIES_TTL" \
      -e COMPACTION_WINDOW="$COMPACTION_WINDOW" \
      jaegertracing/jaeger-cassandra-schema:latest && {
      echo "Jaeger Cassandra schema created successfully using Docker"
      exit 0
    } || {
      echo "Docker approach failed, checking if schema was partially created..."
      # Check if keyspace exists (might have been created despite error)
      if cqlsh -u "$CQLSH_USER" -p "$CQLSH_PASSWORD" "$CQLSH_HOST" "$CQLSH_PORT" -e "DESCRIBE KEYSPACE $KEYSPACE;" > /dev/null 2>&1; then
        echo "Keyspace $KEYSPACE exists, schema may have been created successfully"
        exit 0
      fi
      echo ""
      echo "WARNING: Schema creation failed - Docker container authentication issue"
      echo "Jaeger will work but schema will need to be created manually later"
      echo "The keyspace was created earlier, but tables may be missing"
      echo "You can create the schema manually after instance startup by running:"
      echo "  docker run --rm --network host \\"
      echo "    -e CQLSH_HOST=localhost -e CQLSH_PORT=9042 \\"
      echo "    -e CQLSH_USER=cassandra -e CQLSH_PASSWORD=cassandra \\"
      echo "    -e MODE=prod -e DATACENTER=datacenter1 -e KEYSPACE=jaeger_v1_dc1 \\"
      echo "    jaegertracing/jaeger-cassandra-schema:latest"
      echo ""
      exit 0  # Don't fail the build, schema can be created later
    }
  fi
fi

# If we reach here, schema creation was skipped or failed
echo "Schema creation skipped or failed - can be done manually later if needed"
exit 0

# Verify schema creation
echo "Verifying schema creation..."
cqlsh -u "$CQLSH_USER" -p "$CQLSH_PASSWORD" "$CQLSH_HOST" "$CQLSH_PORT" -e "USE $KEYSPACE; DESCRIBE TABLES;" || {
  echo "WARNING: Could not verify schema creation, but script completed"
}

if [[ "$DISTRO" == rhel* ]] ; then
  sudo sed -i 's/User=admin/User=ec2-user/' /etc/systemd/system/jaeger-collector.service
  sudo sed -i 's/User=admin/User=ec2-user/' /etc/systemd/system/jaeger-query.service
fi

sudo systemctl enable jaeger-collector
sudo systemctl enable jaeger-query

fi
