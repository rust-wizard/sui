#!/bin/bash
# Copyright (c) Mysten Labs, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Script to build SUI, generate a local cluster configuration, and start the cluster.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  --force              Force rebuild and restart without confirmation"
    echo "  --config-path PATH   Specify custom config directory path (default: target/debug/config)"
    echo ""
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --config-path)
                CUSTOM_CONFIG_PATH="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    FORCE="${FORCE:-false}"
    CUSTOM_CONFIG_PATH="${CUSTOM_CONFIG_PATH:-target/debug/config}"
}

# Build the SUI crate
build_sui() {
    print_info "Building SUI crate..."
    
    if [ "$FORCE" = true ] || [ ! -f "target/debug/sui" ]; then
        cargo build -p sui
        print_info "SUI crate built successfully"
    else
        print_info "SUI binary already exists. Skipping build. Use --force to rebuild."
    fi
}

# Create config directory
create_config_directory() {
    print_info "Creating config directory: $CUSTOM_CONFIG_PATH"
    
    mkdir -p "$CUSTOM_CONFIG_PATH"
    
    if [ -d "$CUSTOM_CONFIG_PATH" ]; then
        print_info "Config directory created successfully"
    else
        print_error "Failed to create config directory: $CUSTOM_CONFIG_PATH"
        exit 1
    fi
}

# Generate local cluster configuration
generate_local_cluster() {
    print_info "Generating local cluster in config directory..."
    
    # Check if genesis already exists
    if [ -f "$CUSTOM_CONFIG_PATH/genesis.blob" ] && [ "$FORCE" != true ]; then
        print_warn "Genesis blob already exists in $CUSTOM_CONFIG_PATH"
        read -p "Do you want to regenerate the cluster? This will overwrite existing data. (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Operation cancelled"
            return 0
        fi
    fi
    
    # Generate the genesis
    ./target/debug/sui genesis --working-dir "$CUSTOM_CONFIG_PATH" --with-faucet
    
    if [ -f "$CUSTOM_CONFIG_PATH/genesis.blob" ]; then
        print_info "Local cluster generated successfully in $CUSTOM_CONFIG_PATH"
    else
        print_error "Failed to generate local cluster"
        exit 1
    fi
}

# Start the cluster
start_cluster() {
    print_info "Starting SUI cluster from config directory: $CUSTOM_CONFIG_PATH"
    
    # Check if cluster is already running
    if pgrep -f "sui.*--network.config.*$CUSTOM_CONFIG_PATH" > /dev/null; then
        print_warn "SUI cluster is already running with config directory: $CUSTOM_CONFIG_PATH"
        if [ "$FORCE" != true ]; then
            read -p "Do you want to stop the running cluster and start a new one? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Operation cancelled"
                return 0
            fi
            
            # Kill existing processes
            pkill -f "sui.*--network.config.*$CUSTOM_CONFIG_PATH" || true
            sleep 2  # Give time for processes to terminate
        else
            # Kill existing processes
            pkill -f "sui.*--network.config.*$CUSTOM_CONFIG_PATH" || true
            sleep 2  # Give time for processes to terminate
        fi
    fi
    
    # Start the cluster in the background
    print_info "Starting SUI cluster in the background..."
    export RUST_LOG="info"
    ./target/debug/sui start --network.config "$CUSTOM_CONFIG_PATH"
}

# Main function
main() {
    print_info "Starting SUI cluster setup process..." 
    parse_args "$@"
    build_sui
    create_config_directory
    generate_local_cluster
    start_cluster
}

main "$@"
