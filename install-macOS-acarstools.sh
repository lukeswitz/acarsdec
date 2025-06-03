#!/bin/bash

# ACARS SDR Tools Installer for macOS
# This script installs libacars, acarsdec, and dependencies for ACARS decoding

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    log_error "This script is designed for macOS only"
    exit 1
fi

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    log_error "Homebrew is required but not installed"
    log_info "Install Homebrew from: https://brew.sh"
    exit 1
fi

# Check for required tools
if ! command -v git &> /dev/null; then
    log_error "Git is required but not installed"
    exit 1
fi

if ! command -v cmake &> /dev/null; then
    log_error "CMake is required but not installed"
    log_info "Install with: brew install cmake"
    exit 1
fi

log_info "Starting ACARS SDR Tools installation..."

# Install dependencies via Homebrew
log_info "Installing dependencies via Homebrew..."
BREW_DEPS=(
    "libsndfile"      # Audio file support
    "cjson"           # JSON output support
    "paho-mqtt-c"     # MQTT output support
    "librtlsdr"       # RTL-SDR support
    "soapysdr"        # Universal SDR support
    "airspy"          # Airspy SDR support
    "pkg-config"      # Build dependency
)

for dep in "${BREW_DEPS[@]}"; do
    if brew list "$dep" &>/dev/null; then
        log_success "$dep already installed"
    else
        log_info "Installing $dep..."
        brew install "$dep"
    fi
done

# Create working directory
WORK_DIR="$HOME/acars_sdr_build"
log_info "Creating working directory: $WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Function to build libacars
build_libacars() {
    log_info "Building libacars from source..."
    
    if [[ -d "libacars" ]]; then
        log_info "Removing existing libacars directory..."
        rm -rf libacars
    fi
    
    git clone https://github.com/szpajder/libacars.git
    cd libacars
    
    mkdir -p build
    cd build
    
    cmake .. \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_INSTALL_RPATH="/usr/local/lib" \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=TRUE
    
    make -j$(sysctl -n hw.ncpu)
    sudo make install
    
    # Fix library paths for libacars tools
    log_info "Fixing library paths for libacars tools..."
    LIBACARS_TOOLS=(
        "/usr/local/bin/decode_acars_apps"
        "/usr/local/bin/adsc_get_position"
        "/usr/local/bin/cpdlc_get_position"
    )
    
    for tool in "${LIBACARS_TOOLS[@]}"; do
        if [[ -f "$tool" ]]; then
            sudo install_name_tool -change @rpath/libacars-2.2.dylib /usr/local/lib/libacars-2.2.dylib "$tool"
            log_success "Fixed library path for $(basename "$tool")"
        fi
    done
    
    cd "$WORK_DIR"
    log_success "libacars installation completed"
}

# Function to build acarsdec
build_acarsdec() {
    log_info "Building acarsdec from source..."
    
    if [[ -d "acarsdec" ]]; then
        log_info "Removing existing acarsdec directory..."
        rm -rf acarsdec
    fi
    
    git clone https://github.com/TLeconte/acarsdec.git
    cd acarsdec
    
    # Backup original CMakeLists.txt
    cp CMakeLists.txt CMakeLists.txt.backup
    
    # Disable ALSA (Linux-only, causes issues on macOS)
    log_info "Disabling ALSA support (not needed on macOS)..."
    sed -i '' '36,46s/^/#/' CMakeLists.txt
    
    mkdir -p build
    cd build
    
    cmake .. \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_INSTALL_RPATH="/usr/local/lib"
    
    make -j$(sysctl -n hw.ncpu)
    sudo make install
    
    # Fix library path for acarsdec
    log_info "Fixing library path for acarsdec..."
    sudo install_name_tool -change @rpath/libacars-2.2.dylib /usr/local/lib/libacars-2.2.dylib /usr/local/bin/acarsdec
    
    # Restore original CMakeLists.txt
    mv ../CMakeLists.txt.backup ../CMakeLists.txt
    
    cd "$WORK_DIR"
    log_success "acarsdec installation completed"
}

# Function to verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    TOOLS_TO_CHECK=(
        "acarsdec"
        "decode_acars_apps"
        "adsc_get_position"
        "cpdlc_get_position"
    )
    
    ALL_GOOD=true
    
    for tool in "${TOOLS_TO_CHECK[@]}"; do
        if command -v "$tool" &> /dev/null; then
            # Test that the tool can load (doesn't crash with library errors)
            if "$tool" --help &>/dev/null || "$tool" -h &>/dev/null || "$tool" 2>&1 | grep -q "Usage\|usage\|USAGE" || [[ $? -eq 1 ]]; then
                log_success "$tool installed and working"
            else
                log_error "$tool installed but may have library issues"
                ALL_GOOD=false
            fi
        else
            log_error "$tool not found in PATH"
            ALL_GOOD=false
        fi
    done
    
    if $ALL_GOOD; then
        log_success "All tools installed successfully!"
    else
        log_warning "Some tools may have issues"
    fi
}

# Function to display usage information
show_usage_info() {
    log_info "Installation completed! Here's how to use the tools:"
    echo
    echo -e "${GREEN}ACARS Decoding:${NC}"
    echo "  acarsdec -r 0 131.550 131.525 131.475  # Decode from RTL-SDR"
    echo "  acarsdec -s - 131.550                   # Decode from audio file/stdin"
    echo
    echo -e "${GREEN}ACARS Message Analysis:${NC}"
    echo "  decode_acars_apps < messages.txt        # Decode ACARS applications"
    echo "  adsc_get_position < messages.txt        # Extract ADS-C position data"
    echo "  cpdlc_get_position < messages.txt       # Extract CPDLC position data"
    echo
    echo -e "${GREEN}Supported SDR Hardware:${NC}"
    echo "  - RTL-SDR dongles"
    echo "  - Airspy devices" 
    echo "  - Any SoapySDR-compatible devices"
    echo
    echo -e "${GREEN}Output Options:${NC}"
    echo "  - JSON format (with libcjson)"
    echo "  - MQTT publishing (with paho-mqtt)"
    echo "  - File output"
    echo "  - Network output"
    echo
    echo -e "${YELLOW}Note:${NC} ALSA support is disabled (not needed on macOS)"
    echo -e "${YELLOW}Note:${NC} SDRplay support requires separate proprietary drivers"
}

# Main installation process
main() {
    log_info "ACARS SDR Tools Installer for macOS"
    echo
    
    # Ask for confirmation
    read -p "This will install libacars and acarsdec. Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    # Build and install
    build_libacars
    build_acarsdec
    
    # Verify everything works
    verify_installation
    
    # Show usage information
    show_usage_info
    
    # Cleanup
    log_info "Cleaning up build directory..."
    cd "$HOME"
    rm -rf "$WORK_DIR"
    
    log_success "Installation complete!"
}

# Run main function
main "$@"
