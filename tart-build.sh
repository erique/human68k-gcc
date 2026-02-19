#!/bin/bash
set -euo pipefail

# Build human68k-gcc in an ephemeral Tart macOS VM.
# Requires: tart (https://tart.run) and sshpass on Apple Silicon Mac.

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "ERROR: This script requires an Apple Silicon Mac."
    exit 1
fi

for cmd in tart sshpass git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: '$cmd' is not installed."
        exit 1
    fi
done

VM_NAME="human68k-build-$$"
VM_BASE="ghcr.io/cirruslabs/macos-sequoia-base:latest"
VM_CACHED="human68k-brewed"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
SSH_USER="admin"
SSH_PASS="admin"
REPO_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
REPO_URL="$(git remote get-url origin | sed 's|git@github.com:|https://github.com/|')"

cleanup() {
    echo "Cleaning up VM ${VM_NAME}..."
    tart stop "$VM_NAME" 2>/dev/null || true
    tart delete "$VM_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Use cached image with brew packages pre-installed, or create it.
if tart list | grep -q "$VM_CACHED"; then
    echo "==> Using cached image ${VM_CACHED}"
    tart clone "$VM_CACHED" "$VM_NAME"
    NEED_BREW=false
else
    echo "==> No cached image found, creating from ${VM_BASE}..."
    tart clone "$VM_BASE" "$VM_NAME"
    NEED_BREW=true
fi

echo "==> Starting VM..."
tart run "$VM_NAME" &
VM_PID=$!

echo "==> Waiting for VM to boot..."
for i in $(seq 1 60); do
    VM_IP="$(tart ip "$VM_NAME" 2>/dev/null || true)"
    if [ -n "$VM_IP" ]; then
        if sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$VM_IP" true 2>/dev/null; then
            break
        fi
    fi
    sleep 5
done

if [ -z "${VM_IP:-}" ]; then
    echo "ERROR: VM did not become reachable within timeout"
    exit 1
fi

echo "==> VM is up at ${VM_IP}"

run_ssh() {
    sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$VM_IP" "$@"
}

run_scp() {
    sshpass -p "$SSH_PASS" scp $SSH_OPTS "$@"
}

if [ "$NEED_BREW" = true ]; then
    echo "==> Installing Homebrew (if needed)..."
    run_ssh 'command -v brew >/dev/null 2>&1 || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

    echo "==> Installing build dependencies..."
    run_ssh 'eval "$(/opt/homebrew/bin/brew shellenv)" && brew install bison gnu-sed bash make wget flex texinfo rsync gmp mpfr libmpc ncurses cmake lhasa gcc@12 dejagnu'

    echo "==> Saving cached image as ${VM_CACHED}..."
    tart stop "$VM_NAME"
    wait "$VM_PID" 2>/dev/null || true
    tart clone "$VM_NAME" "$VM_CACHED"

    echo "==> Restarting VM..."
    tart run "$VM_NAME" &
    VM_PID=$!
    for i in $(seq 1 60); do
        VM_IP="$(tart ip "$VM_NAME" 2>/dev/null || true)"
        if [ -n "$VM_IP" ]; then
            if sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$VM_IP" true 2>/dev/null; then
                break
            fi
        fi
        sleep 5
    done
fi

echo "==> Cloning repository (branch: ${REPO_BRANCH})..."
run_ssh "git clone -b ${REPO_BRANCH} --depth 16 ${REPO_URL} ~/human68k-gcc"

echo "==> Building (make update && make -j min)..."
run_ssh 'eval "$(/opt/homebrew/bin/brew shellenv)" && cd ~/human68k-gcc && \
    PREFIX=$PWD/out \
    PATH="$(brew --prefix bison)/bin:$(brew --prefix gnu-sed)/libexec/gnubin:$PATH" \
    CC=gcc-12 CXX=g++-12 \
    gmake update SHELL="$(brew --prefix)/bin/bash" && \
    PREFIX=$PWD/out \
    PATH="$(brew --prefix bison)/bin:$(brew --prefix gnu-sed)/libexec/gnubin:$PATH" \
    CC=gcc-12 CXX=g++-12 \
    gmake -j min SHELL="$(brew --prefix)/bin/bash"'

echo "==> Building (make -j all)..."
run_ssh 'eval "$(/opt/homebrew/bin/brew shellenv)" && cd ~/human68k-gcc && \
    PREFIX=$PWD/out \
    PATH="$(brew --prefix bison)/bin:$(brew --prefix gnu-sed)/libexec/gnubin:$PATH" \
    CC=gcc-12 CXX=g++-12 \
    gmake -j all SHELL="$(brew --prefix)/bin/bash"'

echo "==> Running tests (make check)..."
run_ssh 'eval "$(/opt/homebrew/bin/brew shellenv)" && cd ~/human68k-gcc && \
    PREFIX=$PWD/out \
    PATH="$(brew --prefix bison)/bin:$(brew --prefix gnu-sed)/libexec/gnubin:$PATH" \
    CC=gcc-12 CXX=g++-12 \
    gmake check SHELL="$(brew --prefix)/bin/bash"'

echo "==> Copying artifacts..."
mkdir -p out
run_scp -r "$SSH_USER@$VM_IP:~/human68k-gcc/out/" out/

echo "==> Done. Artifacts are in out/"
