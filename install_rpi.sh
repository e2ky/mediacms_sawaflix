#!/usr/bin/env bash
set -e

#################################################
# MediaCMS – Raspberry Pi OS (CM5)
# Repo-local installer
#################################################

########################
# Failure trap
########################
trap 'fail "FAILED at line $LINENO. See log: $LOG_FILE"; exit 1' ERR

########################
# Optional command tracing
########################
TRACE=0
if [[ "$1" == "--trace" ]]; then
  TRACE=1
  shift
fi
[[ $TRACE -eq 1 ]] && set -x

########################
# Color definitions
########################
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

log()  { echo -e "${BLUE}▶ $*${NC}"; }
ok()   { echo -e "${GREEN}✔ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "${RED}✖ $*${NC}"; }

stage() {
  echo
  echo -e "${BLUE}==============================${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}==============================${NC}"
}

########################
# Dry-run handling
########################
DRY_RUN=0
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=1
  warn "Running in DRY-RUN mode"
fi

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

########################
# Logging
########################
LOG_DIR="/var/log/mediacms"
LOG_FILE="$LOG_DIR/install_$(date +%Y%m%d_%H%M%S).log"

run "mkdir -p $LOG_DIR"
run "chmod 755 $LOG_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

########################
# Configuration
########################
TARGET_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo ~$TARGET_USER)"

# Script lives inside the repo
MEDIACMS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VENV_DIR="$MEDIACMS_DIR/venv"
STATIC_DIR="$MEDIACMS_DIR/static"

SRC_DIR="/opt/src"
MEDIA_MOUNT="/mnt/mediacms-media"

FFMPEG_PREFIX="/usr/local"
FFMPEG_SRC="$SRC_DIR/ffmpeg"
FFMPEG_TAG="n6.1"

########################
# Guards
########################
stage "Environment validation"

[[ $EUID -eq 0 ]] || fail "Run with sudo"
mountpoint -q "$MEDIA_MOUNT" || fail "Media mount not present"

[[ -f "$MEDIACMS_DIR/manage.py" ]] || fail "Script not run from MediaCMS repo"

ok "Environment OK"
ok "MediaCMS dir: $MEDIACMS_DIR"

########################
# Helpers
########################
install_pkg() {
  dpkg -s "$1" >/dev/null 2>&1 || run "apt install -y $1"
}

########################
# Base system
########################
stage "Base system packages"

run "apt update"

for pkg in git build-essential python3 python3-venv python3-dev \
           redis-server postgresql postgresql-contrib libpq-dev \
           imagemagick nginx; do
  install_pkg "$pkg"
done

run "systemctl enable redis-server postgresql"
run "systemctl start redis-server postgresql"

ok "Base system ready"

########################
# Source directory
########################
stage "Source directory setup"

run "mkdir -p $SRC_DIR"
run "chmod 755 $SRC_DIR"

########################
# FFmpeg build
########################
stage "FFmpeg build ($FFMPEG_TAG)"

if [[ ! -x "$FFMPEG_PREFIX/bin/ffmpeg" ]]; then
  for pkg in yasm nasm pkg-config libx264-dev libx265-dev \
             libv4l-dev libdrm-dev libfreetype6-dev \
             libfontconfig1-dev libass-dev; do
    install_pkg "$pkg"
  done

  run "[[ -d $FFMPEG_SRC ]] || git clone https://git.ffmpeg.org/ffmpeg.git $FFMPEG_SRC"
  run "cd $FFMPEG_SRC"
  run "git fetch --tags"
  run "git checkout $FFMPEG_TAG"

  run "./configure \
    --prefix=$FFMPEG_PREFIX \
    --enable-gpl \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libdrm \
    --enable-v4l2 \
    --enable-neon \
    --enable-optimizations \
    --enable-pthreads \
    --disable-debug \
    --disable-doc \
    --disable-ffplay"

  run "make -j$(nproc) V=1"
  run "make install"
  run "ldconfig"

  ok "FFmpeg installed"
else
  ok "FFmpeg already present"
fi

########################
# Python environment
########################
stage "Python virtual environment"

run "[[ -d $VENV_DIR ]] || sudo -u $TARGET_USER python3 -m venv $VENV_DIR"

run "sudo -u $TARGET_USER bash -c '
  source $VENV_DIR/bin/activate
  pip install --upgrade pip wheel
  pip install -r requirements.txt
'"

ok "Python environment ready"

########################
# Media directories
########################
stage "Media directories"

run "mkdir -p $MEDIA_MOUNT/{uploads,thumbnails,previews,transcoded,tmp}"
run "chown -R www-data:www-data $MEDIA_MOUNT"
run "chmod -R 750 $MEDIA_MOUNT"

########################
# Django setup
########################
stage "Django initialization"

run "sudo -u $TARGET_USER bash -c '
  cd $MEDIACMS_DIR
  source $VENV_DIR/bin/activate
  python manage.py migrate
  python manage.py collectstatic --noinput
'"

run "chmod -R 755 $STATIC_DIR"

########################
# Summary
########################
stage "Installation complete"

ok "Code   : $MEDIACMS_DIR"
ok "Static : $STATIC_DIR"
ok "Media  : $MEDIA_MOUNT"
ok "Log    : $LOG_FILE"
echo

