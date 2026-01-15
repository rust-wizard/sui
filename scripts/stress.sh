#!/bin/bash
# Copyright (c) Mysten Labs, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Script to run stress tests against a SUI cluster bootstrapped by cluster.sh

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
    echo "  -h, --help                     Show this help message"
    echo "  --config-path PATH             Specify custom config directory path (default: target/debug/config)"
    echo "  --target-qps QPS               Target queries per second (default: 100)"
    echo "  --duration DURATION            Duration to run the test (default: unbounded)"
    echo "  --workload WORKLOAD            Workload type (default: transfer-object:100)"
    echo "                                  Format: workload_name:percentage (e.g., shared-counter:50,transfer-object:50)"
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
            --config-path)
                CUSTOM_CONFIG_PATH="$2"
                shift 2
                ;;
            --target-qps)
                TARGET_QPS="$2"
                shift 2
                ;;
            --duration)
                DURATION="$2"
                shift 2
                ;;
            --workload)
                WORKLOAD="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    CUSTOM_CONFIG_PATH="${CUSTOM_CONFIG_PATH:-target/debug/config}"
    TARGET_QPS="${TARGET_QPS:-100}"
    DURATION="${DURATION:-unbounded}"
    WORKLOAD="${WORKLOAD:-transfer-object:100}"
}

# Get RPC address from config
get_rpc_address() {
    RPC_ADDRESS="http://127.0.0.1:9000"
    print_info "Using RPC address: $RPC_ADDRESS"
}

# Get genesis file path
get_genesis_path() {
    print_info "Checking genesis file path..."

    GENESIS_PATH="$CUSTOM_CONFIG_PATH/genesis.blob"
    if [ ! -f "$GENESIS_PATH" ]; then
        print_error "Genesis file not found at $GENESIS_PATH"
        exit 1
    fi

    print_info "Genesis file found at: $GENESIS_PATH"
}

# Get keystore path
get_keystore_path() {
    KEYSTORE_PATH="$CUSTOM_CONFIG_PATH/sui.keystore"
}

# Get active address using sui client
get_active_address() {
    SUI_CLIENT_CONFIG="$CUSTOM_CONFIG_PATH/client.yaml"
    ACTIVE_ADDRESS=$(./target/debug/sui client --client.config $SUI_CLIENT_CONFIG --json active-address | jq -r '.')
    print_info "Active address: $ACTIVE_ADDRESS"
}

# Get primary gas object ID for the active address
get_primary_gas_id() {
    print_info "Getting primary gas object ID for active address..."

    # Set up environment for sui client
    export SUI_CLIENT_CONFIG="$CUSTOM_CONFIG_PATH/client.yaml"

    # Get gas objects for the active address
    GAS_OBJECTS_JSON=$(./target/debug/sui client --json get-gas 2>/dev/null || echo "")

    if [ -z "$GAS_OBJECTS_JSON" ] || [ "$GAS_OBJECTS_JSON" = "null" ]; then
        print_error "Could not get gas objects for address $ACTIVE_ADDRESS"
        print_info "Make sure the address has gas objects available"
        exit 1
    fi

    # Extract the object ID of the first gas object with the highest gas value
    PRIMARY_GAS_ID=$(echo "$GAS_OBJECTS_JSON" | jq -r '.result[] | select(.gasObject) | .gasObject.objectId' | head -n1)

    if [ -z "$PRIMARY_GAS_ID" ] || [ "$PRIMARY_GAS_ID" = "null" ]; then
        print_error "Could not find a valid gas object ID for address $ACTIVE_ADDRESS"
        exit 1
    fi

    print_info "Primary gas object ID: $PRIMARY_GAS_ID"
}

