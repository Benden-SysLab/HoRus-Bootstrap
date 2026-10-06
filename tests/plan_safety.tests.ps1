#requires -Version 7.0
param([Parameter(Mandatory)][string] $PlanJsonPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$plan = Get-Content -LiteralPath $PlanJsonPath -Raw | ConvertFrom-Json -Depth 100
$destructive = @($plan.resource_changes | Where-Object {
  $_.type -in @('proxmox_virtual_environment_container', 'proxmox_virtual_environment_vm') -and
  $_.change.actions -contains 'delete'
})
if ($destructive.Count) {
  throw "Plan contains Proxmox workload destroy/replace: $($destructive.address -join ', ')"
}
Write-Host 'PASS: Proxmox VM/LXC destroy or replace = 0.'
