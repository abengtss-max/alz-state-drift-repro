# Cloud Shell State Validation Runbook

1. Set subscription context.

```bash
az account set --subscription "b9794400-1ef6-405c-be7f-2e24ba8bfa1b"
```

2. Clone repository into empty Cloud Shell filesystem.

```bash
git clone https://github.com/abengtss-max/alz-state-drift-repro.git
cd alz-state-drift-repro
```

3. Change directory to your real Terraform root folder (replace placeholder).

```bash
cd <your-real-terraform-root>
```

4. Initialize Terraform backend.

```bash
terraform init \
  -backend-config="resource_group_name=rg-alz-mgmt-state-swedencentral-001" \
  -backend-config="storage_account_name=stoalzmgmswe001nnif" \
  -backend-config="container_name=mgmt-tfstate" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="use_azuread_auth=true"
```

5. Create state backup.

```bash
terraform state pull > state-backup-before-test.tfstate
```

6. Simulate missing states by removing 14 role-assignment entries from state only.

```bash
keys=(
"Deploy-MDFC-DefSQL-AMA-managed_identity_operator"
"Deploy-MDFC-DefSQL-AMA-monitoring_contributor"
"Deploy-VM-ChangeTrack-managed_identity_operator"
"Deploy-VM-ChangeTrack-monitoring_contributor"
"Deploy-VM-Monitoring-managed_identity_operator"
"Deploy-VM-Monitoring-monitoring_contributor"
"Deploy-VMSS-ChangeTrack-managed_identity_operator"
"Deploy-VMSS-ChangeTrack-monitoring_contributor"
"Deploy-VMSS-Monitoring-managed_identity_operator"
"Deploy-VMSS-Monitoring-monitoring_contributor"
"Deploy-vmArc-ChangeTrack-managed_identity_operator"
"Deploy-vmArc-ChangeTrack-monitoring_contributor"
"Deploy-vmHybr-Monitoring-managed_identity_operator"
"Deploy-vmHybr-Monitoring-monitoring_contributor"
)
for k in "${keys[@]}"; do
  terraform state rm "azurerm_role_assignment.landing_zones_policy_mi[\"$k\"]"
done
```

7. Confirm reproduction.

```bash
terraform plan -input=false
```

Expected: Terraform wants to create the removed role-assignment resources.

8. Run import fix script.

```bash
pwsh ../scripts/import-missing-role-assignments.ps1 -TerraformRoot . -Execute
```

If pwsh is not available, use PowerShell Cloud Shell.

9. Validate fix.

```bash
terraform plan -input=false
```

Expected: the 14 create actions are gone.

10. Roll back immediately if needed.

```bash
terraform state push state-backup-before-test.tfstate
```

## Safety notes

- Do not run terraform apply during validation.
- This test changes state only, not Azure resources.
- Open storage account public access only for the shortest possible window, then disable it again.
- The import script currently contains environment-specific resource IDs and must only be used where those IDs are correct.
