#!/usr/bin/env bash
set -e
set -o pipefail

echo "============================================"
echo " MediaCMS UNINSTALL SCRIPT"
echo "============================================"
echo
echo "⚠ WARNING:"
echo "This will REMOVE MediaCMS, FFmpeg, databases,"
echo "services, configs, and related system packages."
echo
read -p "Type UNINSTALL to continue: " CONFIRM
[[ "$CONFIRM" == "UNINSTALL" ]] || exit 1

############################
# Root check
############################
if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

############################
# Stop and disable services
############################
systemctl stop mediacms.service || true
systemctl disable mediacms.service || true

systemctl stop celery_long celery_short celery_beat || true
systemctl disable celery_long celery_short celery_beat || true

systemctl stop nginx || true
systemctl stop redis-server || true
systemctl stop postgresql || true

############################
# Remove systemd units
############################
rm -f /etc/systemd/system/mediacms.service
rm -f /etc/systemd/system/celery_long.service
rm -f /etc/systemd/system/celery_short.service
rm -f /etc/systemd/system/celery_beat.service

systemctl daemon-reload

############################
# Remove nginx configuration
############################
rm -f /etc/nginx/sites-enabled/mediacms.io
rm -f /etc/nginx/sites-available/mediacms.io
rm -f /etc/nginx/nginx.conf
rm -f /etc/nginx/sites-enabled/uwsgi_params
rm -rf /etc/letsencrypt/live/*
rm -rf /etc/letsencrypt/archive/*
rm -rf /etc/letsencrypt/renewal/*

############################
# Remove MediaCMS files
############################
rm -rf /home/mediacms.io

############################
# Remove PostgreSQL database and user
############################
sudo -u postgres psql <<EOF || true
DROP DATABASE IF EXISTS mediacms;
DROP USER IF EXISTS mediacms;
EOF

############################
# Remove FFmpeg (custom build)
############################
rm -f /usr/bin/ffmpeg /usr/bin/ffprobe
rm -f /usr/local/bin/ffmpeg /usr/local/bin/ffprobe
rm -rf /usr/local/lib/libav*
rm -rf /usr/local/include/libav*
rm -rf /opt/src/ffmpeg

ldconfig

############################
# Remove Bento4
############################
rm -rf /home/mediacms.io/mediacms/Bento4*

############################
# Remove packages installed by MediaCMS
############################
apt-get purge -y \
  nginx \
  redis-server \
  postgresql \
  postgresql-contrib \
  python3-venv \
  python3-dev \
  virtualenv \
  imagemagick \
  certbot \
  python3-certbot-nginx \
  libxml2-dev \
  libxmlsec1-dev \
  libxmlsec1-openssl \
  pkg-config \
  gcc \
  git \
  unzip \
  wget \
  xz-utils \
  procps || true

############################
# Remove FFmpeg build dependencies
############################
apt-get purge -y \
  yasm \
  nasm \
  libx264-dev \
  libx265-dev \
  libv4l-dev \
  libdrm-dev \
  libfreetype6-dev \
  libfontconfig1-dev \
  libass-dev || true

############################
# Autoremove leftovers
############################
apt-get autoremove -y
apt-get autoclean -y

############################
# Final message
############################
echo
echo "============================================"
echo " MediaCMS uninstall COMPLETE"
echo "============================================"
echo
echo "Remaining items NOT removed:"
echo "- System users (www-data, postgres)"
echo "- Kernel packages"
echo "- apt cache outside autoclean"
echo
echo "Reboot recommended."

