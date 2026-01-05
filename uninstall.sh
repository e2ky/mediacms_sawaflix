#!/usr/bin/env bash
set -e

echo "=========================================="
echo " MediaCMS FULL UNINSTALL"
echo " Removes MediaCMS + system dependencies"
echo "=========================================="

if [ "$EUID" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

read -p "THIS WILL REMOVE PostgreSQL, nginx, Redis, ffmpeg. Continue? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo "Stopping services..."
systemctl stop mediacms celery celerybeat nginx postgresql redis-server || true

echo "Disabling MediaCMS services..."
systemctl disable mediacms celery celerybeat || true

echo "Removing systemd service files..."
rm -f /etc/systemd/system/mediacms.service
rm -f /etc/systemd/system/celery.service
rm -f /etc/systemd/system/celerybeat.service
systemctl daemon-reload

echo "Removing nginx configs..."
rm -rf /etc/nginx/sites-enabled/*
rm -rf /etc/nginx/sites-available/*
rm -rf /etc/nginx/conf.d/*
rm -rf /etc/nginx/snippets/*
rm -rf /etc/letsencrypt
rm -rf /var/lib/letsencrypt
rm -rf /var/www/html

echo "Removing MediaCMS app files..."
rm -rf /opt/mediacms
rm -rf /var/www/mediacms
rm -rf /var/media/mediacms

echo "Removing Bento4 tools..."
rm -rf /opt/bento4
rm -rf /usr/local/bin/mp4*

echo "Clearing Redis data..."
rm -rf /var/lib/redis
rm -rf /etc/redis

echo "Removing PostgreSQL data..."
rm -rf /var/lib/postgresql
rm -rf /etc/postgresql
rm -rf /etc/postgresql-common
rm -rf /var/log/postgresql

echo "Removing logs..."
rm -rf /var/log/nginx
rm -rf /var/log/mediacms
rm -rf /var/log/celery*

echo "Uninstalling system packages..."
apt-get purge -y \
  nginx nginx-common nginx-core \
  postgresql postgresql-* \
  redis-server redis-tools \
  ffmpeg \

echo "Autoremoving unused dependencies..."
apt-get autoremove -y
apt-get autoclean -y

echo "Removing mediacms user (if exists)..."
id mediacms &>/dev/null && userdel -r mediacms || true

echo "Clearing pip caches..."
rm -rf /root/.cache/pip
rm -rf /home/*/.cache/pip

echo "=========================================="
echo "FULL UNINSTALL COMPLETE"
echo "System is ready for a fresh install"
echo "=========================================="

