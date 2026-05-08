param(
  [Parameter(Mandatory = $true)]
  [string]$VmResourceGroup,

  [Parameter(Mandatory = $true)]
  [string]$VmName,

  [Parameter(Mandatory = $true)]
  [string]$DcrResourceGroup,

  [Parameter(Mandatory = $true)]
  [string]$DcrName,

  [string]$VmSubscriptionId = "08436ef1-79fc-4f99-a8c3-1ea611f64196",
  [string]$ManagementSubscriptionId = "b9794400-1ef6-405c-be7f-2e24ba8bfa1b",
  [string]$WorkspaceResourceGroup = "",
  [string]$WorkspaceName = "",
  [switch]$CreateAssociation
)

$ErrorActionPreference = "Stop"

function Invoke-AzJson {
  param([string]$Command)
  $raw = Invoke-Expression $Command
  if (-not $raw) { return $null }
  return $raw | ConvertFrom-Json -Depth 100
}

Write-Host "[1/7] Reading VM metadata from subscription: $VmSubscriptionId"
$vm = Invoke-AzJson "az vm show --subscription `"$VmSubscriptionId`" --resource-group `"$VmResourceGroup`" --name `"$VmName`" -o json"
if (-not $vm) { throw "VM not found: $VmResourceGroup/$VmName in subscription $VmSubscriptionId" }
$vmId = $vm.id
$vmLocation = $vm.location
Write-Host "VM ID: $vmId"
Write-Host "VM Location: $vmLocation"

$vmStatusCodes = az vm get-instance-view --subscription "$VmSubscriptionId" --resource-group "$VmResourceGroup" --name "$VmName" --query "instanceView.statuses[].code" -o tsv
$powerState = ($vmStatusCodes | Select-String "^PowerState/").Line
if ($powerState) {
  Write-Host "VM Power State: $powerState"
  if ($powerState -ne "PowerState/running") {
    Write-Warning "VM is not running. No Heartbeat/InsightsMetrics ingestion will occur while VM is stopped/deallocated."
  }
}

Write-Host "[2/7] Checking Azure Monitor Agent extensions"
$extensions = Invoke-AzJson "az vm extension list --subscription `"$VmSubscriptionId`" --resource-group `"$VmResourceGroup`" --vm-name `"$VmName`" -o json"
$ama = @($extensions | Where-Object {
  $_.name -in @('AzureMonitorWindowsAgent', 'AzureMonitorLinuxAgent') -or
  $_.type -in @('AzureMonitorWindowsAgent', 'AzureMonitorLinuxAgent')
})
if ($ama.Count -eq 0) {
  Write-Warning "No Azure Monitor Agent extension found on VM."
} else {
  $ama | ForEach-Object {
    $extName = if ($_.name) { $_.name } else { $_.type }
    Write-Host ("AMA Extension: {0} | Publisher: {1} | ProvisioningState: {2}" -f $extName, $_.publisher, $_.provisioningState)
  }
}

Write-Host "[3/7] Reading DCR from management subscription: $ManagementSubscriptionId"
$dcr = Invoke-AzJson "az monitor data-collection rule show --subscription `"$ManagementSubscriptionId`" --resource-group `"$DcrResourceGroup`" --name `"$DcrName`" -o json"
if (-not $dcr) { throw "DCR not found: $DcrResourceGroup/$DcrName in subscription $ManagementSubscriptionId" }
$dcrId = $dcr.id
$dcrLocation = $dcr.location
Write-Host "DCR ID: $dcrId"
Write-Host "DCR Location: $dcrLocation"
if ($vmLocation -ne $dcrLocation) {
  Write-Warning "VM location and DCR location differ. This can block ingestion. VM=$vmLocation DCR=$dcrLocation"
}

Write-Host "[4/7] Checking DCR association on VM"
$assocs = Invoke-AzJson "az monitor data-collection rule association list --subscription `"$VmSubscriptionId`" --resource `"$vmId`" -o json"
if (-not $assocs) { $assocs = @() }
$existing = @($assocs | Where-Object { $_.dataCollectionRuleId -eq $dcrId })
if ($existing.Count -gt 0) {
  Write-Host "Association already exists for this DCR."
} else {
  Write-Warning "No association found for this DCR on VM."
  if ($CreateAssociation) {
    $assocName = "assoc-$VmName-$DcrName"
    if ($assocName.Length -gt 64) { $assocName = $assocName.Substring(0,64) }
    Write-Host "Creating association: $assocName"
    az monitor data-collection rule association create --subscription "$VmSubscriptionId" --name "$assocName" --rule-id "$dcrId" --resource "$vmId" | Out-Null
    Write-Host "Association created."
  } else {
    Write-Host "CreateAssociation not set. Skipping create."
  }
}

Write-Host "[5/7] Showing current VM associations"
az monitor data-collection rule association list --subscription "$VmSubscriptionId" --resource "$vmId" -o table

Write-Host "[6/7] Optional workspace heartbeat check"
if ($WorkspaceName -and $WorkspaceResourceGroup) {
  $ws = Invoke-AzJson "az monitor log-analytics workspace show --subscription `"$ManagementSubscriptionId`" --resource-group `"$WorkspaceResourceGroup`" --workspace-name `"$WorkspaceName`" -o json"
  if (-not $ws) {
    Write-Warning "Workspace not found: $WorkspaceResourceGroup/$WorkspaceName"
  } else {
    $query = "Heartbeat | where TimeGenerated > ago(30m) | where Computer contains '$VmName' | sort by TimeGenerated desc | take 10"
    Write-Host "Running query: $query"
    az monitor log-analytics query --subscription "$ManagementSubscriptionId" --workspace "$($ws.customerId)" --analytics-query "$query" -o table
  }
} else {
  Write-Host "Workspace parameters not provided. Skipping heartbeat query."
}

Write-Host "[7/7] Completed."
