packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

####################
# VARIABLES
####################
variable "region" { default = "ap-south-1" }
variable "ssh_username" { default = "admin" }
variable "ami_description" { default = "jambonz all-in-one AMI" }
variable "instance_type" { default = "c6in.xlarge" }
variable "drachtio_version" { default = "v0.8.24" }
variable "jambonz_version" { default = "v0.8.5-2" }
variable "jambonz_user" { default = "admin" }
variable "jambonz_password" { default = "JambonzR0ck$" }
variable "install_telegraf" { default = "yes" }
variable "homer_user" { default = "homer_user" }
variable "homer_password" { default = "XcapJTqy11LnsYRtxXGPTYQkAnI" }
variable "install_influxdb" { default = "yes" }
variable "install_homer" { default = "yes" }
variable "install_jaeger" { default = "yes" }
variable "install_cloudwatch" { default = "yes" }
variable "install_nodered" { default = "no" }
variable "influxdb_ip" { default = "127.0.0.1" }
variable "rtp_engine_version" { default = "mr11.5.1.1" }
variable "rtp_engine_min_port" { default = "40000" }
variable "rtp_engine_max_port" { default = "60000" }
variable "mediaserver_name" { default = "jambonz" }
variable "preferred_codec_list" { default = "PCMU,PCMA,OPUS,G722" }
variable "distro" { default = "debian-11" }
variable "leave_source" { default = "yes" }
variable "apiban_username" { default = "" }
variable "apiban_password" { default = "" }

####################
# BUILDER
####################
source "amazon-ebs" "jambonz" {
  region        = var.region
  instance_type = var.instance_type
  ssh_username  = var.ssh_username
  ami_name      =  "jambonz-mini-{{user `jambonz_version`}}-{{isotime | clean_resource_name}}"
  ami_description = var.ami_description

  source_ami_filter {
    filters = {
      "virtualization-type" = "hvm"
      "name"                = "jambonz-base-image-${var.distro}"
      "root-device-type"    = "ebs"
    }
    owners      = ["376029039784"]  # official Jambonz AMI
    most_recent = true
  }

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 100
    volume_type           = "gp2"
    delete_on_termination = true
  }

  # Increase SSH timeout to handle long downloads
  ssh_timeout = "100m"
  
  # Keep connection alive during long operations
  ssh_keep_alive_interval = "30s"

  tags = {
    Name = "jambonz-mini"
  }

  run_tags = {
    Name = "jambonz-mini-build"
  }
}

####################
# BUILD
####################
build {
  sources = ["source.amazon-ebs.jambonz"]

  ####################
  # PROVISIONERS
  ####################
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "sudo apt-get update",
      "sudo apt-get remove --auto-remove nftables",
      "sudo apt-get purge nftables",
      "sudo apt-get -y install python-is-python3 lsof gcc g++ make cmake build-essential git autoconf automake default-mysql-client redis-tools curl argon2 telnet libtool libtool-bin libssl-dev libcurl4-openssl-dev zlib1g-dev systemd-coredump liblz4-tool libxtables-dev libip6tc-dev libip4tc-dev libiptc-dev libavformat-dev liblua5.1-0-dev libavfilter-dev libavcodec-dev libswresample-dev libevent-dev libpcap-dev libxmlrpc-core-c3-dev markdown libjson-glib-dev lsb-release libhiredis-dev gperf libspandsp-dev default-libmysqlclient-dev htop dnsutils gdb autoconf-archive gnupg2 wget pkg-config ca-certificates libjpeg-dev libsqlite3-dev libpcre3-dev libldns-dev snapd linux-headers-$(uname -r) libspeex-dev libspeexdsp-dev libedit-dev libtiff-dev yasm libswscale-dev haveged jq fail2ban pandoc libre2-dev libopus-dev libsndfile1-dev libshout3-dev libmpg123-dev libmp3lame-dev libopusfile-dev libgoogle-perftools-dev",
      "sudo chmod a+w /usr/local/src",
      "mkdir ~/apps",
      "cd ~/apps",
      "git config --global advice.detachedHead false",
      "git clone https://github.com/jambonz/sbc-call-router.git -b ${var.jambonz_version}",
      "git clone https://github.com/jambonz/fsw-clear-old-calls.git -b ${var.jambonz_version}",
      "git clone https://github.com/jambonz/sbc-outbound.git -b ${var.jambonz_version}",
      "git clone https://github.com/jambonz/sbc-inbound.git -b ${var.jambonz_version}",
      "git clone https://github.com/jambonz/sbc-sip-sidecar.git -b ${var.jambonz_version}",
      "git clone https://github.com/jambonz/jambonz-feature-server.git -b ${var.jambonz_version}",
      "git clone https://github.com/jambonz/jambonz-api-server.git -b ${var.jambonz_version}",
      "git clone https://github.com/jambonz/jambonz-webapp.git -b ${var.jambonz_version}",
      "git clone https://github.com/jambonz/jambonz-smpp-esme.git -b ${var.jambonz_version}",
      "git clone https://github.com/jambonz/sbc-rtpengine-sidecar.git -b ${var.jambonz_version}"
    ]
  }

  provisioner "file" {
    source        = "files/"
    destination = "/tmp"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro}"
    script          = "scripts/install_os_tuning.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.drachtio_version}"
    script          = "scripts/install_drachtio.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "ARCH=amd64",
      "MEDIA_SERVER_NAME=${var.mediaserver_name}",
      "PREFERRED_CODEC_LIST=${var.preferred_codec_list}",
      "DISTRO=${var.distro}"
    ]
    script = "scripts/install_freeswitch.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.install_jaeger}"
    script          = "scripts/install_jaeger.sh"
    # Allow for longer execution time and handle disconnects during long downloads
    timeout         = "60m"
    expect_disconnect = true
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.install_homer} ${var.homer_user} ${var.homer_password}"
    script          = "scripts/install_postgresql.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.install_homer} ${var.homer_user} ${var.homer_password}"
    script          = "scripts/install_homer.sh"
    timeout         = "45m"
    expect_disconnect = true
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.install_cloudwatch}"
    script          = "scripts/install_cloudwatch.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.rtp_engine_version}"
    script          = "scripts/install_rtpengine.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro}"
    script          = "scripts/install_nodejs.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.install_influxdb}"
    script          = "scripts/install_influxdb.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' {{build `ID`}} ${var.apiban_username} ${var.apiban_password}"
    script          = "scripts/install_apiban.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro}"
    script          = "scripts/install_nginx.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro}"
    script          = "scripts/install_redis.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.install_homer} ${var.influxdb_ip}"
    script          = "scripts/install_telegraf.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.install_influxdb}"
    script          = "scripts/install_grafana.sh"
  }

  provisioner "shell" {
    script = "scripts/install_fail2ban.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.jambonz_user} ${var.jambonz_password}"
    script          = "scripts/install_mysql.sh"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo '{{ .Path }}' ${var.distro} ${var.jambonz_version} ${var.jambonz_user} ${var.jambonz_password}"
    script          = "scripts/install_app.sh"
  }

  provisioner "shell" {
    inline = [
      "set -e",
      "set -x",
      "echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections",
      "echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections",
      "sudo apt-get -y install iptables-persistent",
      "sudo rm -Rf /tmp/*",
      "sudo rm /root/.ssh/authorized_keys",
      "sudo rm /home/admin/.ssh/authorized_keys",
      "if [ \"${var.leave_source}\" = 'no' ]; then sudo rm -Rf /usr/local/src/*; fi"
    ]
  }
}
