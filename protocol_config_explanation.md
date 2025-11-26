# Sui Protocol Configuration Analysis

## Code Snippet Explanation

The code snippet from `crates/sui-protocol-config/src/lib.rs` is part of the `get_for_version_impl` function, which creates protocol configurations for specific protocol versions.

### Simulator Version Handling

```rust
fn get_for_version_impl(version: ProtocolVersion, chain: Chain) -> Self {
    #[cfg(msim)]
    {
        // populate the fake simulator version # with a different base tx cost.
        if version == ProtocolVersion::MAX_ALLOWED {
            let mut config = Self::get_for_version_impl(version - 1, Chain::Unknown);
            config.base_tx_cost_fixed = Some(config.base_tx_cost_fixed() + 1000);
            return config;
        }
    }
```

This code handles simulator builds (msim configuration). In simulator mode, there's an extra protocol version available (`MAX_ALLOWED` = `MAX` + 1) that's used exclusively for testing protocol upgrades. When requesting the configuration for this maximum allowed version, the code:

1. Recursively gets the configuration for the previous version (version - 1)
2. Modifies one parameter (`base_tx_cost_fixed`) by adding 1000 to make it different
3. Returns this modified configuration

This allows simulator tests to have two distinct protocol versions to test upgrade scenarios.

## Input Parameter Source

The `version` parameter for `with_protocol_version()` comes from:
- **Command-line argument**: When using `sui genesis ceremony --protocol-version N`
- **Default value**: `ProtocolVersion::MAX` (currently version 104) when no argument is provided

## Genesis File Preparation Steps

Based on the code analysis, the steps for preparing a genesis file are:

1. **Initialize Builder**: Create a new `Builder::new()`

2. **Set Protocol Version**: Call `with_protocol_version()` with the desired version

3. **Add Validators**: Call `add_validator()` for each validator, providing their information and proof of possession

4. **Add Custom Objects** (optional): Call `add_object()` or `add_objects()` for any additional objects needed at genesis

5. **Save Initial State**: Call `save(directory_path)` to persist the initial builder state to disk files

6. **Build Unsigned Checkpoint**: Call `build_unsigned_genesis_checkpoint()` to create the initial blockchain state

7. **Collect Validator Signatures**: Each validator calls `add_validator_signature()` with their keypair to sign the checkpoint

8. **Finalize Genesis**: Call `build()` to create the final `Genesis` object with a certified checkpoint

9. **Save Final Genesis**: Save the final genesis to a file (typically `genesis.blob`)

The process involves multiple phases: initialization, building the unsigned state, collecting signatures, and final certification.
