param(
  [string]$TerraformRoot = ".",
  [switch]$Execute
)

$ErrorActionPreference = "Stop"

$imports = @(
  @{ Key = "Deploy-MDFC-DefSQL-AMA-managed_identity_operator"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/0c3ef80e-8769-bc3d-a3fd-7fd0188de45d" },
  @{ Key = "Deploy-MDFC-DefSQL-AMA-monitoring_contributor"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/48ee2ec4-bfa9-3498-56d3-f08945437526" },
  @{ Key = "Deploy-VM-ChangeTrack-managed_identity_operator"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/f694225d-ff2f-06b6-4022-5308b9a5c183" },
  @{ Key = "Deploy-VM-ChangeTrack-monitoring_contributor"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/682cdca0-e71f-07ed-aba4-fbeb9ebc303d" },
  @{ Key = "Deploy-VM-Monitoring-managed_identity_operator"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/89789f53-a3d2-e17a-04d3-d0ea58ef1b42" },
  @{ Key = "Deploy-VM-Monitoring-monitoring_contributor"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/46e240ce-3577-8e1f-170b-1db83f4670df" },
  @{ Key = "Deploy-vmArc-ChangeTrack-managed_identity_operator"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/1ce57868-8ea2-5e6f-b305-c4ba88f13ca6" },
  @{ Key = "Deploy-vmArc-ChangeTrack-monitoring_contributor"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/7d9ee7bb-8c02-142f-61d6-33ec15d68c35" },
  @{ Key = "Deploy-vmHybr-Monitoring-managed_identity_operator"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/cb76f1e1-f453-b7a7-38b2-2f8958ef2022" },
  @{ Key = "Deploy-vmHybr-Monitoring-monitoring_contributor"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/82e8c35b-4da5-cfdf-e28d-8cc817a0de3e" },
  @{ Key = "Deploy-VMSS-ChangeTrack-managed_identity_operator"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/00b96df1-5405-bbcd-01d9-65d9b190bdc0" },
  @{ Key = "Deploy-VMSS-ChangeTrack-monitoring_contributor"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/d44706c4-e3e2-92bd-7f6c-2f6f0429b58c" },
  @{ Key = "Deploy-VMSS-Monitoring-managed_identity_operator"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/61025b41-966c-2aa8-0198-030890d659e5" },
  @{ Key = "Deploy-VMSS-Monitoring-monitoring_contributor"; Id = "/subscriptions/d775d3cc-7245-4744-aa69-bee03036114b/resourceGroups/rg-management-swedencentral/providers/Microsoft.Authorization/roleAssignments/cf0fa7b0-dcae-401f-874f-b07fdf6da8bc" }
)

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
  throw "terraform CLI not found in PATH"
}

if (-not (Test-Path $TerraformRoot)) {
  throw "TerraformRoot not found: $TerraformRoot"
}

Write-Host "Terraform root: $TerraformRoot"
Write-Host "Total imports: $($imports.Count)"

$commands = foreach ($item in $imports) {
  $address = "azurerm_role_assignment.landing_zones_policy_mi[\"$($item.Key)\"]"
  "terraform -chdir=`"$TerraformRoot`" import '$address' '$($item.Id)'"
}

if (-not $Execute) {
  Write-Host ""
  Write-Host "Dry-run mode. No changes made."
  Write-Host "Re-run with -Execute to perform import."
  Write-Host ""
  $commands | ForEach-Object { Write-Host $_ }
  exit 0
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupPath = Join-Path $TerraformRoot "state-backup-before-import-$timestamp.tfstate"

Write-Host "Creating state backup: $backupPath"
terraform -chdir="$TerraformRoot" state pull | Out-File -FilePath $backupPath -Encoding utf8

$failures = @()

foreach ($item in $imports) {
  $address = "azurerm_role_assignment.landing_zones_policy_mi[\"$($item.Key)\"]"
  Write-Host "Importing: $address"
  try {
    terraform -chdir="$TerraformRoot" import $address $item.Id | Out-Host
  }
  catch {
    $failures += [pscustomobject]@{ Address = $address; Id = $item.Id; Error = $_.Exception.Message }
  }
}

if ($failures.Count -gt 0) {
  Write-Host ""
  Write-Host "Completed with failures: $($failures.Count)"
  $failures | Format-Table -AutoSize | Out-String -Width 300 | Write-Host
  exit 1
}

Write-Host ""
Write-Host "All imports completed successfully."
Write-Host "Run next: terraform -chdir=\"$TerraformRoot\" plan -input=false"
