#!/bin/bash
#
# Local test script for validating Terraform and GitHub Actions workflows
# Run this before pushing to avoid failed CI runs
#
# Usage:
#   ./test-local.sh              # Run all tests
#   ./test-local.sh --quick      # Quick syntax checks only (no connectivity)
#   ./test-local.sh --full       # Full test including terraform plan
#

set -uo pipefail
# Note: -e is not set so individual check failures don't exit the script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
WORKFLOWS_DIR="${SCRIPT_DIR}/.github/workflows"

# Test mode
TEST_MODE="${1:-standard}"

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------

print_header() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_section() {
    echo
    echo -e "${YELLOW}▶ $1${NC}"
}

pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASSED++))
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAILED++))
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        pass "$1 is installed ($(command -v "$1"))"
        return 0
    else
        fail "$1 is not installed"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Prerequisites check
#------------------------------------------------------------------------------

check_prerequisites() {
    print_header "Checking Prerequisites"

    print_section "Required tools"
    check_command terraform || true
    check_command vault || true
    check_command curl || true
    check_command jq || true

    print_section "Optional tools"
    if command -v python3 &> /dev/null; then
        pass "python3 is installed"
        if python3 -c "import yaml" 2>/dev/null; then
            pass "PyYAML module available"
        else
            warn "PyYAML not installed (pip install pyyaml)"
        fi
    else
        warn "python3 not installed - some YAML checks will be skipped"
    fi

    if command -v yamllint &> /dev/null; then
        pass "yamllint is installed"
    else
        warn "yamllint not installed - install for better YAML validation"
    fi

    if command -v actionlint &> /dev/null; then
        pass "actionlint is installed"
    else
        warn "actionlint not installed - install for GitHub Actions validation"
        info "  Install: go install github.com/rhysd/actionlint/cmd/actionlint@latest"
    fi
}

#------------------------------------------------------------------------------
# File structure validation
#------------------------------------------------------------------------------

check_file_structure() {
    print_header "Checking File Structure"

    print_section "Terraform files"
    if [ -d "$TERRAFORM_DIR" ]; then
        pass "terraform/ directory exists"
    else
        fail "terraform/ directory missing"
        return 1
    fi

    local tf_files=("main.tf" "variables.tf" "outputs.tf")
    for file in "${tf_files[@]}"; do
        if [ -f "${TERRAFORM_DIR}/${file}" ]; then
            pass "${file} exists"
        else
            warn "${file} missing"
        fi
    done

    print_section "Workflow files"
    if [ -d "$WORKFLOWS_DIR" ]; then
        pass ".github/workflows/ directory exists"
    else
        fail ".github/workflows/ directory missing"
        return 1
    fi

    local workflow_count
    workflow_count=$(find "$WORKFLOWS_DIR" -name "*.yml" -o -name "*.yaml" 2>/dev/null | wc -l)
    info "Found ${workflow_count} workflow file(s)"
}

#------------------------------------------------------------------------------
# YAML validation
#------------------------------------------------------------------------------

