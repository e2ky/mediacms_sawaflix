#!/usr/bin/env bash
set -e

#################################################
# MediaCMS – Raspberry Pi OS (CM5)
# Secure, Repeatable Installer
# mediacms_sawflix layout
#################################################

### ---------- Configuration ---------- ###
TARGET_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo ~$TARGET_USER)"

MEDIACMS_DIR="$HOME_DIR/mediacms_sawflix"
VENV_DIR="$MEDIACMS_DIR/venv"
STATIC_DIR="$MEDIACMS_DIR/static"

SRC_DIR="/opt/src"
MEDIA_MOUNT="/mnt/mediacms-media"

FFMPEG_PREFIX="/usr/local"
FFMPEG_SRC="$SRC_DIR/ffmpeg"
FFMPEG_TAG="n6.1"

DB_NAME="mediacms"
DB_USER="mediacmsuser"
DB_PASS="strongpassword"

### ---------- Guards ---------- ###
OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
ARCH=$(uname -m)

if [[ "$OS_ID" != "raspbian" && "$OS_ID" != "debian" ]]; then
  echo "ERROR: Raspberry Pi OS / Debian required"
  exit 1
fi

if [[ "$ARCH" != "aarch64" ]]; then
  echo "ERROR: 64-bit ARM required"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run with sudo"
  exit 1
fi

if ! mountpoint -q "$MEDIA_MOUNT"; then
  echo "ERROR: Media mount $MEDIA_MOUNT not present"
  exit 1
fi

echo "✔ Target user: $TARGET_USER"
echo "✔ MediaCMS dir: $MEDIACMS_DIR"
echo "✔ Media mount: $MEDIA_MOUNT"

### ---------- Helpers ---------- ###
install_pkg() {
  dpkg -s "$1" >/dev/null 2>&1 || apt install -y "$1"
}

### ---------- Base system ---------- ###
apt update

install_pkg git
install_pkg build-essential
install_pkg python3
install_pkg python3-venv
install_pkg python3-dev
install_pkg redis-server
install_pkg postgresql
install_pkg postgresql-contrib
install_pkg libpq-dev
install_pkg imagemagick
install_pkg nginx

systemctl enable redis-server
systemctl start redis-server
systemctl enable postgresql
systemctl start postgresql

### ---------- Source directory ---------- ###
mkdir -p "$SRC_DIR"
chmod 755 "$SRC_DIR"

### ---------- FFmpeg (custom, pinned, ARM64) ---------- ###
if [[ ! -x "$FFMPEG_PREFIX/bin/ffmpeg" ]]; then
  echo "▶ Building FFmpeg $FFMPEG_TAG"

  install_pkg yasm
  install_pkg nasm
  install_pkg pkg-config
  install_pkg libx264-dev
  install_pkg libx265-dev
  install_pkg libv4l-dev
  install_pkg libdrm-dev
  install_pkg libfreetype6-dev
  install_pkg libfontconfig1-dev
  install_pkg libass-dev

  [[ -d "$FFMPEG_SRC" ]] || git clone https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_SRC"
  cd "$FFMPEG_SRC"

  git fetch --tags
  git checkout "$FFMPEG_TAG"

  ./configure \
    --prefix="$FFMPEG_PREFIX" \
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
    --disable-ffplay

  make -j"$(nproc)"
  make install
  ldconfig
fi

ln -sf /usr/local/bin/ffmpeg /usr/bin/ffmpeg
ln -sf /usr/local/bin/ffprobe /usr/bin/ffprobe

### ---------- MediaCMS code ---------- ###
if [[ ! -d "$MEDIACMS_DIR" ]]; then
  sudo -u "$TARGET_USER" git clone https://github.com/mediacms-io/mediacms "$MEDIACMS_DIR"
fi

cd "$MEDIACMS_DIR"

### ---------- Python virtualenv ---------- ###
if [[ ! -d "$VENV_DIR" ]]; then
  sudo -u "$TARGET_USER" python3 -m venv "$VENV_DIR"
fi

sudo -u "$TARGET_USER" bash <<EOF
source "$VENV_DIR/bin/activate"
pip install --upgrade pip wheel
pip install -r requirements.txt
EOF

### ---------- Database ---------- ###
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
    CREATE DATABASE $DB_NAME;
  END IF;
END
\$\$;
EOF

sudo -u postgres psql <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
    CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
  END IF;
END
\$\$;
EOF

sudo -u postgres psql <<EOF
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

### ---------- Media directories ---------- ###
mkdir -p "$MEDIA_MOUNT"/{uploads,thumbnails,previews,transcoded,tmp}
chown -R www-data:www-data "$MEDIA_MOUNT"
chmod -R 750 "$MEDIA_MOUNT"

### ---------- MediaCMS settings ---------- ###
SETTINGS="$MEDIACMS_DIR/cms/settings/local.py"

if [[ ! -f "$SETTINGS" ]]; then
  sudo -u "$TARGET_USER" cp "$MEDIACMS_DIR/cms/settings/local.py.example" "$SETTINGS"
fi

cat <<EOF >> "$SETTINGS"

STATIC_ROOT = "$STATIC_DIR"
STATIC_URL = "/static/"

MEDIA_ROOT = "$MEDIA_MOUNT"
MEDIA_URL = "/media/"

MEDIA_UPLOAD_DIR = "uploads"
MEDIA_THUMBNAILS_DIR = "thumbnails"
MEDIA_PREVIEWS_DIR = "previews"
MEDIA_TRANSCODED_DIR = "transcoded"
MEDIA_TMP_DIR = "tmp"

FFMPEG_TEMP_DIR = "$MEDIA_MOUNT/tmp"

MEDIA_TRANSCODING_MAX_CONCURRENT_JOBS = 1

VIDEO_RENDITIONS = [
    {"width": 1280, "height": 720, "bitrate": "1800k"}
]

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '$DB_NAME',
        'USER': '$DB_USER',
        'PASSWORD': '$DB_PASS',
        'HOST': '127.0.0.1',
        'PORT': '5432',
    }
}
EOF

chown "$TARGET_USER:$TARGET_USER" "$SETTINGS"

### ---------- Django init ---------- ###
sudo -u "$TARGET_USER" bash <<EOF
cd "$MEDIACMS_DIR"
source "$VENV_DIR/bin/activate"
python manage.py migrate
python manage.py collectstatic --noinput
EOF

chmod -R 755 "$STATIC_DIR"

echo
echo "✔ Installation complete"
echo
echo "Code:   $MEDIACMS_DIR"
echo "Static: $STATIC_DIR (read-only)"
echo "Media:  $MEDIA_MOUNT (www-data writable)"
echo