# Parse workload string into benchmark parameters
parse_workload() {
    print_info "Parsing workload: $WORKLOAD"

    # Initialize arrays
    unset SHARED_COUNTER_WEIGHTS
    unset TRANSFER_OBJECT_WEIGHTS
    SHARED_COUNTER_WEIGHTS=()
    TRANSFER_OBJECT_WEIGHTS=()

    # Split workload by comma to handle multiple workload types
    IFS=',' read -ra PAIRS <<< "$WORKLOAD"
    for pair in "${PAIRS[@]}"; do
        IFS=':' read -ra PARTS <<< "$pair"
        workload_name="${PARTS[0]}"
        workload_weight="${PARTS[1]}"

        case "$workload_name" in
            "shared-counter")
                SHARED_COUNTER_WEIGHTS+=("$workload_weight")
                ;;
            "transfer-object")
                TRANSFER_OBJECT_WEIGHTS+=("$workload_weight")
                ;;
            *)
                print_warn "Unknown workload type: $workload_name, ignoring"
                ;;
        esac
    done

    # If no weights were set, default to transfer-object:100
    if [ ${#SHARED_COUNTER_WEIGHTS[@]} -eq 0 ] && [ ${#TRANSFER_OBJECT_WEIGHTS[@]} -eq 0 ]; then
        TRANSFER_OBJECT_WEIGHTS=("100")
    fi

    # If only one workload type was specified, set the other to 0
    if [ ${#SHARED_COUNTER_WEIGHTS[@]} -eq 0 ]; then
        SHARED_COUNTER_WEIGHTS=("0")
    fi
    if [ ${#TRANSFER_OBJECT_WEIGHTS[@]} -eq 0 ]; then
        TRANSFER_OBJECT_WEIGHTS=("0")
    fi

    # Use the first values for now (we could extend this to support multiple benchmark groups)
    SHARED_COUNTER_WEIGHT="${SHARED_COUNTER_WEIGHTS[0]}"
    TRANSFER_OBJECT_WEIGHT="${TRANSFER_OBJECT_WEIGHTS[0]}"

    print_info "Parsed workload - shared-counter: $SHARED_COUNTER_WEIGHT, transfer-object: $TRANSFER_OBJECT_WEIGHT"
}

# Run stress test
run_stress_test() {
    print_info "Running stress test with parameters:"
    print_info "  RPC Address: $RPC_ADDRESS"
    print_info "  Genesis Path: $GENESIS_PATH"
    print_info "  Keystore Path: $KEYSTORE_PATH"
    print_info "  Primary Gas Owner: $ACTIVE_ADDRESS"
    print_info "  Target QPS: $TARGET_QPS"
    print_info "  Duration: $DURATION"
    print_info "  Workload - shared-counter: $SHARED_COUNTER_WEIGHT, transfer-object: $TRANSFER_OBJECT_WEIGHT"

    # Build the stress test command
    STRESS_CMD="cargo run --release --package sui-benchmark --bin stress -- \
        --genesis-blob-path \"$GENESIS_PATH\" \
        --keystore-path \"$KEYSTORE_PATH\" \
        --primary-gas-owner-id \"$ACTIVE_ADDRESS\" \
        --fullnode-rpc-addresses \"$RPC_ADDRESS\" \
        --num-client-threads 12 \
        --num-server-threads 10 \
        --num-transfer-accounts 2 \
        bench \
        --target-qps $TARGET_QPS \
        --in-flight-ratio 2 \
        --shared-counter $SHARED_COUNTER_WEIGHT \
        --transfer-object $TRANSFER_OBJECT_WEIGHT"

    # Add duration if specified
    if [ "$DURATION" != "unbounded" ]; then
        STRESS_CMD="$STRESS_CMD --run-duration $DURATION"
    fi

    print_info "Executing: $STRESS_CMD"
    eval $STRESS_CMD
}

# Main function
main() {
    print_info "Starting SUI stress test setup..."

    parse_args "$@"
    get_rpc_address
    get_genesis_path
    get_keystore_path
    get_active_address
    parse_workload
    run_stress_test

    print_info "SUI stress test completed!"
}

# Run main function with all arguments
main "$@"