validate_yaml() {
    print_header "Validating YAML Syntax"

    print_section "Workflow files"
    for file in "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml; do
        [ -f "$file" ] || continue
        local filename
        filename=$(basename "$file")

        # Basic YAML syntax check with Python
        if command -v python3 &> /dev/null && python3 -c "import yaml" 2>/dev/null; then
            if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
                pass "$filename - valid YAML syntax"
            else
                fail "$filename - invalid YAML syntax"
            fi
        fi

        # yamllint check if available
        if command -v yamllint &> /dev/null; then
            if yamllint -d relaxed "$file" 2>/dev/null; then
                pass "$filename - passes yamllint"
            else
                warn "$filename - yamllint warnings (run: yamllint $file)"
            fi
        fi
    done

    # actionlint for GitHub Actions specific validation
    if command -v actionlint &> /dev/null; then
        print_section "GitHub Actions validation (actionlint)"
        if actionlint "$WORKFLOWS_DIR"/*.yml 2>&1; then
            pass "All workflows pass actionlint"
        else
            warn "actionlint found issues (see above)"
        fi
    fi
}

#------------------------------------------------------------------------------
# Terraform validation
#------------------------------------------------------------------------------

validate_terraform() {
    print_header "Validating Terraform Configuration"

    if ! command -v terraform &> /dev/null; then
        fail "terraform not installed - skipping terraform checks"
        return 1
    fi

    cd "$TERRAFORM_DIR"

    print_section "Terraform format check"
    if terraform fmt -check -recursive . 2>/dev/null; then
        pass "Terraform files are properly formatted"
    else
        warn "Terraform files need formatting (run: terraform fmt)"
        info "  Files that need formatting:"
        terraform fmt -check -recursive . 2>&1 | head -5 || true
    fi

    print_section "Terraform syntax validation"
    # Initialize with a local backend for validation only
    if terraform init -backend=false -input=false 2>/dev/null; then
        pass "Terraform init (local) succeeded"

        if terraform validate 2>/dev/null; then
            pass "Terraform validate succeeded"
        else
            fail "Terraform validate failed"
            terraform validate 2>&1 | head -10 || true
        fi
    else
        fail "Terraform init failed"
    fi

    cd "$SCRIPT_DIR"
}

#------------------------------------------------------------------------------
# Environment and secrets check
#------------------------------------------------------------------------------

check_environment() {
    print_header "Checking Environment Variables"

    print_section "Vault configuration"
    if [ -n "${VAULT_ADDR:-}" ]; then
        pass "VAULT_ADDR is set: $VAULT_ADDR"
    else
        warn "VAULT_ADDR not set"
        info "  Export: export VAULT_ADDR=https://10.0.10.21:8200"
    fi

    if [ -n "${VAULT_TOKEN:-}" ]; then
        pass "VAULT_TOKEN is set"
    else
        warn "VAULT_TOKEN not set (needed for vault CLI)"
    fi

    print_section "Terraform variables (TF_VAR_*)"
    local tf_vars=("proxmox_api_url" "proxmox_api_token" "ssh_public_key")
    for var in "${tf_vars[@]}"; do
        local env_var="TF_VAR_${var}"
        if [ -n "${!env_var:-}" ]; then
            pass "$env_var is set"
        else
            warn "$env_var not set"
        fi
    done

    print_section "PostgreSQL backend"
    if [ -n "${PG_CONN_STR:-}" ]; then
        pass "PG_CONN_STR is set"
    else
        warn "PG_CONN_STR not set (needed for terraform state backend)"
    fi
}

#------------------------------------------------------------------------------
# Connectivity tests
#------------------------------------------------------------------------------

test_connectivity() {
    print_header "Testing Connectivity"

    print_section "Vault connectivity"
    if [ -n "${VAULT_ADDR:-}" ]; then
        if curl -sk --connect-timeout 5 "${VAULT_ADDR}/v1/sys/health" 2>/dev/null | jq -e '.initialized' > /dev/null 2>&1; then
            pass "Vault is reachable and initialized"

            # Check if we can authenticate
            if [ -n "${VAULT_TOKEN:-}" ]; then
                if vault token lookup &>/dev/null; then
                    pass "Vault token is valid"
                else
                    warn "Vault token is invalid or expired"
                fi
            fi
        else
            fail "Cannot connect to Vault at $VAULT_ADDR"
        fi
    else
        info "Skipping Vault connectivity (VAULT_ADDR not set)"
    fi

    print_section "Proxmox connectivity"
    if [ -n "${TF_VAR_proxmox_api_url:-}" ] && [ -n "${TF_VAR_proxmox_api_token:-}" ]; then
        local api_response
        api_response=$(curl -sk --connect-timeout 5 \
            -H "Authorization: PVEAPIToken=${TF_VAR_proxmox_api_token}" \
            "${TF_VAR_proxmox_api_url}/api2/json/version" 2>/dev/null)

        if echo "$api_response" | jq -e '.data.version' > /dev/null 2>&1; then
            local pve_version
            pve_version=$(echo "$api_response" | jq -r '.data.version')
            pass "Proxmox API is reachable (version: $pve_version)"
        else
            fail "Cannot authenticate with Proxmox API"
            info "  Check your API token format: user@realm!tokenid=secret"
        fi
    else
        info "Skipping Proxmox connectivity (credentials not set)"
    fi

    print_section "PostgreSQL connectivity"
    if [ -n "${PG_CONN_STR:-}" ]; then
        # Extract host from connection string for basic connectivity test
        local pg_host
        pg_host=$(echo "$PG_CONN_STR" | grep -oP '(?<=@)[^:/]+' || echo "")
        if [ -n "$pg_host" ]; then
            if nc -z -w5 "$pg_host" 5432 2>/dev/null; then
                pass "PostgreSQL port is reachable at $pg_host"
            else
                warn "Cannot reach PostgreSQL at $pg_host:5432"
            fi
        else
            info "Could not extract host from PG_CONN_STR"
        fi
    else
        info "Skipping PostgreSQL connectivity (PG_CONN_STR not set)"
    fi
}

#------------------------------------------------------------------------------
# Full terraform plan test
#------------------------------------------------------------------------------

test_terraform_plan() {
    print_header "Testing Terraform Plan (Full)"

    if [ -z "${PG_CONN_STR:-}" ]; then
        warn "Cannot run terraform plan - PG_CONN_STR not set"
        return 1
    fi

    if [ -z "${TF_VAR_proxmox_api_url:-}" ] || [ -z "${TF_VAR_proxmox_api_token:-}" ]; then
        warn "Cannot run terraform plan - Proxmox credentials not set"
        return 1
    fi

    cd "$TERRAFORM_DIR"

    print_section "Terraform init with backend"
    if terraform init -backend-config="conn_str=${PG_CONN_STR}" -input=false 2>&1 | tail -5; then
        pass "Terraform init with backend succeeded"
    else
        fail "Terraform init with backend failed"
        cd "$SCRIPT_DIR"
        return 1
    fi

    print_section "Terraform plan"
    info "Running terraform plan (this may take a while)..."
    if terraform plan -input=false -no-color 2>&1 | tail -20; then
        pass "Terraform plan succeeded"
    else
        fail "Terraform plan failed"
    fi

    cd "$SCRIPT_DIR"
}

#------------------------------------------------------------------------------
# Workflow-specific checks
#------------------------------------------------------------------------------

check_workflow_issues() {
    print_header "Checking Known Workflow Issues"

    print_section "terraform-check.yml"
    local tc_file="${WORKFLOWS_DIR}/terraform-check.yml"
    if [ -f "$tc_file" ]; then
        # Check for pull-requests permission
        if grep -q "pull-requests: write" "$tc_file"; then
            pass "Has pull-requests: write permission"
        else
            warn "Missing 'pull-requests: write' permission for PR comments"
        fi

        # Check for invalid peter-evans parameters
        if grep -q "title:" "$tc_file" && grep -q "peter-evans/create-or-update-comment" "$tc_file"; then
            warn "'title' is not a valid parameter for peter-evans/create-or-update-comment"
        fi

        # Check Vault path consistency
        if grep -q "secret/infrastructure/" "$tc_file" && ! grep -q "secret/data/infrastructure/" "$tc_file"; then
            info "Uses Vault KV v1 paths (secret/infrastructure/...)"
        fi
    fi

    print_section "terraform-check-improved.yml"
    local tci_file="${WORKFLOWS_DIR}/terraform-check-improved.yml"
    if [ -f "$tci_file" ]; then
        # Check for command substitution in YAML
        if grep -q '\$(terraform' "$tci_file"; then
            warn "Contains command substitution in YAML that may not execute"
        fi

        # Check for plan.txt reference without creation
        if grep -q "plan.txt" "$tci_file" && ! grep -q "tee plan.txt" "$tci_file"; then
            warn "References plan.txt but never creates it"
        fi
    fi

    print_section "vault-deploy.yml"
    local vd_file="${WORKFLOWS_DIR}/vault-deploy.yml"
    if [ -f "$vd_file" ]; then
        # Check for hardcoded paths
        if grep -q "/home/runner/_work/_temp/" "$vd_file"; then
            warn "Contains hardcoded runner paths that will break"
        fi

        # Check for hardcoded Vault URL
        if grep -q "url: https://10.0.10.21:8200" "$vd_file"; then
            warn "Has hardcoded Vault URL instead of using secrets.VAULT_ADDR"
        fi
    fi
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

print_summary() {
    print_header "Test Summary"

    echo
    echo -e "  ${GREEN}Passed:${NC}   $PASSED"
    echo -e "  ${RED}Failed:${NC}   $FAILED"
    echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
    echo

    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All critical tests passed!${NC}"
        if [ $WARNINGS -gt 0 ]; then
            echo -e "${YELLOW}Review the warnings above before committing.${NC}"
        fi
        return 0
    else
        echo -e "${RED}Some tests failed. Fix the issues above before committing.${NC}"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    echo
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Local Infrastructure Validation Script                ║${NC}"
    echo -e "${BLUE}║         Run before pushing to avoid CI failures               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"

    case "$TEST_MODE" in
        --quick|-q)
            info "Running quick checks (syntax only)..."
            check_prerequisites
            check_file_structure
            validate_yaml
            validate_terraform
            check_workflow_issues
            ;;
        --full|-f)
            info "Running full test suite including terraform plan..."
            check_prerequisites
            check_file_structure
            validate_yaml
            validate_terraform
            check_environment
            test_connectivity
            check_workflow_issues
            test_terraform_plan
            ;;
        *)
            info "Running standard checks..."
            check_prerequisites
            check_file_structure
            validate_yaml
            validate_terraform
            check_environment
            test_connectivity
            check_workflow_issues
            ;;
    esac

    print_summary
}

main "$@"
