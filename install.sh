#!/bin/bash
# =============================================================================
# Claude Code iOS Setup — One-line installer
# =============================================================================
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/bguidolim/my-claude-ios-setup/main/install.sh | bash
# =============================================================================

set -euo pipefail

# Keep in sync with REPO_URL in setup.sh
REPO_URL="https://github.com/bguidolim/my-claude-ios-setup.git"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Prerequisites ---
command -v git >/dev/null 2>&1 || error "git is required. Install Xcode CLT: xcode-select --install"
[ -c /dev/tty ] || error "No terminal available. This installer must be run interactively."

# --- Clone or update to persistent location ---
INSTALL_DIR="$HOME/.claude-ios-setup"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Updating existing installation..."
    git -C "$INSTALL_DIR" pull origin main || warn "Pull failed. Continuing with existing version."
else
    if [[ -d "$INSTALL_DIR" ]]; then
        # Directory exists but isn't a git repo — move it aside
        mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%Y%m%d_%H%M%S)"
    fi
    info "Cloning setup repo..."
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>&1 | tail -1
fi

# --- Run setup ---
echo ""
echo -e "${BOLD}Running setup...${NC}"
echo ""
# Redirect stdin from terminal so setup.sh can prompt interactively
# (curl pipe consumes stdin, leaving EOF for read calls)
"$INSTALL_DIR/setup.sh" "$@" </dev/tty
