#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
ubuntu_version="$(lsb_release -r -s 2>/dev/null || echo "unknown")"

echo "mode=${mode} ubuntu_version=${ubuntu_version} ofed_fid=${ofed_fid:-}"

export DEBIAN_FRONTEND=noninteractive

# --- Base packages ---
sudo apt update -y
sudo apt install -y curl wget ca-certificates git build-essential pkg-config lsb-release \
                    gpg gpg-agent cmake libssl-dev unzip zsh

# ---------- Anaconda (Conda) ----------
INSTALL_DIR="$(pwd)/install"
mkdir -p "$INSTALL_DIR"

# Move ofed.tgz into install/ only if it exists (your OFED download block is commented)
[ -f ofed.tgz ] && mv -f ofed.tgz "$INSTALL_DIR/"

cd "$INSTALL_DIR"

if [ ! -f "./anaconda-install.sh" ]; then
  wget -q https://repo.anaconda.com/archive/Anaconda3-2022.05-Linux-x86_64.sh -O anaconda-install.sh
fi

# Install only once
if [ ! -d "$HOME/anaconda3" ]; then
  chmod +x anaconda-install.sh
  ./anaconda-install.sh -b -p "$HOME/anaconda3"
fi

# Make conda available to THIS script (non-interactive shell)
if [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
  # Preferred: defines the 'conda' function
  . "$HOME/anaconda3/etc/profile.d/conda.sh"
else
  # Fallback for old installers
  export PATH="$HOME/anaconda3/bin:$PATH"
  if command -v conda >/dev/null 2>&1; then
    eval "$(conda shell.bash hook)"
  fi
fi

# Persist PATH for future shells (avoid duplicates)
grep -qxF 'export PATH="$HOME/anaconda3/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null || \
  echo 'export PATH="$HOME/anaconda3/bin:$PATH"' >> "$HOME/.bashrc"
grep -qxF 'export PATH="$HOME/anaconda3/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null || \
  echo 'export PATH="$HOME/anaconda3/bin:$PATH"' >> "$HOME/.zshrc"

# Initialize shell startup files (idempotent)
conda init bash >/dev/null 2>&1 || true
conda init zsh  >/dev/null 2>&1 || true

# Use conda now
conda activate base

cd - >/dev/null

# ---------- Python utilities ----------
# Use conda's pip explicitly to avoid mixing system pip
python3 -m pip install gdown
python3 -m pip install fabric

# ---------- Memcached / Boost (as in your script) ----------
sudo apt install -y libmemcached-dev memcached libboost-all-dev

# ---------- OFED (if ofed.tgz provided) ----------
cd "$INSTALL_DIR"
if [ -f "./ofed.tgz" ]; then
  if [ ! -d "./ofed" ]; then
    tar zxf ofed.tgz
    # The extracted folder starts with MLNX...
    mv MLNX* ofed
  fi
  cd ofed
  sudo ./mlnxofedinstall --force
  if [ "${mode}" = "scalestore" ]; then
    sudo /etc/init.d/openibd restart || true
  fi
  cd ..
else
  echo "Skip OFED: no ofed.tgz present."
fi
cd - >/dev/null

# ---------- CMake 3.16.8 (source build, only if not already that version) ----------
cd "$INSTALL_DIR"
if [ ! -f "cmake-3.16.8.tar.gz" ]; then
  wget https://cmake.org/files/v3.16/cmake-3.16.8.tar.gz
fi
if [ ! -d "./cmake-3.16.8" ]; then
  tar zxf cmake-3.16.8.tar.gz
  cd cmake-3.16.8
  ./configure
  make -j"$(nproc)"
  sudo make install
  cd ..
fi
cd - >/dev/null

# ---------- Redis (official repo) ----------
sudo apt update -y
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/redis.list >/dev/null
sudo apt-get update -y
sudo apt-get install -y redis

# ---------- hiredis ----------
sudo apt install -y libhiredis-dev

# ---------- redis++ (sw::redis) ----------
THIRD_PARTY_DIR="$INSTALL_DIR/third_party"
mkdir -p "$THIRD_PARTY_DIR"
if [ ! -d "$THIRD_PARTY_DIR/redis-plus-plus" ]; then
  git clone https://github.com/sewenew/redis-plus-plus.git "$THIRD_PARTY_DIR/redis-plus-plus"
fi
cd "$THIRD_PARTY_DIR/redis-plus-plus"
mkdir -p build
cd build
cmake ..
make -j"$(nproc)"
sudo make install
cd - >/dev/null
cd - >/dev/null

# ---------- GTest ----------
if [ ! -d "/usr/src/gtest" ]; then
  sudo apt install -y libgtest-dev
fi
if [ -d "/usr/src/gtest" ]; then
  cd /usr/src/gtest
  sudo cmake .
  sudo make -j"$(nproc)"
  cd - >/dev/null
fi

# ---------- oh-my-zsh ----------
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Env tweaks for both shells
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  grep -qxF 'export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/lib"' "$rc" 2>/dev/null || \
    echo 'export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/lib"' >> "$rc"
  grep -qxF 'ulimit -n unlimited' "$rc" 2>/dev/null || \
    echo 'ulimit -n unlimited' >> "$rc"
done

# Make zsh the default shell for the current user (may prompt on non-root)
if command -v zsh >/dev/null 2>&1; then
  sudo chsh "$USER" -s /bin/zsh || true
fi

# ---------- Project build dir ----------
echo "Running as: $(whoami)"
PROJECT_DIR="/root/Ditto"
if [ -d "$PROJECT_DIR" ]; then
  mkdir -p "$PROJECT_DIR/build"
else
  echo "Note: $PROJECT_DIR does not exist; skipping build dir creation."
fi


sudo apt-get install -y libboost-all-dev build-essential cmake
sudo apt-get install -y apt
sudo apt-get install -y memcached
python -m pip install gdrive


echo "Installing core dependencies..."
sudo apt-get install -y \
  build-essential \
  cmake \
  libmemcached-dev \
  libgtest-dev \
  memcached \
  redis-server \
  libhiredis-dev \
  pip

echo "Installing redis++ (redis-plus-plus)..."
# Redis++ depends on hiredis, so we build from source
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

git clone https://github.com/sewenew/redis-plus-plus.git
cd redis-plus-plus

mkdir -p build && cd build
cmake -DREDIS_PLUS_PLUS_CXX_STANDARD=17 ..
make -j$(nproc)
sudo make install



echo "✅ All done."
