# Minimal GitHub Actions Security Test

## Overview
A fast, self-contained GitHub Actions workflow that validates Terraform security improvements without requiring infrastructure or secrets.

## Features
- **Fast Execution**: Runs in ~2 minutes without external dependencies
- **No Secrets Required**: Tests configuration files only
- **Comprehensive Coverage**: Validates all security improvements
- **PR Integration**: Provides comments with test results
- **Self-Contained**: No external services or infrastructure needed

## Trigger Conditions
- **Pull Requests**: When terraform/ files change
- **Push to main**: When terraform/ files change  
- **Manual**: Via workflow_dispatch

## Test Coverage

### 1. Backend Configuration
- Validates that backend block doesn't use variables
- Ensures proper `-backend-config` usage

### 2. Sensitive Variables
- Checks that all sensitive variables are marked `sensitive = true`
- Validates: `pg_conn_str`, `proxmox_api_url`, `proxmox_api_token`, `ssh_public_key`

### 3. Secret Interpolation
- Verifies that local-exec commands use environment variables
- Prevents direct variable interpolation in shell commands

### 4. Unified Preflight Behavior
- Ensures consistent warning behavior across all VM checks
- No blocking `exit 1` commands in pre-flight checks

### 5. Provider Documentation
- Validates TLS justification for `insecure = true`
- Ensures security decisions are documented

### 6. Configuration Validation
- Tests Terraform syntax and structure
- Validates HCL configuration correctness

## Output
- **PR Comments**: Detailed results on pull requests
- **Console Output**: Clear test status in workflow logs
- **Pass/Fail**: Stops workflow on critical security failures

## Usage

### Local Testing
```bash
# Run simulation
./test_workflow_sim.sh

# Run minimal test
./test_minimal.sh
```

### GitHub Actions
The workflow runs automatically on:
- Pull requests to terraform/ files
- Push to main branch with terraform/ changes
- Manual trigger via GitHub UI

## Security Benefits
- **Early Detection**: Catches security issues before merge
- **Consistent Validation**: Same checks in CI and local development
- **No Secret Exposure**: Tests configuration only, no secrets required
- **Fast Feedback**: Quick results without infrastructure setup

## Integration
This workflow complements the existing `vault-deploy.yml` workflow:
- **Security Test**: Fast validation, runs on every PR
- **Deploy Workflow**: Full infrastructure deployment, runs on main

The minimal security test provides immediate feedback on security improvements while the deploy workflow handles actual infrastructure changes.